extends Node
## World Loading Manager for synchronizing scene loading in multiplayer
## Ensures all clients have loaded the scene before spawning players
## Note: This is an autoload singleton, not a class_name

## Enable/disable logging
var enable_logging: bool = false

## Dictionary tracking which peers have loaded the scene: peer_id -> bool
var _peers_loaded: Dictionary = {}

## Current scene path being loaded
var _current_scene_path: String = ""

## Is the scene loading process active?
var _is_loading: bool = false

## Callback function to call when all peers have loaded
var _on_all_loaded_callback: Callable


func _ready() -> void:
	CogitoGlobals.debug_log(
		true, "WorldLoadingManager", "World Loading Manager initialized and ready."
	)
	
	# Connect to network events
	if NetworkEventBus:
		NetworkEventBus.network_connected.connect(_on_network_connected)
		NetworkEventBus.network_disconnected.connect(_on_network_disconnected)


## Start loading a scene and wait for all peers to load it
## scene_path: Path to the scene to load
## on_all_loaded: Callback to call when all peers have loaded
func start_loading_scene(scene_path: String, on_all_loaded: Callable = Callable()) -> void:
	if _is_loading:
		CogitoGlobals.debug_log(
			true, "WorldLoadingManager", "Scene loading already in progress!"
		)
		return
	
	_current_scene_path = scene_path
	_is_loading = true
	_on_all_loaded_callback = on_all_loaded
	_peers_loaded.clear()
	
	# Mark local peer as loaded (we'll load it ourselves)
	if NetworkManager and NetworkManager.is_multiplayer():
		var local_peer_id = NetworkManager.get_local_peer_id()
		_peers_loaded[local_peer_id] = false  # Will be set to true after actual load
	
	CogitoGlobals.debug_log(
		enable_logging,
		"WorldLoadingManager",
		"Starting scene load: %s" % scene_path
	)
	
	# Load the scene locally
	_load_scene_local(scene_path)


## Load scene locally and notify other peers
func _load_scene_local(scene_path: String) -> void:
	# Use SceneManager if available (for compatibility with existing system)
	if SceneManager:
		# Use CogitoSceneManager for loading (maintains compatibility)
		if CogitoSceneManager:
			CogitoSceneManager.load_next_scene(
				scene_path,
				"",
				"temp",
				CogitoSceneManager.CogitoSceneLoadMode.RESET
			)
			# Wait for scene to be loaded
			await get_tree().process_frame
			# Wait a bit more for scene to be fully ready
			await get_tree().create_timer(0.1).timeout
			_mark_local_peer_loaded()
		else:
			# Fallback: direct loading
			var packed_scene = load(scene_path) as PackedScene
			if packed_scene:
				get_tree().change_scene_to_packed(packed_scene)
				await get_tree().process_frame
				_mark_local_peer_loaded()
			else:
				CogitoGlobals.debug_log(
					true, "WorldLoadingManager", "Failed to load scene: %s" % scene_path
				)
				_is_loading = false
	else:
		# Fallback: direct loading
		var packed_scene = load(scene_path) as PackedScene
		if packed_scene:
			get_tree().change_scene_to_packed(packed_scene)
			await get_tree().process_frame
			_mark_local_peer_loaded()
		else:
			CogitoGlobals.debug_log(
				true, "WorldLoadingManager", "Failed to load scene: %s" % scene_path
			)
			_is_loading = false


## Public method to notify that scene has been loaded
## Called by loading screen or scene manager after scene is ready
func notify_scene_loaded() -> void:
	_mark_local_peer_loaded()


## Mark local peer as loaded and notify other peers
func _mark_local_peer_loaded() -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		# Single-player: just call callback
		_is_loading = false
		if _on_all_loaded_callback.is_valid():
			_on_all_loaded_callback.call()
		return
	
	var local_peer_id = NetworkManager.get_local_peer_id()
	_peers_loaded[local_peer_id] = true
	
	CogitoGlobals.debug_log(
		enable_logging,
		"WorldLoadingManager",
		"Local peer %d loaded scene: %s" % [local_peer_id, _current_scene_path]
	)
	
	# Notify other peers that we've loaded
	_notify_peer_loaded.rpc(local_peer_id, _current_scene_path)
	
	# Check if all peers have loaded
	_check_all_peers_loaded()


## RPC: Notify that a peer has loaded the scene
@rpc("any_peer", "call_local", "reliable")
func _notify_peer_loaded(peer_id: int, scene_path: String) -> void:
	# Only process if it's for the current scene
	if scene_path != _current_scene_path:
		return
	
	# Only process if we're the server (or in single-player)
	if NetworkManager and NetworkManager.is_multiplayer():
		if not NetworkManager.is_host():
			# Clients forward to server
			_notify_peer_loaded.rpc_id(1, peer_id, scene_path)
			return
	
	_peers_loaded[peer_id] = true
	
	CogitoGlobals.debug_log(
		enable_logging,
		"WorldLoadingManager",
		"Peer %d loaded scene: %s" % [peer_id, scene_path]
	)
	
	# Check if all peers have loaded
	_check_all_peers_loaded()


## Check if all connected peers have loaded the scene
func _check_all_peers_loaded() -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		# Single-player: always ready
		_is_loading = false
		if _on_all_loaded_callback.is_valid():
			_on_all_loaded_callback.call()
		return
	
	# Get all connected peers
	var all_peers = NetworkManager.get_connected_peers()
	all_peers.append(1)  # Add server (peer ID 1)
	
	# Check if all peers have loaded
	var all_loaded = true
	for peer_id in all_peers:
		if not _peers_loaded.has(peer_id) or not _peers_loaded[peer_id]:
			all_loaded = false
			break
	
	if all_loaded:
		CogitoGlobals.debug_log(
			enable_logging,
			"WorldLoadingManager",
			"All peers have loaded scene: %s" % _current_scene_path
		)
		
		# Notify all clients that loading is complete
		if NetworkManager.is_host():
			_all_peers_loaded.rpc()
		
		_is_loading = false
		_current_scene_path = ""
		
		# Call callback
		if _on_all_loaded_callback.is_valid():
			_on_all_loaded_callback.call()


## RPC: Server notifies all clients that all peers have loaded
@rpc("authority", "call_local", "reliable")
func _all_peers_loaded() -> void:
	_is_loading = false
	_current_scene_path = ""
	
	CogitoGlobals.debug_log(
		enable_logging,
		"WorldLoadingManager",
		"All peers loaded - ready to spawn players"
	)
	
	# Call callback
	if _on_all_loaded_callback.is_valid():
		_on_all_loaded_callback.call()


## Check if scene loading is in progress
func is_loading() -> bool:
	return _is_loading


## Get current scene path being loaded
func get_current_scene_path() -> String:
	return _current_scene_path


## Get list of peers that have loaded
func get_loaded_peers() -> Array:
	return _peers_loaded.keys()


## Callback when a peer connects
func _on_network_connected(peer_id: int) -> void:
	# If we're loading, the new peer needs to load too
	if _is_loading and NetworkManager and NetworkManager.is_host():
		# Server should notify new peer about current scene
		_notify_peer_loaded.rpc_id(peer_id, NetworkManager.get_local_peer_id(), _current_scene_path)


## Callback when a peer disconnects
func _on_network_disconnected(peer_id: int) -> void:
	# Remove from loaded peers
	if _peers_loaded.has(peer_id):
		_peers_loaded.erase(peer_id)
	
	# Check if we can proceed (maybe we were waiting for this peer)
	if _is_loading:
		_check_all_peers_loaded()

