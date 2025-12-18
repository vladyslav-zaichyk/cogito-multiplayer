extends Node
## Network Attribute Synchronization Component
## Handles attribute synchronization for multiplayer players
## Attach this to a CharacterBody3D (like CogitoPlayer)

## Enable/disable logging
var enable_logging: bool = false

## Is this the local player?
var is_local: bool = false

## Peer ID of this player
var peer_id: int = -1

## Reference to the parent CharacterBody3D (CogitoPlayer)
var parent_body: CharacterBody3D = null

## Dictionary of tracked attributes: attribute_name -> CogitoAttribute
var tracked_attributes: Dictionary = {}


func _ready() -> void:
	parent_body = get_parent() as CharacterBody3D
	if not parent_body:
		push_error("NetworkAttributeSync: Parent must be a CharacterBody3D")
		return
	
	# Wait a frame for player to be initialized
	await get_tree().process_frame
	
	# Determine if this is local player
	if NetworkManager and NetworkManager.is_multiplayer() and multiplayer:
		var local_peer_id = NetworkManager.get_local_peer_id()
		
		# Check if parent has is_local_player property (CogitoPlayer)
		if parent_body.has_method("get") and parent_body.get("is_local_player") != null:
			is_local = parent_body.is_local_player
		elif PlayerManager:
			# Check if this player is registered as local player
			var player_id = PlayerManager.get_player_id(parent_body)
			is_local = (PlayerManager.has_local_player() and PlayerManager.get_local_player_id() == player_id)
		else:
			# Fallback: assume local if we're the host
			is_local = NetworkManager.is_host()
		
		# Get peer_id
		if is_local:
			peer_id = local_peer_id
		else:
			# For remote players, get peer_id from PlayerManager
			if PlayerManager:
				var player_id = PlayerManager.get_player_id(parent_body)
				if player_id != -1:
					peer_id = PlayerManager.get_player_peer_id(player_id)
					if peer_id == -1:
						# Fallback: try to get from parent if it has peer_id
						if parent_body.has_method("get") and parent_body.get("peer_id") != null:
							peer_id = parent_body.peer_id
						else:
							peer_id = local_peer_id  # Temporary fallback
				else:
					peer_id = local_peer_id  # Temporary fallback
			else:
				peer_id = local_peer_id  # Temporary fallback
	else:
		# Single-player: always local
		is_local = true
		peer_id = 1
	
	# Wait for player attributes to be initialized
	# Need to wait a bit more for CogitoPlayer to fully initialize attributes
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Setup attribute tracking
	_setup_attribute_tracking()
	
	# If this is a remote player, request initial attribute sync from host
	if not is_local and NetworkManager and NetworkManager.is_multiplayer() and NetworkManager.is_connected_client():
		# Wait a bit more to ensure player is fully spawned
		await get_tree().create_timer(0.5).timeout
		_request_initial_attributes.rpc_id(1)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkAttributeSync",
		"Initialized for %s player (peer_id: %d), tracking %d attributes" % ["local" if is_local else "remote", peer_id, tracked_attributes.size()]
	)


## Setup tracking for all player attributes
func _setup_attribute_tracking() -> void:
	if not parent_body or not parent_body.has_method("get"):
		return
	
	# Get player_attributes dictionary from CogitoPlayer
	var player_attributes = parent_body.get("player_attributes")
	if not player_attributes or not player_attributes is Dictionary:
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkAttributeSync",
			"Player attributes not found or not a Dictionary"
		)
		return
	
	# Track each attribute
	for attribute_name in player_attributes.keys():
		var attribute = player_attributes[attribute_name]
		if attribute and attribute.has_signal("attribute_changed"):
			tracked_attributes[attribute_name] = attribute
			
			# Connect to attribute_changed signal
			if is_local:
				# Local player: emit through NetworkEventBus when attribute changes
				# Connect without bind - we'll use attribute_name from the signal itself
				if not attribute.attribute_changed.is_connected(_on_local_attribute_changed):
					attribute.attribute_changed.connect(_on_local_attribute_changed)
					CogitoGlobals.debug_log(
						enable_logging,
						"NetworkAttributeSync",
						"Tracking local attribute: %s" % attribute_name
					)
			else:
				# Remote player: we'll receive updates via RPC
				CogitoGlobals.debug_log(
					enable_logging,
					"NetworkAttributeSync",
					"Tracking remote attribute: %s (will receive updates via RPC)" % attribute_name
				)


## Callback when local player's attribute changes
func _on_local_attribute_changed(attribute_name: String, value_current: float, value_max: float, has_increased: bool) -> void:
	if not is_local:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	if not is_inside_tree() or not multiplayer or not multiplayer.has_multiplayer_peer():
		return
	
	# Get player_id
	var player_id = -1
	if PlayerManager:
		player_id = PlayerManager.get_player_id(parent_body)
	
	if player_id == -1:
		return
	
	# Emit through NetworkEventBus (will be synced via RPC)
	if NetworkEventBus:
		NetworkEventBus.attribute_changed.emit(player_id, attribute_name, value_current, value_max)
	
	# Also send RPC directly for immediate sync
	NetworkManager.sync_player_attribute.rpc(peer_id, attribute_name, value_current, value_max)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkAttributeSync",
		"Local attribute changed: %s = %.2f/%.2f (increased: %s)" % [attribute_name, value_current, value_max, has_increased]
	)


## Receive attribute update from network (called via RPC)
func _receive_attribute_update(attribute_name: String, current_value: float, max_value: float) -> void:
	if is_local:
		return  # Don't update local player's attributes from network
	
	if not parent_body or not parent_body.has_method("get"):
		return
	
	# Get player_attributes dictionary
	var player_attributes = parent_body.get("player_attributes")
	if not player_attributes or not player_attributes is Dictionary:
		return
	
	# Get the attribute
	var attribute = player_attributes.get(attribute_name)
	if not attribute:
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkAttributeSync",
			"Received update for unknown attribute: %s" % attribute_name
		)
		return
	
	# Check if values actually changed to avoid unnecessary updates
	var needs_update = false
	if abs(attribute.value_current - current_value) > 0.01 or abs(attribute.value_max - max_value) > 0.01:
		needs_update = true
	
	if not needs_update:
		return
	
	# Update attribute values using set_attribute
	# Note: set_attribute will trigger attribute_changed signal, but that's OK for remote players
	# as they don't have _on_local_attribute_changed connected, so no network loop
	attribute.set_attribute(current_value, max_value)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkAttributeSync",
		"Received attribute update: %s = %.2f/%.2f" % [attribute_name, current_value, max_value]
	)


## RPC: Request initial attribute values from host (client only)
@rpc("any_peer", "call_local", "reliable")
func _request_initial_attributes() -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	var requester_id = multiplayer.get_remote_sender_id()
	if requester_id == 0:
		return
	
	# Send all current attribute values to the requesting client
	if not parent_body or not parent_body.has_method("get"):
		return
	
	var player_attributes = parent_body.get("player_attributes")
	if not player_attributes or not player_attributes is Dictionary:
		return
	
	# Send each attribute to the requesting client
	for attribute_name in player_attributes.keys():
		var attribute = player_attributes[attribute_name]
		if attribute:
			NetworkManager.sync_player_attribute.rpc_id(requester_id, peer_id, attribute_name, attribute.value_current, attribute.value_max)
			CogitoGlobals.debug_log(
				enable_logging,
				"NetworkAttributeSync",
				"[HOST] Sending initial attribute %s = %.2f/%.2f to client %d" % [attribute_name, attribute.value_current, attribute.value_max, requester_id]
			)

