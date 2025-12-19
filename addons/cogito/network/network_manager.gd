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
		
		# If this is a pickup item, add NetworkPickupID if it doesn't have one
		if spawned_object.has_method("get") and "PickupComponent" in spawned_object.get_groups():
			# Check if it already has NetworkPickupID
			var has_network_id = false
			for child in spawned_object.get_children():
				if child.has_method("get_network_id"):
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

