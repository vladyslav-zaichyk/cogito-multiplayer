extends Node
## Network Interactable Component
## Synchronizes state of interactive objects (doors, switches, etc.) in multiplayer
## Attach this to a CogitoDoor, CogitoSwitch, or other interactable object

## Enable/disable logging
var enable_logging: bool = true  # Enable by default for debugging interactables

## Reference to the parent interactable object
var parent_interactable: Node = null

## Unique network ID for this interactable (based on scene path)
var network_id: String = ""

## Type of interactable (DOOR, SWITCH, etc.)
enum InteractableType { DOOR, SWITCH, UNKNOWN }
var interactable_type: InteractableType = InteractableType.UNKNOWN

## Last synced state (to avoid duplicate syncs)
var last_synced_state: Dictionary = {}

## Is this the host? (only host can change state)
var is_host: bool = false


func _ready() -> void:
	parent_interactable = get_parent()
	if not parent_interactable:
		push_error("NetworkInteractable: Parent must be an interactable object")
		return
	
	# Wait a frame for parent to be initialized
	await get_tree().process_frame
	
	# Determine interactable type
	if parent_interactable is CogitoDoor:
		interactable_type = InteractableType.DOOR
		_setup_door()
	elif parent_interactable is CogitoSwitch:
		interactable_type = InteractableType.SWITCH
		_setup_switch()
	else:
		CogitoGlobals.debug_log(
			true,
			"NetworkInteractable",
			"Warning: Unknown interactable type: %s" % parent_interactable.get_class()
		)
		return
	
	# Generate network ID based on scene path
	network_id = _generate_network_id()
	
	# Check if we're the host
	if NetworkManager:
		is_host = NetworkManager.is_host()
	
	# Initialize last synced state
	_update_last_synced_state()
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"Initialized for %s (type: %s, network_id: %s, is_host: %s)" % [
			parent_interactable.name,
			InteractableType.keys()[interactable_type],
			network_id,
			is_host
		]
	)
	
	# If we're the host and multiplayer is active, sync initial state to all clients
	if NetworkManager and NetworkManager.is_multiplayer() and is_host:
		# Wait a bit for all clients to connect
		await get_tree().create_timer(0.5).timeout
		_sync_state_to_clients()


## Setup for CogitoDoor
func _setup_door() -> void:
	if not parent_interactable.has_signal("door_state_changed"):
		push_error("NetworkInteractable: CogitoDoor missing door_state_changed signal")
		return
	
	# Connect to door state signals
	var connected = parent_interactable.door_state_changed.connect(_on_door_state_changed)
	if connected != OK:
		push_error("NetworkInteractable: Failed to connect door_state_changed signal: %d" % connected)
	
	# Also connect to lock state if available
	if parent_interactable.has_signal("lock_state_changed"):
		connected = parent_interactable.lock_state_changed.connect(_on_door_lock_state_changed)
		if connected != OK:
			push_error("NetworkInteractable: Failed to connect lock_state_changed signal: %d" % connected)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"Connected to CogitoDoor signals (door_state_changed: %s, lock_state_changed: %s)" % [
			parent_interactable.door_state_changed.is_connected(_on_door_state_changed),
			parent_interactable.has_signal("lock_state_changed") and parent_interactable.lock_state_changed.is_connected(_on_door_lock_state_changed) if parent_interactable.has_signal("lock_state_changed") else false
		]
	)


## Setup for CogitoSwitch
func _setup_switch() -> void:
	if not parent_interactable.has_signal("switched"):
		push_error("NetworkInteractable: CogitoSwitch missing switched signal")
		return
	
	# Connect to switch state signal
	var connected = parent_interactable.switched.connect(_on_switch_state_changed)
	if connected != OK:
		push_error("NetworkInteractable: Failed to connect switched signal: %d" % connected)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"Connected to CogitoSwitch signals (switched: %s)" % [
			parent_interactable.switched.is_connected(_on_switch_state_changed)
		]
	)


## Generate unique network ID for this interactable
func _generate_network_id() -> String:
	# Use scene path as network ID (unique per scene instance)
	var scene = get_tree().current_scene
	if not scene:
		push_error("NetworkInteractable: No current scene for network_id generation")
		return ""
	
	var scene_path = scene.scene_file_path
	var node_path = parent_interactable.get_path()
	
	# Combine scene path and node path for unique ID
	var id = "%s::%s" % [scene_path, str(node_path)]
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"Generated network_id: %s (scene: %s, path: %s)" % [id, scene_path, node_path]
	)
	
	return id


## Called when door state changes
func _on_door_state_changed(is_open: bool) -> void:
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"[DOOR STATE CHANGED] Signal received: is_open=%s (is_host: %s, multiplayer: %s)" % [
			is_open,
			is_host,
			NetworkManager.is_multiplayer() if NetworkManager else false
		]
	)
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkInteractable",
			"[DOOR STATE CHANGED] Skipping - not in multiplayer"
		)
		return
	
	# Only host can change state and sync it
	if not is_host:
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkInteractable",
			"[DOOR STATE CHANGED] Skipping - not host"
		)
		return
	
	var door = parent_interactable as CogitoDoor
	if not door:
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkInteractable",
			"[DOOR STATE CHANGED] Error - parent is not CogitoDoor"
		)
		return
	
	# Prepare state dictionary
	var state = {
		"is_open": is_open,
		"is_locked": door.is_locked if "is_locked" in door else false
	}
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"[DOOR STATE CHANGED] State: %s (has_changed: %s)" % [state, _has_state_changed(state)]
	)
	
	# Check if state actually changed
	if _has_state_changed(state):
		_sync_state_to_clients(state)
		_update_last_synced_state(state)
	else:
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkInteractable",
			"[DOOR STATE CHANGED] State unchanged, skipping sync"
		)


## Called when door lock state changes
func _on_door_lock_state_changed(is_locked: bool) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# Only host can change state and sync it
	if not is_host:
		return
	
	var door = parent_interactable as CogitoDoor
	if not door:
		return
	
	# Prepare state dictionary
	var state = {
		"is_open": door.is_open if "is_open" in door else false,
		"is_locked": is_locked
	}
	
	# Check if state actually changed
	if _has_state_changed(state):
		_sync_state_to_clients(state)
		_update_last_synced_state(state)


## Called when switch state changes
func _on_switch_state_changed(is_on: bool) -> void:
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"[SWITCH STATE CHANGED] Signal received: is_on=%s (is_host: %s, multiplayer: %s)" % [
			is_on,
			is_host,
			NetworkManager.is_multiplayer() if NetworkManager else false
		]
	)
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkInteractable",
			"[SWITCH STATE CHANGED] Skipping - not in multiplayer"
		)
		return
	
	# Only host can change state and sync it
	if not is_host:
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkInteractable",
			"[SWITCH STATE CHANGED] Skipping - not host"
		)
		return
	
	var state = {
		"is_on": is_on
	}
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"[SWITCH STATE CHANGED] State: %s (has_changed: %s)" % [state, _has_state_changed(state)]
	)
	
	# Check if state actually changed
	if _has_state_changed(state):
		_sync_state_to_clients(state)
		_update_last_synced_state(state)
	else:
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkInteractable",
			"[SWITCH STATE CHANGED] State unchanged, skipping sync"
		)


## Check if state has changed
func _has_state_changed(new_state: Dictionary) -> bool:
	if last_synced_state.is_empty():
		return true
	
	# Compare all keys
	for key in new_state:
		if not key in last_synced_state or last_synced_state[key] != new_state[key]:
			return true
	
	return false


## Update last synced state
func _update_last_synced_state(state: Dictionary = {}) -> void:
	if state.is_empty():
		# Get current state from parent
		if interactable_type == InteractableType.DOOR:
			var door = parent_interactable as CogitoDoor
			if door:
				last_synced_state = {
					"is_open": door.is_open if "is_open" in door else false,
					"is_locked": door.is_locked if "is_locked" in door else false
				}
		elif interactable_type == InteractableType.SWITCH:
			var switch = parent_interactable as CogitoSwitch
			if switch:
				last_synced_state = {
					"is_on": switch.is_on if "is_on" in switch else false
				}
	else:
		last_synced_state = state.duplicate()


## Sync state to all clients
func _sync_state_to_clients(state: Dictionary = {}) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	if state.is_empty():
		# Get current state
		_update_last_synced_state()
		state = last_synced_state
	
	# Prepare data for RPC
	var interactable_data = {
		"network_id": network_id,
		"type": InteractableType.keys()[interactable_type],
		"state": state
	}
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"[HOST] Syncing state for %s: %s" % [network_id, state]
	)
	
	# Send RPC through NetworkManager
	NetworkManager.sync_interactable_state.rpc(interactable_data)


## Receive state update from network (called by NetworkManager RPC)
func _receive_state_update(interactable_data: Dictionary) -> void:
	var received_id = interactable_data.get("network_id", "")
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"[RPC RECEIVED] network_id=%s (ours: %s, is_host: %s)" % [received_id, network_id, is_host]
	)
	
	# Only process if this is about us
	if received_id != network_id:
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkInteractable",
			"[RPC RECEIVED] ID mismatch, ignoring (received: %s, ours: %s)" % [received_id, network_id]
		)
		return
	
	# Don't process if we're the host (we already have the correct state)
	if is_host:
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkInteractable",
			"[RPC RECEIVED] We are host, ignoring (already have correct state)"
		)
		return
	
	var state = interactable_data.get("state", {})
	var type_str = interactable_data.get("type", "")
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"[CLIENT] Received state update for %s: %s (type: %s)" % [network_id, state, type_str]
	)
	
	# Apply state based on type
	if type_str == "DOOR":
		_apply_door_state(state)
	elif type_str == "SWITCH":
		_apply_switch_state(state)
	
	# Update last synced state
	_update_last_synced_state(state)


## Apply door state (client-side)
func _apply_door_state(state: Dictionary) -> void:
	var door = parent_interactable as CogitoDoor
	if not door:
		return
	
	var is_open = state.get("is_open", false)
	var is_locked = state.get("is_locked", false)
	
	# Temporarily disconnect signals to avoid feedback loop
	if door.door_state_changed.is_connected(_on_door_state_changed):
		door.door_state_changed.disconnect(_on_door_state_changed)
	if door.has_signal("lock_state_changed") and door.lock_state_changed.is_connected(_on_door_lock_state_changed):
		door.lock_state_changed.disconnect(_on_door_lock_state_changed)
	
	# Apply lock state first (if changed)
	if "is_locked" in door and door.is_locked != is_locked:
		door.is_locked = is_locked
		if is_locked:
			door.lock_door()
		else:
			door.unlock_door()
	
	# Apply open/close state
	if "is_open" in door and door.is_open != is_open:
		# Directly set state and trigger animation/movement without interactor
		door.is_open = is_open
		
		if is_open:
			# Open door - handle different door types
			if door.door_type == CogitoDoor.DoorType.ANIMATED:
				if door.animation_player:
					door.animation_player.play(door.opening_animation)
			elif door.door_type == CogitoDoor.DoorType.ROTATING:
				# For rotating doors, use default swing direction (no interactor)
				door.target_rotation_vector = door.open_rotation
				door.is_moving = true
			else:
				# Sliding door
				var tween_door = get_tree().create_tween()
				tween_door.tween_property(door, "position", door.open_position, door.door_speed)
			
			door.interaction_text = door.interaction_text_when_open
			door.object_state_updated.emit(door.interaction_text)
		else:
			# Close door
			if door.close_timer:
				door.close_timer.queue_free()
			
			if door.door_type == CogitoDoor.DoorType.ANIMATED:
				if door.animation_player:
					if door.reverse_opening_anim_for_close:
						door.animation_player.play_backwards(door.opening_animation)
					else:
						door.animation_player.play(door.closing_animation)
			elif door.door_type == CogitoDoor.DoorType.ROTATING:
				door.target_rotation_vector = door.closed_rotation
				door.is_moving = true
			else:
				# Sliding door
				var tween_door = get_tree().create_tween()
				tween_door.tween_property(door, "position", door.closed_position, door.door_speed)
			
			door.interaction_text = door.interaction_text_when_closed
			door.object_state_updated.emit(door.interaction_text)
		
		# Emit signal manually (since we disconnected it)
		door.door_state_changed.emit(is_open)
	
	# Reconnect signals
	if not door.door_state_changed.is_connected(_on_door_state_changed):
		door.door_state_changed.connect(_on_door_state_changed)
	if door.has_signal("lock_state_changed") and not door.lock_state_changed.is_connected(_on_door_lock_state_changed):
		door.lock_state_changed.connect(_on_door_lock_state_changed)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"[CLIENT] Applied door state: is_open=%s, is_locked=%s" % [is_open, is_locked]
	)


## Apply switch state (client-side)
func _apply_switch_state(state: Dictionary) -> void:
	var switch = parent_interactable as CogitoSwitch
	if not switch:
		return
	
	var is_on = state.get("is_on", false)
	
	# Temporarily disconnect signal to avoid feedback loop
	if switch.switched.is_connected(_on_switch_state_changed):
		switch.switched.disconnect(_on_switch_state_changed)
	
	# Apply state
	if "is_on" in switch and switch.is_on != is_on:
		if is_on:
			switch.switch_on()
		else:
			switch.switch_off()
	
	# Reconnect signal
	if not switch.switched.is_connected(_on_switch_state_changed):
		switch.switched.connect(_on_switch_state_changed)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"[CLIENT] Applied switch state: is_on=%s" % is_on
	)

