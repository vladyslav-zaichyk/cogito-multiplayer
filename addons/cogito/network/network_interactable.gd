extends Node
## Network Interactable Component
## Synchronizes state of interactive objects (doors, switches, etc.) in multiplayer
## Attach this to a CogitoDoor, CogitoSwitch, or other interactable object

## Preload required classes
const InventorySlotPD = preload("res://addons/cogito/inventory_pd/CustomResources/InventorySlotPD.gd")
const CogitoTurnwheel = preload("res://addons/cogito/cogito_objects/cogito_turnwheel.gd")

## Enable/disable logging
var enable_logging: bool = false  # Disabled by default

## Reference to the parent interactable object
var parent_interactable: Node = null

## Unique network ID for this interactable (based on scene path)
var network_id: String = ""

## Type of interactable (DOOR, SWITCH, etc.)
enum InteractableType { DOOR, SWITCH, CONTAINER, TURNWHEEL, UNKNOWN }
var interactable_type: InteractableType = InteractableType.UNKNOWN

## Last synced state (to avoid duplicate syncs)
var last_synced_state: Dictionary = {}

## Is this the host? (only host can change state)
var is_host: bool = false

## Flag to prevent recursive RPC calls when applying state from network
var _is_applying_network_state: bool = false


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
	elif parent_interactable is CogitoContainer:
		interactable_type = InteractableType.CONTAINER
		_setup_container()
	elif parent_interactable is CogitoTurnwheel:
		interactable_type = InteractableType.TURNWHEEL
		_setup_turnwheel()
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


## Setup for CogitoTurnwheel
func _setup_turnwheel() -> void:
	var turnwheel = parent_interactable as CogitoTurnwheel
	if not turnwheel:
		return
	
	# Connect to turnwheel state signal
	if turnwheel.has_signal("turnwheel_state_changed"):
		var connected = turnwheel.turnwheel_state_changed.connect(_on_turnwheel_state_changed)
		if connected != OK:
			push_error("NetworkInteractable: Failed to connect turnwheel_state_changed signal: %d" % connected)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"Connected to CogitoTurnwheel signals"
	)


## Setup for CogitoContainer
func _setup_container() -> void:
	var container = parent_interactable as CogitoContainer
	if not container:
		return
	
	# Connect to container signals
	# Note: toggle_inventory is emitted when player interacts, but we need to track open/close state
	# We'll use container_closed signal and check interaction_text to determine state
	if container.has_signal("container_closed"):
		var connected = container.container_closed.connect(_on_container_closed)
		if connected != OK:
			push_error("NetworkInteractable: Failed to connect container_closed signal: %d" % connected)
	
	# Also connect to inventory_updated to sync inventory changes
	if container.inventory_data and container.inventory_data.has_signal("inventory_updated"):
		var connected = container.inventory_data.inventory_updated.connect(_on_container_inventory_updated)
		if connected != OK:
			push_error("NetworkInteractable: Failed to connect inventory_updated signal: %d" % connected)
	
	# Connect to toggle_inventory to detect when container is opened
	if container.has_signal("toggle_inventory"):
		var connected = container.toggle_inventory.connect(_on_container_toggled)
		if connected != OK:
			push_error("NetworkInteractable: Failed to connect toggle_inventory signal: %d" % connected)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInteractable",
		"Connected to CogitoContainer signals"
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
	# Don't sync if we're applying state from network (to avoid feedback loop)
	if _is_applying_network_state:
		print("[NetworkInteractable] [%s] Door state changed but skipping - applying network state" % ["HOST" if is_host else "CLIENT"])
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	var door = parent_interactable as CogitoDoor
	if not door:
		return
	
	# Prepare state dictionary
	var current_is_locked = door.is_locked if "is_locked" in door else false
	var state = {
		"is_open": is_open,
		"is_locked": current_is_locked
	}
	
	print("[NetworkInteractable] [%s] Door state changed signal: is_open=%s, is_locked=%s, last_synced=%s" % [
		"HOST" if is_host else "CLIENT",
		is_open,
		current_is_locked,
		last_synced_state
	])
	
	# Check if state actually changed
	var has_changed = _has_state_changed(state)
	print("[NetworkInteractable] [%s] State changed check: %s" % ["HOST" if is_host else "CLIENT", has_changed])
	
	if has_changed:
		print("[NetworkInteractable] [%s] Door state changed: is_open=%s, sending RPC" % ["HOST" if is_host else "CLIENT", is_open])
		_sync_state_to_clients(state)
		_update_last_synced_state(state)
	else:
		print("[NetworkInteractable] [%s] Door state unchanged, skipping RPC" % ["HOST" if is_host else "CLIENT"])


## Called when door lock state changes
func _on_door_lock_state_changed(is_locked: bool) -> void:
	# Don't sync if we're applying state from network (to avoid feedback loop)
	if _is_applying_network_state:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
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
		print("[NetworkInteractable] [%s] Door lock state changed: is_locked=%s, sending RPC" % ["HOST" if is_host else "CLIENT", is_locked])
		_sync_state_to_clients(state)
		_update_last_synced_state(state)


## Called when switch state changes
func _on_switch_state_changed(is_on: bool) -> void:
	# Don't sync if we're applying state from network (to avoid feedback loop)
	if _is_applying_network_state:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	var switch = parent_interactable as CogitoSwitch
	if not switch:
		return
	
	# Get actual current state from switch (signal might fire before state is updated)
	var actual_is_on = switch.is_on if "is_on" in switch else is_on
	
	var state = {
		"is_on": actual_is_on
	}
	
	# Check if state actually changed
	if _has_state_changed(state):
		print("[NetworkInteractable] [%s] Switch state changed: is_on=%s, sending RPC" % ["HOST" if is_host else "CLIENT", actual_is_on])
		_sync_state_to_clients(state)
		_update_last_synced_state(state)


## Called when container is toggled (opened/closed)
func _on_container_toggled(_external_inventory_owner) -> void:
	# Don't sync if we're applying state from network (to avoid feedback loop)
	if _is_applying_network_state:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	var container = parent_interactable as CogitoContainer
	if not container:
		return
	
	# Determine if container is open by checking interaction_text
	# If interaction_text matches text_when_open, container is open
	var is_open = false
	if container.interaction_text == tr(container.text_when_open):
		is_open = true
	elif container.interaction_text == tr(container.text_when_closed):
		is_open = false
	else:
		# Fallback: assume it's being opened if text doesn't match closed text
		# This handles the case when container is first opened
		is_open = (container.interaction_text != tr(container.text_when_closed))
	
	var state = {
		"is_open": is_open
	}
	
	# Check if state actually changed
	if _has_state_changed(state):
		print("[NetworkInteractable] [%s] Container toggled: is_open=%s, sending RPC" % ["HOST" if is_host else "CLIENT", is_open])
		_sync_state_to_clients(state)
		_update_last_synced_state(state)


## Called when container is closed
func _on_container_closed() -> void:
	# Don't sync if we're applying state from network (to avoid feedback loop)
	if _is_applying_network_state:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	var container = parent_interactable as CogitoContainer
	if not container:
		return
	
	var state = {
		"is_open": false
	}
	
	# Check if state actually changed
	if _has_state_changed(state):
		print("[NetworkInteractable] [%s] Container closed, sending RPC" % ["HOST" if is_host else "CLIENT"])
		_sync_state_to_clients(state)
		_update_last_synced_state(state)


## Called when turnwheel state changes
func _on_turnwheel_state_changed(has_been_turned: bool) -> void:
	# Don't sync if we're applying state from network (to avoid feedback loop)
	if _is_applying_network_state:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	var turnwheel = parent_interactable as CogitoTurnwheel
	if not turnwheel:
		return
	
	var state = {
		"has_been_turned": has_been_turned
	}
	
	# Check if state actually changed
	if _has_state_changed(state):
		print("[NetworkInteractable] [%s] Turnwheel state changed: has_been_turned=%s, sending RPC" % ["HOST" if is_host else "CLIENT", has_been_turned])
		_sync_state_to_clients(state)
		_update_last_synced_state(state)


## Called when container inventory is updated
func _on_container_inventory_updated(inventory_data: CogitoInventory) -> void:
	# Don't sync if we're applying state from network (to avoid feedback loop)
	if _is_applying_network_state:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	var container = parent_interactable as CogitoContainer
	if not container or container.inventory_data != inventory_data:
		return
	
	# Serialize inventory state
	var inventory_state = _serialize_container_inventory(inventory_data)
	
	var state = {
		"is_open": _get_container_open_state(container),
		"inventory": inventory_state
	}
	
	# Always sync inventory changes (they're important)
	print("[NetworkInteractable] [%s] Container inventory updated, sending RPC" % ["HOST" if is_host else "CLIENT"])
	_sync_state_to_clients(state)
	_update_last_synced_state(state)


## Helper: Get container open state
func _get_container_open_state(container: CogitoContainer) -> bool:
	if container.interaction_text == tr(container.text_when_open):
		return true
	elif container.interaction_text == tr(container.text_when_closed):
		return false
	else:
		# Fallback: assume closed if text doesn't match
		return false


## Helper: Serialize container inventory
func _serialize_container_inventory(inventory: CogitoInventory) -> Dictionary:
	var serialized = {
		"slots": []
	}
	
	for i in range(inventory.inventory_slots.size()):
		var slot = inventory.inventory_slots[i]
		if slot and slot.inventory_item:
			var slot_data = {
				"index": i,
				"item_name": slot.inventory_item.name,
				"quantity": slot.quantity if "quantity" in slot else 1
			}
			# Try to get resource path for proper deserialization
			if slot.inventory_item.resource_path:
				slot_data["resource_path"] = slot.inventory_item.resource_path
			elif slot.inventory_item.get_script() and slot.inventory_item.get_script().resource_path:
				slot_data["resource_path"] = slot.inventory_item.get_script().resource_path
			
			serialized.slots.append(slot_data)
	
	return serialized


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
		elif interactable_type == InteractableType.CONTAINER:
			var container = parent_interactable as CogitoContainer
			if container:
				last_synced_state = {
					"is_open": _get_container_open_state(container),
					"inventory": _serialize_container_inventory(container.inventory_data) if container.inventory_data else {}
				}
		elif interactable_type == InteractableType.TURNWHEEL:
			var turnwheel = parent_interactable as CogitoTurnwheel
			if turnwheel:
				last_synced_state = {
					"has_been_turned": turnwheel.has_been_turned if "has_been_turned" in turnwheel else false
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
	
	print("[NetworkInteractable] [%s] Calling RPC sync_interactable_state for %s: %s" % [
		"HOST" if is_host else "CLIENT",
		parent_interactable.name if parent_interactable else "unknown",
		state
	])
	
	# Send RPC through NetworkManager
	NetworkManager.sync_interactable_state.rpc(interactable_data)


## Receive state update from network (called by NetworkManager RPC)
func _receive_state_update(interactable_data: Dictionary) -> void:
	var received_id = interactable_data.get("network_id", "")
	
	# Only process if this is about us
	if received_id != network_id:
		return
	
	var state = interactable_data.get("state", {})
	var type_str = interactable_data.get("type", "")
	
	print("[NetworkInteractable] [%s] Received RPC for %s: %s" % [
		"HOST" if is_host else "CLIENT",
		parent_interactable.name if parent_interactable else "unknown",
		state
	])
	
	# Check if this is our own RPC (state already matches current state)
	# If so, we don't need to apply it, just update last_synced_state
	var is_own_rpc = false
	if type_str == "DOOR":
		var door = parent_interactable as CogitoDoor
		if door:
			var current_is_open = door.is_open if "is_open" in door else false
			var current_is_locked = door.is_locked if "is_locked" in door else false
			var received_is_open = state.get("is_open", false)
			var received_is_locked = state.get("is_locked", false)
			
			if current_is_open == received_is_open and current_is_locked == received_is_locked:
				is_own_rpc = true
				print("[NetworkInteractable] [%s] Received own RPC (state matches), skipping apply" % ["HOST" if is_host else "CLIENT"])
	elif type_str == "SWITCH":
		var switch = parent_interactable as CogitoSwitch
		if switch:
			var current_is_on = switch.is_on if "is_on" in switch else false
			var received_is_on = state.get("is_on", false)
			
			if current_is_on == received_is_on:
				is_own_rpc = true
				print("[NetworkInteractable] [%s] Received own RPC (state matches), skipping apply" % ["HOST" if is_host else "CLIENT"])
	elif type_str == "CONTAINER":
		var container = parent_interactable as CogitoContainer
		if container:
			var current_is_open = _get_container_open_state(container)
			var received_is_open = state.get("is_open", false)
			
			# For containers, we also check inventory state if present
			var inventory_matches = true
			if "inventory" in state and container.inventory_data:
				var current_inventory = _serialize_container_inventory(container.inventory_data)
				var received_inventory = state.get("inventory", {})
				# Simple comparison: check if slot counts match
				var current_slots = current_inventory.get("slots", [])
				var received_slots = received_inventory.get("slots", [])
				if current_slots.size() != received_slots.size():
					inventory_matches = false
			
			if current_is_open == received_is_open and inventory_matches:
				is_own_rpc = true
				print("[NetworkInteractable] [%s] Received own RPC (state matches), skipping apply" % ["HOST" if is_host else "CLIENT"])
	elif type_str == "TURNWHEEL":
		var turnwheel = parent_interactable as CogitoTurnwheel
		if turnwheel:
			var current_has_been_turned = turnwheel.has_been_turned if "has_been_turned" in turnwheel else false
			var received_has_been_turned = state.get("has_been_turned", false)
			
			if current_has_been_turned == received_has_been_turned:
				is_own_rpc = true
				print("[NetworkInteractable] [%s] Received own RPC (state matches), skipping apply" % ["HOST" if is_host else "CLIENT"])
	
	# Only apply state if it's different (not our own RPC)
	if not is_own_rpc:
		# Apply state based on type
		if type_str == "DOOR":
			_apply_door_state(state)
		elif type_str == "SWITCH":
			_apply_switch_state(state)
		elif type_str == "CONTAINER":
			_apply_container_state(state)
		elif type_str == "TURNWHEEL":
			_apply_turnwheel_state(state)
	
	# Update last synced state
	_update_last_synced_state(state)


## Apply door state (client-side)
func _apply_door_state(state: Dictionary) -> void:
	var door = parent_interactable as CogitoDoor
	if not door:
		return
	
	var is_open = state.get("is_open", false)
	var is_locked = state.get("is_locked", false)
	
	# Set flag to prevent feedback loop
	_is_applying_network_state = true
	
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
	
	# Clear flag after a frame to allow future local changes
	await get_tree().process_frame
	_is_applying_network_state = false


## Apply switch state (client-side)
func _apply_switch_state(state: Dictionary) -> void:
	var switch = parent_interactable as CogitoSwitch
	if not switch:
		return
	
	var is_on = state.get("is_on", false)
	
	# Set flag to prevent feedback loop
	_is_applying_network_state = true
	
	# Temporarily disconnect signal to avoid feedback loop
	if switch.switched.is_connected(_on_switch_state_changed):
		switch.switched.disconnect(_on_switch_state_changed)
	
	# Apply state only if it's different
	if "is_on" in switch and switch.is_on != is_on:
		if is_on:
			switch.switch_on()
		else:
			switch.switch_off()
	
	# Reconnect signal
	if not switch.switched.is_connected(_on_switch_state_changed):
		switch.switched.connect(_on_switch_state_changed)
	
	# Clear flag after a frame to allow future local changes
	await get_tree().process_frame
	_is_applying_network_state = false


## Apply container state (client-side)
func _apply_container_state(state: Dictionary) -> void:
	var container = parent_interactable as CogitoContainer
	if not container:
		return
	
	var is_open = state.get("is_open", false)
	var inventory_state = state.get("inventory", {})
	
	# Set flag to prevent feedback loop
	_is_applying_network_state = true
	
	# Temporarily disconnect signals to avoid feedback loop
	if container.has_signal("container_closed") and container.container_closed.is_connected(_on_container_closed):
		container.container_closed.disconnect(_on_container_closed)
	if container.has_signal("toggle_inventory") and container.toggle_inventory.is_connected(_on_container_toggled):
		container.toggle_inventory.disconnect(_on_container_toggled)
	if container.inventory_data and container.inventory_data.has_signal("inventory_updated") and container.inventory_data.inventory_updated.is_connected(_on_container_inventory_updated):
		container.inventory_data.inventory_updated.disconnect(_on_container_inventory_updated)
	
	# Apply open/close state
	var current_is_open = _get_container_open_state(container)
	if current_is_open != is_open:
		if is_open:
			container.open()
		else:
			container.close()
	
	# Apply inventory state if provided
	if not inventory_state.is_empty() and container.inventory_data:
		_apply_container_inventory(container.inventory_data, inventory_state)
	
	# Reconnect signals
	if container.has_signal("container_closed") and not container.container_closed.is_connected(_on_container_closed):
		container.container_closed.connect(_on_container_closed)
	if container.has_signal("toggle_inventory") and not container.toggle_inventory.is_connected(_on_container_toggled):
		container.toggle_inventory.connect(_on_container_toggled)
	if container.inventory_data and container.inventory_data.has_signal("inventory_updated") and not container.inventory_data.inventory_updated.is_connected(_on_container_inventory_updated):
		container.inventory_data.inventory_updated.connect(_on_container_inventory_updated)
	
	# Clear flag after a frame to allow future local changes
	await get_tree().process_frame
	_is_applying_network_state = false


## Helper: Apply container inventory state
func _apply_container_inventory(inventory: CogitoInventory, inventory_state: Dictionary) -> void:
	# Clear existing inventory
	for i in range(inventory.inventory_slots.size()):
		inventory.inventory_slots[i] = null
	
	# Apply serialized inventory
	var slots = inventory_state.get("slots", [])
	for slot_data in slots:
		var index = slot_data.get("index", -1)
		if index < 0 or index >= inventory.inventory_slots.size():
			continue
		
		# Try to load item from resource path
		var item_resource = null
		if "resource_path" in slot_data:
			item_resource = load(slot_data.resource_path) as InventoryItemPD
		
		# If resource loading failed, try to find by name
		if not item_resource:
			# This is a fallback - in a real implementation, you'd want a better lookup system
			push_warning("NetworkInteractable: Could not load item from resource_path: %s" % slot_data.get("resource_path", ""))
			continue
		
		# Create slot data
		var slot = InventorySlotPD.new()
		slot.inventory_item = item_resource
		slot.quantity = slot_data.get("quantity", 1)
		slot.origin_index = index
		
		inventory.inventory_slots[index] = slot
	
	# Emit inventory updated signal
	inventory._emit_inventory_updated()


## Apply turnwheel state (client-side)
func _apply_turnwheel_state(state: Dictionary) -> void:
	var turnwheel = parent_interactable as CogitoTurnwheel
	if not turnwheel:
		return
	
	var has_been_turned = state.get("has_been_turned", false)
	
	# Set flag to prevent feedback loop
	_is_applying_network_state = true
	
	# Temporarily disconnect signal to avoid feedback loop
	if turnwheel.has_signal("turnwheel_state_changed") and turnwheel.turnwheel_state_changed.is_connected(_on_turnwheel_state_changed):
		turnwheel.turnwheel_state_changed.disconnect(_on_turnwheel_state_changed)
	
	# Apply state only if it's different
	if "has_been_turned" in turnwheel and turnwheel.has_been_turned != has_been_turned:
		turnwheel.has_been_turned = has_been_turned
		# Note: We don't call interact() here because that would trigger nodes_to_trigger
		# The state change is enough - the visual rotation happens in _is_being_turned()
	
	# Reconnect signal
	if turnwheel.has_signal("turnwheel_state_changed") and not turnwheel.turnwheel_state_changed.is_connected(_on_turnwheel_state_changed):
		turnwheel.turnwheel_state_changed.connect(_on_turnwheel_state_changed)
	
	# Clear flag after a frame to allow future local changes
	await get_tree().process_frame
	_is_applying_network_state = false

