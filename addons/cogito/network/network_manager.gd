extends Node
## Network Manager for handling multiplayer connections.
## Provides abstraction over Godot's Multiplayer API.
## Note: This is an autoload singleton, not a class_name

## Enable/disable logging
var enable_logging: bool = false

## Current game mode: SINGLE_PLAYER or MULTIPLAYER
enum GameMode { SINGLE_PLAYER, MULTIPLAYER }
var current_game_mode: GameMode = GameMode.SINGLE_PLAYER

## Multiplayer peer (ENetMultiplayerPeer, WebSocketMultiplayerPeer, etc.)
var multiplayer_peer: MultiplayerPeer = null

## Is this instance the server/host?
var is_server: bool = false

## Is this instance a client?
var is_client: bool = false

## Local peer ID (1 for server, >1 for clients)
var local_peer_id: int = 1

## Port for multiplayer connections
var multiplayer_port: int = 7777

## Max number of players
var max_players: int = 4


func _ready() -> void:
	# Set up multiplayer connection handlers
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	CogitoGlobals.debug_log(
		true, "NetworkManager", "Network Manager initialized (Single-player mode)"
	)


## Start hosting a multiplayer game
func start_hosting(port: int = 7777, max_peers: int = 4) -> bool:
	if current_game_mode == GameMode.MULTIPLAYER:
		CogitoGlobals.debug_log(
			true, "NetworkManager", "Already in multiplayer mode!"
		)
		return false
	
	multiplayer_port = port
	max_players = max_peers
	
	# Create ENet peer for hosting
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, max_peers)
	
	if error != OK:
		CogitoGlobals.debug_log(
			true, "NetworkManager", "Failed to create server: %d" % error
		)
		if NetworkEventBus:
			NetworkEventBus.network_error.emit("Failed to create server: %d" % error)
		return false
	
	multiplayer_peer = peer
	multiplayer.multiplayer_peer = peer
	
	is_server = true
	is_client = false
	local_peer_id = 1
	current_game_mode = GameMode.MULTIPLAYER
	
	CogitoGlobals.debug_log(
		enable_logging, "NetworkManager", "Server started on port %d" % port
	)
	
	if NetworkEventBus:
		NetworkEventBus.network_connected.emit(local_peer_id)
	
	return true


## Join a multiplayer game
func join_game(address: String, port: int = 7777) -> bool:
	if current_game_mode == GameMode.MULTIPLAYER:
		CogitoGlobals.debug_log(
			true, "NetworkManager", "Already in multiplayer mode!"
		)
		return false
	
	multiplayer_port = port
	
	# Create ENet peer for client
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		CogitoGlobals.debug_log(
			true, "NetworkManager", "Failed to create client: %d" % error
		)
		if NetworkEventBus:
			NetworkEventBus.network_error.emit("Failed to create client: %d" % error)
		return false
	
	multiplayer_peer = peer
	multiplayer.multiplayer_peer = peer
	
	is_server = false
	is_client = true
	current_game_mode = GameMode.MULTIPLAYER
	
	CogitoGlobals.debug_log(
		enable_logging, "NetworkManager", "Connecting to %s:%d" % [address, port]
	)
	
	return true


## Disconnect from multiplayer game
func disconnect_from_game() -> void:
	if current_game_mode == GameMode.SINGLE_PLAYER:
		return
	
	if multiplayer_peer:
		multiplayer_peer.close()
		multiplayer_peer = null
	
	multiplayer.multiplayer_peer = null
	
	is_server = false
	is_client = false
	local_peer_id = 1
	current_game_mode = GameMode.SINGLE_PLAYER
	
	CogitoGlobals.debug_log(
		enable_logging, "NetworkManager", "Disconnected from multiplayer"
	)
	
	if NetworkEventBus:
		NetworkEventBus.network_disconnected.emit(local_peer_id)


## Check if we're in multiplayer mode
func is_multiplayer() -> bool:
	return current_game_mode == GameMode.MULTIPLAYER


## Check if we're in single-player mode
func is_single_player() -> bool:
	return current_game_mode == GameMode.SINGLE_PLAYER


## Get local peer ID
func get_local_peer_id() -> int:
	if is_multiplayer():
		return multiplayer.get_unique_id()
	return 1


## Check if this is the server
func is_host() -> bool:
	return is_server


## Check if this is a client
func is_connected_client() -> bool:
	return is_client


## Get all connected peer IDs
func get_connected_peers() -> Array:
	if not is_multiplayer():
		return []
	
	var peers = []
	for peer_id in multiplayer.get_peers():
		peers.append(peer_id)
	return peers


## Callback when a peer connects
func _on_peer_connected(peer_id: int) -> void:
	CogitoGlobals.debug_log(
		enable_logging, "NetworkManager", "Peer connected: %d" % peer_id
	)
	
	if NetworkEventBus:
		NetworkEventBus.network_connected.emit(peer_id)


## Callback when a peer disconnects
func _on_peer_disconnected(peer_id: int) -> void:
	CogitoGlobals.debug_log(
		enable_logging, "NetworkManager", "Peer disconnected: %d" % peer_id
	)
	
	# Unregister player if exists
	if PlayerManager:
		var player = PlayerManager.get_player(peer_id)
		if player:
			PlayerManager.unregister_player(peer_id)
	
	if NetworkEventBus:
		NetworkEventBus.network_disconnected.emit(peer_id)


## Callback when connected to server
func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	CogitoGlobals.debug_log(
		enable_logging, "NetworkManager", "Connected to server as peer: %d" % local_peer_id
	)
	
	if NetworkEventBus:
		NetworkEventBus.network_connected.emit(local_peer_id)


## Callback when connection fails
func _on_connection_failed() -> void:
	CogitoGlobals.debug_log(
		true, "NetworkManager", "Connection to server failed"
	)
	
	disconnect_from_game()
	
	if NetworkEventBus:
		NetworkEventBus.network_error.emit("Connection to server failed")


## Callback when server disconnects
func _on_server_disconnected() -> void:
	CogitoGlobals.debug_log(
		true, "NetworkManager", "Server disconnected"
	)
	
	disconnect_from_game()
	
	if NetworkEventBus:
		NetworkEventBus.network_error.emit("Server disconnected")


## RPC: Sync player position (called from NetworkPositionSync)
@rpc("any_peer", "call_local", "unreliable")
func sync_player_position(peer_id: int, position: Vector3) -> void:
	# Route to the correct player's NetworkPositionSync component
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var position_sync = player_node.get_node_or_null("NetworkPositionSync")
			if position_sync:
				position_sync._receive_position_update(position)


## RPC: Sync player rotation (called from NetworkRotationSync)
@rpc("any_peer", "call_local", "unreliable")
func sync_player_rotation(peer_id: int, body_rotation: float, neck_rotation: float, head_rotation: float) -> void:
	# Route to the correct player's NetworkRotationSync component
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var rotation_sync = player_node.get_node_or_null("NetworkRotationSync")
			if rotation_sync:
				rotation_sync._receive_rotation_update(body_rotation, neck_rotation, head_rotation)


## RPC: Sync player attribute (called from NetworkAttributeSync)
@rpc("any_peer", "call_local", "reliable")
func sync_player_attribute(peer_id: int, attribute_name: String, current_value: float, max_value: float) -> void:
	# Route to the correct player's NetworkAttributeSync component
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var attribute_sync = player_node.get_node_or_null("NetworkAttributeSync")
			if attribute_sync:
				attribute_sync._receive_attribute_update(attribute_name, current_value, max_value)


## RPC: Sync player state (called from NetworkPlayerStateSync)
@rpc("any_peer", "call_local", "unreliable")
func sync_player_state(peer_id: int, state: Dictionary) -> void:
	# Route to the correct player's NetworkPlayerStateSync component
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var state_sync = player_node.get_node_or_null("NetworkPlayerStateSync")
			if state_sync:
				state_sync._receive_state_update(state)


## RPC: Sync player name (called from lobby or when player joins)
@rpc("any_peer", "call_local", "reliable")
func sync_player_name(peer_id: int, player_name: String) -> void:
	# Route to PlayerManager to update the name
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var player_id = PlayerManager.get_player_id(player_node)
			if player_id != -1:
				PlayerManager.set_player_name(player_id, player_name)


## RPC: Sync player data (centralized player information)
@rpc("any_peer", "call_local", "reliable")
func sync_player_data(peer_id: int, data_dict: Dictionary) -> void:
	# Route to PlayerManager to update player data
	if PlayerManager:
		PlayerManager.update_player_data(peer_id, data_dict)


## RPC: Request pause (client requests pause from host)
@rpc("any_peer", "call_local", "reliable")
func request_pause(requester_peer_id: int) -> void:
	# Only host can authorize pause
	if not is_host():
		return
	
	# Host authorizes pause and notifies all clients
	if NetworkEventBus:
		NetworkEventBus.game_paused.emit()
	
	# Notify all clients about pause
	set_game_paused.rpc(true)
	
	CogitoGlobals.debug_log(
		true,
		"NetworkManager",
		"[HOST] Pause requested by peer %d, pausing game for all players" % requester_peer_id
	)


## RPC: Request resume (client requests resume from host)
@rpc("any_peer", "call_local", "reliable")
func request_resume(requester_peer_id: int) -> void:
	# Only host can authorize resume
	if not is_host():
		return
	
	# Host authorizes resume and notifies all clients
	if NetworkEventBus:
		NetworkEventBus.game_resumed.emit()
	
	# Notify all clients about resume
	set_game_paused.rpc(false)
	
	CogitoGlobals.debug_log(
		true,
		"NetworkManager",
		"[HOST] Resume requested by peer %d, resuming game for all players" % requester_peer_id
	)


## RPC: Set game paused state (host notifies clients)
@rpc("any_peer", "call_local", "reliable")
func set_game_paused(paused: bool) -> void:
	# Update local pause state
	if paused:
		if NetworkEventBus:
			NetworkEventBus.game_paused.emit()
	else:
		if NetworkEventBus:
			NetworkEventBus.game_resumed.emit()
	
	CogitoGlobals.debug_log(
		true,
		"NetworkManager",
		"Game pause state changed: %s" % ("paused" if paused else "resumed")
	)


## RPC: Sync player death (called from NetworkDeathSync)
@rpc("any_peer", "call_local", "reliable")
func sync_player_death(peer_id: int) -> void:
	# Route to the correct player's NetworkDeathSync component
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var death_sync = player_node.get_node_or_null("NetworkDeathSync")
			if death_sync and death_sync.has_method("_receive_death"):
				death_sync._receive_death(peer_id)


## RPC: Sync inventory item picked (called from NetworkInventorySync)
@rpc("any_peer", "call_local", "reliable")
func sync_inventory_item_picked(peer_id: int, item_data: Dictionary, slot_index: int) -> void:
	# Route to the correct player's NetworkInventorySync component
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var inventory_sync = player_node.get_node_or_null("NetworkInventorySync")
			if inventory_sync and inventory_sync.has_method("_receive_item_picked"):
				inventory_sync._receive_item_picked(peer_id, item_data, slot_index)


## RPC: Sync inventory item dropped (called from NetworkInventorySync)
@rpc("any_peer", "call_local", "reliable")
func sync_inventory_item_dropped(peer_id: int, item_data: Dictionary, position: Vector3) -> void:
	# Route to the correct player's NetworkInventorySync component
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var inventory_sync = player_node.get_node_or_null("NetworkInventorySync")
			if inventory_sync and inventory_sync.has_method("_receive_item_dropped"):
				inventory_sync._receive_item_dropped(peer_id, item_data, position)


## RPC: Sync inventory item used (called from NetworkInventorySync)
@rpc("any_peer", "call_local", "reliable")
func sync_inventory_item_used(peer_id: int, item_data: Dictionary) -> void:
	# Route to the correct player's NetworkInventorySync component
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var inventory_sync = player_node.get_node_or_null("NetworkInventorySync")
			if inventory_sync and inventory_sync.has_method("_receive_item_used"):
				inventory_sync._receive_item_used(peer_id, item_data)


## RPC: Sync pickup item removed from world (called when item is used/consumed from world)
@rpc("any_peer", "call_local", "reliable")
func sync_pickup_item_removed(peer_id: int, item_data: Dictionary) -> void:
	# Route to the correct player's NetworkInventorySync component
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var inventory_sync = player_node.get_node_or_null("NetworkInventorySync")
			if inventory_sync and inventory_sync.has_method("_receive_pickup_removed"):
				inventory_sync._receive_pickup_removed(peer_id, item_data)


## RPC: Sync rigid body state (called from NetworkRigidSync)
@rpc("any_peer", "unreliable")
func sync_rigid_body_state(state_data: Dictionary) -> void:
	# Route to NetworkRigidSyncManager
	# Note: removed call_local - use sender_peer_id to filter own packets
	if NetworkRigidSyncManager:
		var sender_peer_id = multiplayer.get_remote_sender_id()
		NetworkRigidSyncManager._receive_rigid_state(state_data, sender_peer_id)


## RPC: Request rigid body ownership (called from client when picking up object)
@rpc("any_peer", "call_local", "reliable")
func request_rigid_body_ownership(network_id: int, requesting_peer_id: int) -> void:
	# Only host processes ownership requests
	if not is_host():
		return
	
	# Route to NetworkRigidSyncManager
	if NetworkRigidSyncManager:
		NetworkRigidSyncManager._handle_ownership_request(network_id, requesting_peer_id)


## RPC: Grant rigid body ownership (called from host to grant ownership)
@rpc("any_peer", "call_local", "reliable")
func grant_rigid_body_ownership(network_id: int, owner_peer_id: int) -> void:
	# Route to NetworkRigidSyncManager
	if NetworkRigidSyncManager:
		NetworkRigidSyncManager._handle_ownership_grant(network_id, owner_peer_id)


## RPC: Return rigid body ownership (called from client when object sleeps)
@rpc("any_peer", "call_local", "reliable")
func return_rigid_body_ownership(network_id: int) -> void:
	# Only host processes ownership returns
	if not is_host():
		return
	
	# Route to NetworkRigidSyncManager
	if NetworkRigidSyncManager:
		NetworkRigidSyncManager._handle_ownership_return(network_id)


## RPC: Sync wieldable change (called from NetworkWieldableSync)
@rpc("any_peer", "call_local", "reliable")
func sync_wieldable_change(peer_id: int, wieldable_data: Dictionary) -> void:
	# Route to the correct player's NetworkWieldableSync component
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var wieldable_sync = player_node.get_node_or_null("NetworkWieldableSync")
			if wieldable_sync and wieldable_sync.has_method("_receive_wieldable_change"):
				wieldable_sync._receive_wieldable_change(peer_id, wieldable_data)


## RPC: Sync pickup network_id (called from NetworkPickupID on host)
@rpc("any_peer", "call_local", "reliable")
func sync_pickup_network_id(scene_path_str: String, network_id: int, position: Vector3, item_name: String = "") -> void:
	# Find the pickup item by scene path and set its network_id
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	
	# Try to parse scene_path_str as NodePath
	var scene_path = NodePath(scene_path_str)
	var target_node = scene_root.get_node_or_null(scene_path)
	
	if target_node:
		# Find NetworkPickupID component
		for child in target_node.get_children():
			if child.has_method("set_network_id"):
				child.set_network_id(network_id)
				CogitoGlobals.debug_log(
					false,
					"NetworkManager",
					"Set network_id %d for pickup at path %s" % [network_id, scene_path_str]
				)
				return
		
		# If not found, add NetworkPickupID component
		var network_id_component = preload("res://addons/cogito/network/network_pickup_id.gd").new()
		network_id_component.name = "NetworkPickupID"
		target_node.add_child(network_id_component)
		network_id_component.set_network_id(network_id)
		return
	
	# If path doesn't work, try to find by position and item name (for dynamically spawned items)
	_find_pickup_by_position_and_set_id(position, network_id, item_name)


## RPC: Sync rigid body network_id (called from NetworkRigidBodyID on host)
@rpc("any_peer", "call_local", "reliable")
func sync_rigid_body_network_id(scene_path_str: String, network_id: int, position: Vector3) -> void:
	# Find the rigid body by scene path and set its network_id
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	
	# Try to parse scene_path_str as NodePath
	var scene_path = NodePath(scene_path_str)
	var target_node = scene_root.get_node_or_null(scene_path)
	
	if target_node and target_node is RigidBody3D:
		# Find NetworkRigidBodyID component
		for child in target_node.get_children():
			if child.has_method("set_network_id") and child.get_script() and child.get_script().resource_path.ends_with("network_rigid_body_id.gd"):
				child.set_network_id(network_id)
				return
		
		# If not found, add NetworkRigidBodyID component
		var network_id_component = preload("res://addons/cogito/network/network_rigid_body_id.gd").new()
		network_id_component.name = "NetworkRigidBodyID"
		target_node.add_child(network_id_component)
		network_id_component.set_network_id(network_id)
		return
	
	# If path doesn't work, try to find by position (for dynamically spawned items)
	_find_rigid_body_by_position_and_set_id(position, network_id)


## Helper: Find rigid body by position and set network_id
func _find_rigid_body_by_position_and_set_id(position: Vector3, network_id: int) -> void:
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	
	var all_nodes = scene_root.get_children()
	var nodes_to_check = []
	nodes_to_check.append_array(all_nodes)
	
	var closest_match = null
	var closest_distance = 0.5  # Max distance to consider a match
	
	# Recursively find all nodes
	while nodes_to_check.size() > 0:
		var node = nodes_to_check.pop_front()
		if not is_instance_valid(node):
			continue
		
		# Check if this node is a RigidBody3D without NetworkRigidBodyID
		if node is RigidBody3D:
			var has_network_id = false
			for child in node.get_children():
				if child.has_method("get_network_id") and child.get_script() and child.get_script().resource_path.ends_with("network_rigid_body_id.gd"):
					has_network_id = true
					break
			
			if not has_network_id:
				# Check distance
				var distance = node.global_position.distance_to(position)
				if distance < closest_distance:
					closest_match = node
					closest_distance = distance
		
		# Add children to check
		for child in node.get_children():
			nodes_to_check.append(child)
	
	if closest_match:
		# Add NetworkRigidBodyID component if it doesn't exist
		var network_id_component = preload("res://addons/cogito/network/network_rigid_body_id.gd").new()
		network_id_component.name = "NetworkRigidBodyID"
		closest_match.add_child(network_id_component)
		network_id_component.set_network_id(network_id)


## Helper: Find pickup by position and set network_id
func _find_pickup_by_position_and_set_id(position: Vector3, network_id: int, item_name: String = "") -> void:
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	
	var all_nodes = scene_root.get_children()
	var nodes_to_check = []
	nodes_to_check.append_array(all_nodes)
	
	var closest_match = null
	var closest_distance = 0.5  # Max distance to consider a match
	
	# Recursively find all nodes
	while nodes_to_check.size() > 0:
		var node = nodes_to_check.pop_front()
		if not is_instance_valid(node):
			continue
		
		# Check if this node has a PickupComponent but no NetworkPickupID yet
		var has_pickup = false
		var has_network_id = false
		var matches_item_name = false
		
		for child in node.get_children():
			if child is PickupComponent:
				has_pickup = true
				# Check if item name matches (if provided)
				var pickup = child as PickupComponent
				if pickup.slot_data and pickup.slot_data.inventory_item:
					var item = pickup.slot_data.inventory_item
					var item_n = item.get("name") if item.get("name") else ""
					if item_name.is_empty() or item_n == item_name:
						matches_item_name = true
			if child.has_method("set_network_id") or child.has_method("get_network_id"):
				has_network_id = true
		
		if has_pickup and not has_network_id and matches_item_name:
			# Check distance
			if node is Node3D:
				var distance = (node as Node3D).global_position.distance_to(position)
				if distance < closest_distance:
					closest_match = node
					closest_distance = distance
		
		# Add children to check
		for child in node.get_children():
			nodes_to_check.append(child)
	
	if closest_match:
		# Add NetworkPickupID component if it doesn't exist
		var network_id_component = preload("res://addons/cogito/network/network_pickup_id.gd").new()
		network_id_component.name = "NetworkPickupID"
		closest_match.add_child(network_id_component)
		network_id_component.set_network_id(network_id)


## RPC: Sync interactable state (called from NetworkInteractable on host)
@rpc("any_peer", "call_local", "reliable")
func sync_interactable_state(interactable_data: Dictionary) -> void:
	# Route to all NetworkInteractable components in the scene
	# They will check if the network_id matches
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	
	# Find all NetworkInteractable components
	var interactables = []
	_find_network_interactables(scene_root, interactables)
	
	# Send state update to matching interactable
	for interactable in interactables:
		if interactable.has_method("_receive_state_update"):
			interactable._receive_state_update(interactable_data)


## Helper: Recursively find all NetworkInteractable components
func _find_network_interactables(node: Node, result: Array) -> void:
	for child in node.get_children():
		if child.has_method("_receive_state_update"):
			result.append(child)
		_find_network_interactables(child, result)


## RPC: Sync object spawn (called when an object is spawned dynamically)
@rpc("any_peer", "reliable")
func sync_object_spawn(spawn_data: Dictionary) -> void:
	# This RPC is only called on remote peers (not locally)
	# The local peer spawns the object directly, then calls this RPC for others
	
	var scene_path = spawn_data.get("scene_path", "")
	var position = spawn_data.get("position", Vector3.ZERO)
	var rotation = spawn_data.get("rotation", Vector3.ZERO)
	
	if scene_path.is_empty():
		push_error("NetworkManager: sync_object_spawn called with empty scene_path")
		return
	
	# Load and instantiate the scene
	var scene = load(scene_path) as PackedScene
	if not scene:
		push_error("NetworkManager: Failed to load scene: %s" % scene_path)
		return
	
	var spawned_object = scene.instantiate()
	if not spawned_object:
		push_error("NetworkManager: Failed to instantiate scene: %s" % scene_path)
		return
	
	# Set position and rotation
	if spawned_object is Node3D:
		spawned_object.position = position
		spawned_object.rotation = rotation
	
	# Add to current scene
	var current_scene = get_tree().current_scene
	if current_scene:
		current_scene.add_child(spawned_object)
		
		# If this is a pickup item (has PickupComponent child), add NetworkPickupID if it doesn't have one
		var has_pickup_component = false
		for child in spawned_object.get_children():
			if child is PickupComponent:
				has_pickup_component = true
				break
		
		if has_pickup_component:
			# Check if it already has NetworkPickupID
			var has_network_id = false
			for child in spawned_object.get_children():
				if child.has_method("get_network_id") and child.get_script() and child.get_script().resource_path.ends_with("network_pickup_id.gd"):
					has_network_id = true
					break
			
			if not has_network_id:
				var network_id_component = preload("res://addons/cogito/network/network_pickup_id.gd").new()
				network_id_component.name = "NetworkPickupID"
				spawned_object.add_child(network_id_component)
		
		print("[NetworkManager] [%s] Spawned object from network: %s at %s" % [
			"HOST" if is_host() else "CLIENT",
			scene_path,
			position
		])
	else:
		push_error("NetworkManager: No current scene to spawn object into")
		spawned_object.queue_free()


## RPC: Sync projectile spawn (called when a player shoots)
@rpc("any_peer", "reliable")
func sync_projectile_spawn(projectile_data: Dictionary) -> void:
	# This RPC is only called on remote peers (not locally)
	# The local peer spawns the projectile directly, then calls this RPC for others
	
	var scene_path = projectile_data.get("scene_path", "")
	var position = projectile_data.get("position", Vector3.ZERO)
	var rotation = projectile_data.get("rotation", Vector3.ZERO)
	var linear_velocity = projectile_data.get("linear_velocity", Vector3.ZERO)
	var damage_amount = projectile_data.get("damage_amount", 0)
	var shooter_peer_id = projectile_data.get("shooter_peer_id", 0)
	
	if scene_path.is_empty():
		push_error("NetworkManager: sync_projectile_spawn called with empty scene_path")
		return
	
	# Load and instantiate the projectile scene
	var scene = load(scene_path) as PackedScene
	if not scene:
		push_error("NetworkManager: Failed to load projectile scene: %s" % scene_path)
		return
	
	var projectile = scene.instantiate()
	if not projectile:
		push_error("NetworkManager: Failed to instantiate projectile: %s" % scene_path)
		return
	
	# Set position and rotation (works for any Node3D)
	if projectile is Node3D:
		projectile.position = position
		projectile.rotation = rotation
		
		# Set physics properties if it's a RigidBody3D
		if projectile is RigidBody3D:
			projectile.linear_velocity = linear_velocity
		
		# Set damage amount if projectile has this property
		# Try multiple methods to set damage_amount
		if "damage_amount" in projectile:
			projectile.damage_amount = damage_amount
		elif projectile.has_method("set"):
			projectile.set("damage_amount", damage_amount)
		
		# Set Direction if projectile has this property (used in CogitoProjectile)
		if linear_velocity.length() > 0:
			var direction = linear_velocity.normalized()
			if "Direction" in projectile:
				projectile.Direction = direction
			elif projectile.has_method("set"):
				projectile.set("Direction", direction)
		
		# Set shooter_peer_id for damage sync (only for remote projectiles)
		if "shooter_peer_id" in projectile:
			projectile.shooter_peer_id = shooter_peer_id
		elif projectile.has_method("set"):
			projectile.set("shooter_peer_id", shooter_peer_id)
	
	# Add to current scene
	var current_scene = get_tree().current_scene
	if current_scene:
		current_scene.add_child(projectile)
		
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkManager",
			"[%s] Spawned projectile from peer %d: %s at %s with velocity %s" % [
				"HOST" if is_host() else "CLIENT",
				shooter_peer_id,
				scene_path,
				position,
				linear_velocity
			]
		)
	else:
		push_error("NetworkManager: No current scene to spawn projectile into")
		projectile.queue_free()


## RPC: Sync hitscan shot (called when a player shoots with hitscan weapon like Laser Rifle)
@rpc("any_peer", "reliable")
func sync_hitscan_shot(hitscan_data: Dictionary) -> void:
	# This RPC is only called on remote peers (not locally)
	# The local peer processes the hitscan directly, then calls this RPC for others
	
	var shooter_peer_id = hitscan_data.get("shooter_peer_id", 0)
	var shot_origin = hitscan_data.get("shot_origin", Vector3.ZERO)
	var target_point = hitscan_data.get("target_point", Vector3.ZERO)
	var has_hit = hitscan_data.get("has_hit", false)
	var hit_position = hitscan_data.get("hit_position", Vector3.ZERO)
	var hit_normal = hitscan_data.get("hit_normal", Vector3.UP)
	var laser_ray_prefab_path = hitscan_data.get("laser_ray_prefab_path", "")
	var collision_scene_path = hitscan_data.get("collision_scene_path", "")
	var decal_texture_path = hitscan_data.get("decal_texture_path", "")
	var decal_spawn = hitscan_data.get("decal_spawn", false)
	var damage_amount = hitscan_data.get("damage_amount", 0)
	
	# Get shooter player to find their wieldable container
	var shooter_player = null
	if PlayerManager:
		shooter_player = PlayerManager.get_player_by_peer_id(shooter_peer_id)
	
	# Spawn laser ray visual effect
	if not laser_ray_prefab_path.is_empty():
		var laser_ray_scene = load(laser_ray_prefab_path) as PackedScene
		if laser_ray_scene:
			var laser_ray = laser_ray_scene.instantiate()
			if laser_ray and laser_ray.has_method("draw_ray"):
				# Use actual hit position if there's a hit, otherwise use target_point
				var ray_end = hit_position if has_hit else target_point
				laser_ray.draw_ray(shot_origin, ray_end)
				
				# Add to current scene
				var current_scene = get_tree().current_scene
				if current_scene:
					current_scene.add_child(laser_ray)
				else:
					laser_ray.queue_free()
	
	# Spawn hit decal if there's a hit
	if has_hit and decal_spawn and not hit_position.is_zero_approx():
		# Try to find the collider at hit position (for decal placement)
		# We'll use a small raycast to find the surface
		var current_scene = get_tree().current_scene
		if not current_scene:
			return
		var space_state = current_scene.get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(
			hit_position + hit_normal * 0.1,  # Start slightly above hit position
			hit_position - hit_normal * 0.2   # End slightly below
		)
		var result = space_state.intersect_ray(query)
		
		if result:
			var decal_texture = null
			if not decal_texture_path.is_empty():
				decal_texture = load(decal_texture_path) as Texture2D
			
			# Get basis from hit normal (for decal orientation)
			var up = Vector3.UP
			if hit_normal.dot(up) > 0.9:
				up = Vector3.FORWARD
			var right = hit_normal.cross(up).normalized()
			var forward = right.cross(hit_normal).normalized()
			var decal_basis = Basis(right, hit_normal, forward)
			
			BulletDecalPool.spawn_bullet_decal(
				hit_position,
				hit_normal,
				result.collider,
				decal_basis,
				decal_texture
			)
	
	# Spawn collision scene if there's a hit
	if has_hit and not collision_scene_path.is_empty():
		var collision_scene = load(collision_scene_path) as PackedScene
		if collision_scene:
			var hit_indicator = collision_scene.instantiate()
			var current_scene = get_tree().current_scene
			if current_scene:
				current_scene.add_child(hit_indicator)
				hit_indicator.global_position = hit_position
			else:
				hit_indicator.queue_free()
	
	# Apply damage to hit object on remote clients
	# The local client already applied damage, so we only do this for remote clients
	if has_hit and damage_amount > 0:
		# Find the object that was hit by doing a raycast at the hit position
		# This ensures we hit the same object that was hit on the shooter's client
		var current_scene = get_tree().current_scene
		if current_scene:
			var space_state = current_scene.get_world_3d().direct_space_state
			# Do a small raycast to find the object at hit position
			var query = PhysicsRayQueryParameters3D.create(
				hit_position + hit_normal * 0.1,  # Start slightly above hit position
				hit_position - hit_normal * 0.2   # End slightly below
			)
			var result = space_state.intersect_ray(query)
			
			if result and result.collider:
				var hit_collider = result.collider
				var bullet_direction = hitscan_data.get("bullet_direction", Vector3.ZERO)
				
				# Apply damage to the hit object
				if hit_collider.has_signal("damage_received"):
					hit_collider.damage_received.emit(damage_amount, bullet_direction, hit_position)
					CogitoGlobals.debug_log(
						enable_logging,
						"NetworkManager",
						"[%s] Applied hitscan damage to %s: %d damage" % [
							"HOST" if is_host() else "CLIENT",
							hit_collider.name,
							damage_amount
						]
					)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkManager",
		"[%s] Received hitscan shot from peer %d: origin=%s, hit=%s at %s" % [
			"HOST" if is_host() else "CLIENT",
			shooter_peer_id,
			shot_origin,
			"yes" if has_hit else "no",
			hit_position if has_hit else target_point
		]
	)


## RPC: Sync damage dealt (called when a projectile hits a target)
@rpc("any_peer", "reliable")
func sync_damage_dealt(damage_data: Dictionary) -> void:
	# This RPC is called when a local projectile hits a target
	# Remote clients receive this and apply damage to the target
	
	var shooter_peer_id = damage_data.get("shooter_peer_id", 0)
	var collider_path = damage_data.get("collider_path", "")
	var damage_amount = damage_data.get("damage_amount", 0)
	var bullet_direction = damage_data.get("bullet_direction", Vector3.ZERO)
	var bullet_position = damage_data.get("bullet_position", Vector3.ZERO)
	
	# Don't apply damage if this is from ourselves (already applied locally)
	var local_peer_id = NetworkManager.get_local_peer_id() if NetworkManager else 0
	if shooter_peer_id == local_peer_id:
		return
	
	# Find the collider by path
	if collider_path.is_empty():
		CogitoGlobals.debug_log(
			true,
			"NetworkManager",
			"sync_damage_dealt: collider_path is empty, cannot apply damage"
		)
		return
	
	var collider = get_tree().root.get_node_or_null(NodePath(collider_path))
	if not collider or not is_instance_valid(collider):
		CogitoGlobals.debug_log(
			true,
			"NetworkManager",
			"sync_damage_dealt: Could not find collider at path: %s" % collider_path
		)
		return
	
	# Apply damage to the collider
	if collider.has_signal("damage_received"):
		collider.damage_received.emit(damage_amount, bullet_direction, bullet_position)
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkManager",
			"[%s] Applied damage from peer %d to %s: %d damage" % [
				"HOST" if is_host() else "CLIENT",
				shooter_peer_id,
				collider.name,
				damage_amount
			]
		)
	else:
		CogitoGlobals.debug_log(
			true,
			"NetworkManager",
			"sync_damage_dealt: Collider %s does not have damage_received signal" % collider.name
		)


## RPC: Sync object destruction (called when an object is destroyed)
@rpc("any_peer", "reliable")
func sync_object_destroyed(destruction_data: Dictionary) -> void:
	# This RPC is called when an object is destroyed (e.g., target destroyed by damage)
	# Remote clients receive this and destroy the object locally
	
	var object_path = destruction_data.get("object_path", "")
	var destroyer_peer_id = destruction_data.get("destroyer_peer_id", 0)
	
	# Don't destroy if this is from ourselves (already destroyed locally)
	var local_peer_id = NetworkManager.get_local_peer_id() if NetworkManager else 0
	if destroyer_peer_id == local_peer_id:
		return
	
	if object_path.is_empty():
		CogitoGlobals.debug_log(
			true,
			"NetworkManager",
			"sync_object_destroyed: object_path is empty, cannot destroy object"
		)
		return
	
	# Find the object by path
	var object = get_tree().root.get_node_or_null(NodePath(object_path))
	if not object or not is_instance_valid(object):
		CogitoGlobals.debug_log(
			true,
			"NetworkManager",
			"sync_object_destroyed: Could not find object at path: %s" % object_path
		)
		return
	
	# Destroy the object
	object.queue_free()
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkManager",
		"[%s] Destroyed object %s (destroyed by peer %d)" % [
			"HOST" if is_host() else "CLIENT",
			object.name,
			destroyer_peer_id
		]
	)


## RPC: Sync flashlight state (called when a player toggles flashlight)
@rpc("any_peer", "reliable")
func sync_flashlight_state(flashlight_data: Dictionary) -> void:
	# This RPC is called when a player toggles their flashlight on/off
	var peer_id = flashlight_data.get("peer_id", 0)
	var is_on = flashlight_data.get("is_on", false)
	
	# Find the player by peer_id
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			# Find NetworkWieldableSync component
			var wieldable_sync = player_node.get_node_or_null("NetworkWieldableSync")
			if wieldable_sync:
				# Get the remote wieldable node (flashlight)
				if wieldable_sync.remote_wieldable_node:
					var flashlight = wieldable_sync.remote_wieldable_node
					if flashlight.has_method("toggle_flashlight"):
						flashlight.toggle_flashlight(is_on)
						CogitoGlobals.debug_log(
							enable_logging,
							"NetworkManager",
							"[%s] Synced flashlight state for peer %d: %s" % [
								"HOST" if is_host() else "CLIENT",
								peer_id,
								"ON" if is_on else "OFF"
							]
						)


## RPC: Validate command (client -> host)
## Client sends command to host for validation
## Note: Only host should process this, but we can't restrict RPC to host only
## So we check is_host() inside the function
@rpc("any_peer", "call_local", "reliable")
func validate_command(command_data: Dictionary) -> void:
	# Only host can receive validation requests
	if not is_host():
		return
	
	var sender_peer_id = multiplayer.get_remote_sender_id()
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkManager",
		"[HOST] Received command validation request from peer %d: %s" % [
			sender_peer_id,
			command_data.get("command_type", "unknown")
		]
	)
	
	# Route to CommandBus for validation
	# CommandBus is an autoload singleton (registered in cogito_plugin.gd)
	# Accessible directly as global variable at runtime
	CommandBus._validate_and_broadcast_from_network(command_data, sender_peer_id)


## RPC: Broadcast command to all clients (host -> all)
## Host broadcasts validated command to all clients
@rpc("any_peer", "call_local", "reliable")
func broadcast_command(command_data: Dictionary) -> void:
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkManager",
		"[%s] Received command broadcast: %s" % [
			"HOST" if is_host() else "CLIENT",
			command_data.get("command_type", "unknown")
		]
	)
	
	# Route to CommandBus for execution
	# CommandBus is an autoload singleton (registered in cogito_plugin.gd)
	# Accessible directly as global variable at runtime
	CommandBus.receive_validated_command(command_data)