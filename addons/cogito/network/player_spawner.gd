extends Node
## Player Spawner for multiplayer
## Handles spawning players after scene loading
## Note: This is an autoload singleton, not a class_name

## Enable/disable logging
var enable_logging: bool = false

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
	
	# Spawn players if in multiplayer
	if NetworkManager and NetworkManager.is_multiplayer():
		_spawn_all_players()
	else:
		# Single-player: spawn local player if not already spawned
		_spawn_local_player_singleplayer()


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
	
	# Set spawn position
	player_instance.global_position = spawn_pos
	
	# Add to scene tree
	var scene_root = get_tree().current_scene
	if not scene_root:
		push_error("PlayerSpawner: No current scene found")
		return
	
	scene_root.add_child(player_instance)
	
	# Register player
	if PlayerManager:
		var player_id = PlayerManager.register_player(player_instance, true)  # true = is_local
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerSpawner",
			"Local player spawned with ID: %d at position: %s" % [player_id, spawn_pos]
		)
		
		# Notify other peers
		if NetworkManager.is_host():
			_player_spawned.rpc(local_peer_id, spawn_pos)
	
	# Set network authority (local player controls their own character)
	if multiplayer:
		multiplayer.set_authority(player_instance.get_path(), local_peer_id)


## Spawn remote players (host only)
func _spawn_remote_players() -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	var connected_peers = NetworkManager.get_connected_peers()
	
	for peer_id in connected_peers:
		# Spawn remote player for this peer
		_spawn_remote_player(peer_id)


## Spawn a remote player for a specific peer
func _spawn_remote_player(peer_id: int) -> void:
	if not NetworkManager or not NetworkManager.is_host():
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
	
	# Set spawn position
	player_instance.global_position = spawn_pos
	
	# Add to scene tree
	var scene_root = get_tree().current_scene
	if not scene_root:
		push_error("PlayerSpawner: No current scene found")
		return
	
	scene_root.add_child(player_instance)
	
	# Set network authority (remote player controls their own character)
	if multiplayer:
		multiplayer.set_authority(player_instance.get_path(), peer_id)
	
	# Register player
	if PlayerManager:
		var player_id = PlayerManager.register_player(player_instance, false)  # false = not local
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerSpawner",
			"Remote player spawned for peer %d with ID: %d at position: %s" % [peer_id, player_id, spawn_pos]
		)
	
	# Notify all clients about this spawn
	_player_spawned.rpc(peer_id, spawn_pos)


## RPC: Request spawn info from host (client only)
@rpc("any_peer", "call_local", "reliable")
func _request_spawn_info() -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	var requester_id = multiplayer.get_remote_sender_id()
	
	# Spawn remote player for requester
	_spawn_remote_player(requester_id)


## RPC: Notify all clients that a player has spawned
@rpc("authority", "call_local", "reliable")
func _player_spawned(peer_id: int, spawn_position: Vector3) -> void:
	# Only process on clients (host already spawned)
	if NetworkManager and NetworkManager.is_host():
		return
	
	# Check if we already have this player
	if PlayerManager and PlayerManager.has_player_by_peer_id(peer_id):
		return
	
	# Spawn remote player representation
	var player_scene = load(REMOTE_PLAYER_SCENE_PATH) as PackedScene
	if not player_scene:
		push_error("PlayerSpawner: Failed to load remote player scene")
		return
	
	var player_instance = player_scene.instantiate()
	if not player_instance:
		push_error("PlayerSpawner: Failed to instantiate remote player")
		return
	
	# Set spawn position
	player_instance.global_position = spawn_position
	
	# Add to scene tree
	var scene_root = get_tree().current_scene
	if not scene_root:
		push_error("PlayerSpawner: No current scene found")
		return
	
	scene_root.add_child(player_instance)
	
	# Set network authority (remote player controls their own character)
	if multiplayer:
		multiplayer.set_authority(player_instance.get_path(), peer_id)
	
	# Register player
	if PlayerManager:
		var player_id = PlayerManager.register_player(player_instance, false)  # false = not local
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerSpawner",
			"Remote player spawned for peer %d with ID: %d at position: %s" % [peer_id, player_id, spawn_position]
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
