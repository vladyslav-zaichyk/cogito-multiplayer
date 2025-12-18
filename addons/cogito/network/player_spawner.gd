extends Node
## Player Spawner for multiplayer
## Handles spawning players after scene loading
## Note: This is an autoload singleton, not a class_name

## Enable/disable logging
var enable_logging: bool = true  # Enable for debugging

## Path to the player scene
const PLAYER_SCENE_PATH = "res://addons/cogito/packed_scenes/cogito_player.tscn"

## Path to the remote player scene (simplified version for other clients)
## For now, we'll use the same scene but with different authority
const REMOTE_PLAYER_SCENE_PATH = "res://addons/cogito/packed_scenes/cogito_player.tscn"

## Default spawn position (will be overridden by spawn points)
var default_spawn_position: Vector3 = Vector3(0, 2, 0)

## Dictionary of spawn points: peer_id -> spawn_position
var _spawn_points: Dictionary = {}

## Has spawning been initialized?
var _spawning_initialized: bool = false


func _ready() -> void:
	CogitoGlobals.debug_log(
		true, "PlayerSpawner", "Player Spawner initialized and ready."
	)
	
	# Connect to network events
	if NetworkEventBus:
		NetworkEventBus.scene_changed.connect(_on_scene_changed)
		NetworkEventBus.network_connected.connect(_on_network_connected)
		NetworkEventBus.network_disconnected.connect(_on_network_disconnected)
	
	# Connect to WorldLoadingManager
	if WorldLoadingManager:
		pass
		# We'll spawn players after all peers have loaded
		# This will be handled in _on_scene_changed


## Called when scene changes
func _on_scene_changed(scene_path: String, scene_name: String) -> void:
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerSpawner",
		"Scene changed to: %s (%s)" % [scene_name, scene_path]
	)
	
	# Reset spawning state
	_spawning_initialized = false
	_spawn_points.clear()
	
	# Wait a bit for scene to be fully ready
	await get_tree().create_timer(0.5).timeout
	
	# Create spawn points if in multiplayer
	if NetworkManager and NetworkManager.is_multiplayer():
		var scene_root = get_tree().current_scene
		if scene_root:
			_create_spawn_points_for_scene(scene_root)
	
	# Spawn players if in multiplayer
	if NetworkManager and NetworkManager.is_multiplayer():
		_spawn_all_players()
	else:
		# Single-player: spawn local player if not already spawned
		_spawn_local_player_singleplayer()


## Create spawn points for the current scene
func _create_spawn_points_for_scene(scene_root: Node) -> void:
	# Check if spawn points already exist
	var existing_spawn_points = scene_root.get_tree().get_nodes_in_group("SpawnPoint")
	if existing_spawn_points.size() > 0:
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerSpawner",
			"Scene already has %d spawn points" % existing_spawn_points.size()
		)
		return
	
	# Create spawn points utility
	var spawn_points_util = preload("res://addons/cogito/network/multiplayer_spawn_points.gd").new()
	var created_spawn_points = spawn_points_util.create_spawn_points_from_connectors(scene_root)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerSpawner",
		"Created %d spawn points for scene" % created_spawn_points.size()
	)


## Spawn all players (multiplayer)
func _spawn_all_players() -> void:
	if _spawning_initialized:
		return
	
	_spawning_initialized = true
	
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerSpawner",
		"Spawning all players..."
	)
	
	# Spawn local player first
	_spawn_local_player()
	
	# Spawn remote players (will be handled by RPC)
	if NetworkManager.is_host():
		# Host spawns all players
		_spawn_remote_players()
	else:
		# Client requests spawn info from host
		_request_spawn_info.rpc_id(1)


## Spawn local player
func _spawn_local_player() -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	var local_peer_id = NetworkManager.get_local_peer_id()
	
	# Check if player already exists
	if PlayerManager and PlayerManager.has_local_player():
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerSpawner",
			"Local player already exists, skipping spawn"
		)
		return
	
	# Get spawn position
	var spawn_pos = _get_spawn_position(local_peer_id)
	
	# Load and instantiate player scene
	var player_scene = load(PLAYER_SCENE_PATH) as PackedScene
	if not player_scene:
		push_error("PlayerSpawner: Failed to load player scene: %s" % PLAYER_SCENE_PATH)
		return
	
	var player_instance = player_scene.instantiate()
	if not player_instance:
		push_error("PlayerSpawner: Failed to instantiate player")
		return
	
	# Add to scene tree first
	var scene_root = get_tree().current_scene
	if not scene_root:
		push_error("PlayerSpawner: No current scene found")
		return
	
	scene_root.add_child(player_instance)
	
	# Set spawn position after adding to tree
	player_instance.global_position = spawn_pos
	
	# Register player
	if PlayerManager:
		var player_id = PlayerManager.register_player(player_instance, true)  # true = is_local
		# Set peer_id for this player
		PlayerManager.set_player_peer_id(player_id, local_peer_id)
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerSpawner",
			"Local player spawned with ID: %d (peer_id: %d) at position: %s" % [player_id, local_peer_id, spawn_pos]
		)
		
		# Notify other peers about local player spawn (both host and clients)
		# Host needs to notify clients about himself, clients need to notify host about themselves
		if NetworkManager.is_multiplayer():
			# Wait a bit to ensure name is set from lobby
			await get_tree().process_frame
			await get_tree().process_frame
			
			var player_name = PlayerManager.get_player_name(player_id) if PlayerManager else "Player"
			# If name is still "You", replace with something better
			if player_name == "You":
				if NetworkManager.is_host():
					player_name = "Host"
				else:
					player_name = "Player"
			_player_spawned.rpc(local_peer_id, spawn_pos, player_name)
	
	# In Godot 4, authority is managed through RPC attributes
	# Local player will control their own character through RPCs
	# We don't need to explicitly set authority here


## Spawn remote players (host only)
func _spawn_remote_players() -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	var connected_peers = NetworkManager.get_connected_peers()
	
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerSpawner",
		"[HOST] Spawning remote players for %d connected peers" % connected_peers.size()
	)
	
	for peer_id in connected_peers:
		# Spawn remote player for this peer
		_spawn_remote_player(peer_id)
	
	# After spawning all remote players, notify clients about host (peer_id = 1)
	# This ensures clients can see the host
	if PlayerManager and PlayerManager.has_local_player():
		var local_player = PlayerManager.get_local_player()
		if local_player:
			var host_spawn_pos = local_player.global_position
			var host_player_id = PlayerManager.get_local_player_id()
			# Wait a bit to ensure name is set from lobby
			await get_tree().process_frame
			var host_name = PlayerManager.get_player_name(host_player_id) if host_player_id != -1 else "Host"
			# If name is still "You", use "Host" instead
			if host_name == "You":
				host_name = "Host"
			CogitoGlobals.debug_log(
				enable_logging,
				"PlayerSpawner",
				"[HOST] Notifying clients about host spawn at position: %s (name: %s)" % [host_spawn_pos, host_name]
			)
			_player_spawned.rpc(1, host_spawn_pos, host_name)


## Spawn a remote player for a specific peer
func _spawn_remote_player(peer_id: int) -> void:
	# This function is only for host to spawn representations of remote players
	# Clients spawn remote players via _player_spawned RPC
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	# Check if player already exists
	if PlayerManager and PlayerManager.has_player_by_peer_id(peer_id):
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerSpawner",
			"Remote player for peer %d already exists, skipping spawn" % peer_id
		)
		return
	
	# Get spawn position
	var spawn_pos = _get_spawn_position(peer_id)
	
	# Load and instantiate player scene
	var player_scene = load(REMOTE_PLAYER_SCENE_PATH) as PackedScene
	if not player_scene:
		push_error("PlayerSpawner: Failed to load remote player scene: %s" % REMOTE_PLAYER_SCENE_PATH)
		return
	
	var player_instance = player_scene.instantiate()
	if not player_instance:
		push_error("PlayerSpawner: Failed to instantiate remote player")
		return
	
	# Add to scene tree first
	var scene_root = get_tree().current_scene
	if not scene_root:
		push_error("PlayerSpawner: No current scene found")
		return
	
	scene_root.add_child(player_instance)
	
	# Set spawn position after adding to tree
	player_instance.global_position = spawn_pos
	
	# In Godot 4, authority is managed through RPC attributes, not set_authority()
	# The remote player will control their own character through RPCs
	# We don't need to explicitly set authority here
	
	# Register player
	if PlayerManager:
		var player_id = PlayerManager.register_player(player_instance, false)  # false = not local
		# Set peer_id for this player
		PlayerManager.set_player_peer_id(player_id, peer_id)
		
		# Get player name - for remote players, we'll get it from the RPC when they spawn
		# For now, use default name
		var player_name = "Player %d" % peer_id
		
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerSpawner",
			"Remote player spawned for peer %d with ID: %d at position: %s" % [peer_id, player_id, spawn_pos]
		)
		
		# Notify all clients about this spawn (host spawns representation of remote player)
		# The actual name will be sent when the remote player spawns themselves
		_player_spawned.rpc(peer_id, spawn_pos, player_name)


## RPC: Request spawn info from host (client only)
@rpc("any_peer", "call_local", "reliable")
func _request_spawn_info() -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	var requester_id = multiplayer.get_remote_sender_id()
	
	# Spawn remote player for requester
	_spawn_remote_player(requester_id)


## RPC: Notify all clients that a player has spawned
@rpc("any_peer", "call_local", "reliable")
func _player_spawned(peer_id: int, spawn_position: Vector3, player_name: String = "") -> void:
	# Get sender peer ID to determine who sent this
	var sender_id = 0
	if multiplayer.has_multiplayer_peer():
		sender_id = multiplayer.get_remote_sender_id()
		# If sender_id is 0, it means this is a local call (call_local)
		if sender_id == 0:
			sender_id = NetworkManager.get_local_peer_id() if NetworkManager else 0
	
	var role = "[HOST]" if NetworkManager and NetworkManager.is_host() else "[CLIENT]"
	
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerSpawner",
		"%s Received _player_spawned RPC: peer_id=%d, sender_id=%d, spawn_pos=%s, player_name=%s" % [role, peer_id, sender_id, spawn_position, player_name]
	)
	
	# If we're the host and this is about a remote player, we already spawned them
	# But if this is about the sender's own player, we need to spawn them
	if NetworkManager and NetworkManager.is_host():
		# Host already spawned remote players via _spawn_remote_players()
		# But if a client is notifying about themselves, we need to spawn them
		if sender_id == peer_id and sender_id != 1:
			# Client is notifying about themselves, spawn them
			if not PlayerManager or not PlayerManager.has_player_by_peer_id(peer_id):
				CogitoGlobals.debug_log(
					enable_logging,
					"PlayerSpawner",
					"[HOST] Client %d notified about their spawn, creating representation" % peer_id
				)
				# Spawn representation of this client on host
				# Note: player_name is passed in RPC, but _spawn_remote_player doesn't use it
				# We'll set the name after spawning
				_spawn_remote_player(peer_id)
				# Set player name after spawning
				if not player_name.is_empty() and PlayerManager:
					var spawned_player_id = PlayerManager.get_player_id(PlayerManager.get_player_by_peer_id(peer_id))
					if spawned_player_id != -1:
						await get_tree().process_frame
						PlayerManager.set_player_name(spawned_player_id, player_name)
		# If this is about the host (peer_id == 1), we already spawned ourselves locally
		# Don't spawn again, but also don't return - let clients process it
		# Actually, we should return here because host doesn't need to process RPC about itself
		if peer_id == 1:
			CogitoGlobals.debug_log(
				enable_logging,
				"PlayerSpawner",
				"[HOST] Ignoring RPC about ourselves (peer_id=1), already spawned locally"
			)
			return
	
	# Check if scene is loaded - if not, wait for it
	var scene_root = get_tree().current_scene
	if not scene_root:
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerSpawner",
			"Scene not loaded yet, waiting for scene to load before spawning player %d" % peer_id
		)
		# Wait for scene to be loaded
		await _wait_for_scene_loaded()
		scene_root = get_tree().current_scene
		if not scene_root:
			push_error("PlayerSpawner: Scene still not loaded after waiting")
			return
	
	# Check if we already have this player
	if PlayerManager and PlayerManager.has_player_by_peer_id(peer_id):
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerSpawner",
			"%s Player for peer %d already exists, skipping spawn" % [role, peer_id]
		)
		return
	
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerSpawner",
		"%s Player for peer %d does not exist, proceeding with spawn" % [role, peer_id]
	)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerSpawner",
		"[CLIENT] Spawning remote player for peer %d at position: %s" % [peer_id, spawn_position]
	)
	
	# Spawn remote player representation
	var player_scene = load(REMOTE_PLAYER_SCENE_PATH) as PackedScene
	if not player_scene:
		push_error("PlayerSpawner: [CLIENT] Failed to load remote player scene")
		return
	
	var player_instance = player_scene.instantiate()
	if not player_instance:
		push_error("PlayerSpawner: [CLIENT] Failed to instantiate remote player")
		return
	
	# Add to scene tree first
	scene_root.add_child(player_instance)
	
	# Set spawn position after adding to tree
	player_instance.global_position = spawn_position
	
	# In Godot 4, authority is managed through RPC attributes
	# The remote player will control their own character through RPCs
	# We don't need to explicitly set authority here
	
	# Register player
	if PlayerManager:
		var player_id = PlayerManager.register_player(player_instance, false)  # false = not local
		# Set peer_id for this player
		PlayerManager.set_player_peer_id(player_id, peer_id)
		# Set player name if provided (do this AFTER registration so PlayerVisualRepresentation can find it)
		if not player_name.is_empty():
			# Wait a frame to ensure PlayerVisualRepresentation is created
			await get_tree().process_frame
			PlayerManager.set_player_name(player_id, player_name)
		
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerSpawner",
			"[CLIENT] Remote player spawned for peer %d with ID: %d at position: %s (name: %s)" % [peer_id, player_id, spawn_position, player_name]
		)
	else:
		push_error("PlayerSpawner: [CLIENT] PlayerManager not found, cannot register player")


## Wait for scene to be loaded
func _wait_for_scene_loaded() -> void:
	# Wait until we have a current scene
	while not get_tree().current_scene:
		await get_tree().process_frame


## Respawn a player at a spawn point
func respawn_player(peer_id: int) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# Get player node
	if not PlayerManager:
		return
	
	var player_node = PlayerManager.get_player_by_peer_id(peer_id)
	if not player_node:
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerSpawner",
			"Respawn: Player not found for peer_id %d" % peer_id
		)
		return
	
	# Get spawn position
	var spawn_pos = _get_spawn_position(peer_id)
	
	# Respawn player
	if player_node is CogitoPlayer:
		# Reset player state
		player_node.is_dead = false
		player_node.global_position = spawn_pos
		
		# Restore health to max (using setter which will emit signal)
		if player_node.has_method("get") and player_node.get("player_attributes"):
			var player_attributes = player_node.player_attributes
			if player_attributes is Dictionary:
				var health_attribute = player_attributes.get("health")
				if health_attribute:
					# Set health to max - setter will automatically emit signal
					health_attribute.value_current = health_attribute.value_max
		
		# Resume movement
		if player_node.has_method("_on_resume_movement"):
			player_node._on_resume_movement()
		
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerSpawner",
			"Respawned player for peer_id %d at position: %s" % [peer_id, spawn_pos]
		)
		
		# Sync respawn to all clients
		if NetworkManager.is_multiplayer():
			_respawn_player.rpc(peer_id, spawn_pos)


## RPC: Sync player respawn
@rpc("any_peer", "call_local", "reliable")
func _respawn_player(peer_id: int, spawn_position: Vector3) -> void:
	if not PlayerManager:
		return
	
	var player_node = PlayerManager.get_player_by_peer_id(peer_id)
	if not player_node:
		return
	
	if player_node is CogitoPlayer:
		# Reset player state
		player_node.is_dead = false
		player_node.global_position = spawn_position
		
		# Restore health to max (using setter which will emit signal)
		if player_node.has_method("get") and player_node.get("player_attributes"):
			var player_attributes = player_node.player_attributes
			if player_attributes is Dictionary:
				var health_attribute = player_attributes.get("health")
				if health_attribute:
					# Set health to max - setter will automatically emit signal
					health_attribute.value_current = health_attribute.value_max
		
		# Resume movement
		if player_node.has_method("_on_resume_movement"):
			player_node._on_resume_movement()
		
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerSpawner",
			"Received respawn sync for peer_id %d at position: %s" % [peer_id, spawn_position]
		)


## Get spawn position for a peer
func _get_spawn_position(peer_id: int) -> Vector3:
	# Check if we have a cached spawn point
	if _spawn_points.has(peer_id):
		return _spawn_points[peer_id]
	
	# Try to find spawn points in the scene
	var scene_root = get_tree().current_scene
	if scene_root:
		# Look for spawn points (nodes with "SpawnPoint" in name or group)
		var spawn_points = scene_root.get_tree().get_nodes_in_group("SpawnPoint")
		if spawn_points.size() > 0:
			# Use spawn point based on peer_id (round-robin)
			var index = (peer_id - 1) % spawn_points.size()
			var spawn_point = spawn_points[index]
			if spawn_point is Node3D:
				var pos = spawn_point.global_position
				_spawn_points[peer_id] = pos
				return pos
		
		# Look for player connector in CogitoScene
		if scene_root.has_method("get") and scene_root.get("connectors"):
			var connectors = scene_root.connectors
			if connectors.size() > 0:
				var index = (peer_id - 1) % connectors.size()
				var connector = connectors[index]
				if connector is Node3D:
					var pos = connector.global_position
					_spawn_points[peer_id] = pos
					return pos
	
	# Default spawn position (offset by peer_id to avoid overlap)
	var offset = Vector3((peer_id - 1) * 2.0, 0, 0)
	return default_spawn_position + offset


## Spawn local player in single-player mode
func _spawn_local_player_singleplayer() -> void:
	# Check if player already exists
	if PlayerManager and PlayerManager.has_local_player():
		return
	
	# In single-player, player is usually already in the scene
	# Just register it if found
	var scene_root = get_tree().current_scene
	if scene_root:
		# Look for existing player in scene
		var existing_player = scene_root.find_child("CogitoPlayer", true, false)
		if not existing_player:
			existing_player = scene_root.find_child("*", true, false)
			for child in scene_root.get_children():
				if child is CogitoPlayer:
					existing_player = child
					break
		
		if existing_player and existing_player is CogitoPlayer:
			# Register existing player
			if PlayerManager:
				PlayerManager.register_player(existing_player, true)
				CogitoGlobals.debug_log(
					enable_logging,
					"PlayerSpawner",
					"Registered existing player in single-player mode"
				)


## Callback when a peer connects
func _on_network_connected(peer_id: int) -> void:
	# If we're the host and scene is already loaded, spawn the new player
	if NetworkManager and NetworkManager.is_host() and _spawning_initialized:
		await get_tree().create_timer(0.5).timeout
		_spawn_remote_player(peer_id)


## Callback when a peer disconnects
func _on_network_disconnected(peer_id: int) -> void:
	# Remove player from PlayerManager
	if PlayerManager:
		var player = PlayerManager.get_player_by_peer_id(peer_id)
		if player:
			var player_id = PlayerManager.get_player_id(player)
			PlayerManager.unregister_player(player_id)
			
			# Remove player node
			if is_instance_valid(player):
				player.queue_free()
			
			CogitoGlobals.debug_log(
				enable_logging,
				"PlayerSpawner",
				"Removed player for disconnected peer %d" % peer_id
			)
