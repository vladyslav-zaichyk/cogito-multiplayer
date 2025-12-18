extends Node
## World Loading Manager for synchronizing scene loading in multiplayer
## Ensures all clients have loaded the scene before spawning players
## Note: This is an autoload singleton, not a class_name

## Enable/disable logging
var enable_logging: bool = true  # Enable for debugging

## Signal emitted when all peers have loaded the scene
signal all_peers_loaded()

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
## allow_client: If true, allows clients to call this directly (used when called from RPC)
func start_loading_scene(scene_path: String, on_all_loaded: Callable = Callable(), allow_client: bool = false) -> void:
	# In multiplayer, only host can initiate scene loading (unless called from RPC)
	if NetworkManager and NetworkManager.is_multiplayer():
		if not NetworkManager.is_host() and not allow_client:
			CogitoGlobals.debug_log(
				true,
				"WorldLoadingManager",
				"[CLIENT] Scene load blocked: only host can initiate scene loading"
			)
			return
	
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
	
	var role = "[HOST]" if NetworkManager and NetworkManager.is_host() else "[CLIENT]"
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s Starting scene load: %s" % [role, scene_path]
	)
	
	# If we're the host, notify all clients to load the scene
	# Wait a frame to ensure clients are ready
	await get_tree().process_frame
	if NetworkManager and NetworkManager.is_host():
		var connected_peers = NetworkManager.get_connected_peers()
		CogitoGlobals.debug_log(
			true,
			"WorldLoadingManager",
			"[HOST] Notifying %d clients to load scene: %s" % [connected_peers.size(), scene_path]
		)
		_request_scene_load.rpc(scene_path)
	
	# Load the scene locally
	_load_scene_local(scene_path)


## Load scene locally and notify other peers
func _load_scene_local(scene_path: String) -> void:
	var is_client = NetworkManager and NetworkManager.is_connected_client()
	var role = "[HOST]" if NetworkManager and NetworkManager.is_host() else "[CLIENT]"
	
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s Loading scene locally: %s" % [role, scene_path]
	)
	
	# Use SceneManager if available (for compatibility with existing system)
	if SceneManager:
		# Use CogitoSceneManager for loading (maintains compatibility)
		if CogitoSceneManager:
			CogitoGlobals.debug_log(
				true,
				"WorldLoadingManager",
				"%s Using CogitoSceneManager to load scene" % role
			)
			
			# Connect to scene_changed signal to know when scene is actually loaded
			# Note: scene_changed emits (scene_path, scene_name), so we check scene_path in the callback
			if NetworkEventBus:
				var scene_changed_connection = NetworkEventBus.scene_changed.connect(_on_scene_actually_loaded, CONNECT_ONE_SHOT)
			
			CogitoSceneManager.load_next_scene(
				scene_path,
				"",
				"temp",
				CogitoSceneManager.CogitoSceneLoadMode.RESET
			)
			
			# Wait for scene to actually load (CogitoSceneManager uses async loading)
			await _wait_for_scene_to_load(scene_path)
			
			_mark_local_peer_loaded()
		else:
			# Fallback: direct loading
			var packed_scene = load(scene_path) as PackedScene
			if packed_scene:
				CogitoGlobals.debug_log(
					true,
					"WorldLoadingManager",
					"%s Using direct loading (fallback)" % role
				)
				get_tree().change_scene_to_packed(packed_scene)
				await get_tree().process_frame
				_mark_local_peer_loaded()
			else:
				CogitoGlobals.debug_log(
					true, "WorldLoadingManager", "%s Failed to load scene: %s" % [role, scene_path]
				)
				_is_loading = false
	else:
		# Fallback: direct loading
		var packed_scene = load(scene_path) as PackedScene
		if packed_scene:
			CogitoGlobals.debug_log(
				true,
				"WorldLoadingManager",
				"%s Using direct loading (no SceneManager)" % role
			)
			get_tree().change_scene_to_packed(packed_scene)
			await get_tree().process_frame
			_mark_local_peer_loaded()
		else:
			CogitoGlobals.debug_log(
				true, "WorldLoadingManager", "%s Failed to load scene: %s" % [role, scene_path]
			)
			_is_loading = false


## Wait for scene to actually load (CogitoSceneManager uses async loading)
func _wait_for_scene_to_load(scene_path: String) -> void:
	var role = "[HOST]" if NetworkManager and NetworkManager.is_host() else "[CLIENT]"
	var max_wait_frames = 600  # Maximum wait frames (10 seconds at 60 FPS)
	var wait_frame = 0
	
	while wait_frame < max_wait_frames:
		var current_scene = get_tree().current_scene
		if current_scene and current_scene.scene_file_path == scene_path:
			CogitoGlobals.debug_log(
				true,
				"WorldLoadingManager",
				"%s Scene actually loaded: %s (waited %d frames)" % [role, current_scene.get_name(), wait_frame]
			)
			return
		
		await get_tree().process_frame
		wait_frame += 1
		
		# Log progress every 60 frames
		if wait_frame % 60 == 0:
			CogitoGlobals.debug_log(
				true,
				"WorldLoadingManager",
				"%s Still waiting for scene to load... (frame %d)" % [role, wait_frame]
			)
	
	# Timeout - check if scene loaded anyway
	var current_scene = get_tree().current_scene
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s Scene load timeout after %d frames. Current scene: %s" % [role, wait_frame, current_scene.get_name() if current_scene else "null"]
	)


## Callback when scene is actually loaded (from NetworkEventBus.scene_changed)
func _on_scene_actually_loaded(signal_scene_path: String, scene_name: String) -> void:
	var role = "[HOST]" if NetworkManager and NetworkManager.is_host() else "[CLIENT]"
	
	# Only process if this is the scene we're waiting for
	if signal_scene_path != _current_scene_path:
		CogitoGlobals.debug_log(
			true,
			"WorldLoadingManager",
			"%s Scene changed signal ignored (waiting for %s, got %s)" % [role, _current_scene_path, signal_scene_path]
		)
		return
	
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s Scene changed signal received: %s (%s)" % [role, scene_name, signal_scene_path]
	)


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
	var is_client = NetworkManager.is_connected_client()
	var role = "[HOST]" if NetworkManager.is_host() else "[CLIENT]"
	
	_peers_loaded[local_peer_id] = true
	
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s Local peer %d loaded scene: %s" % [role, local_peer_id, _current_scene_path]
	)
	
	# Check current scene
	var current_scene = get_tree().current_scene
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s Current scene after load: %s" % [role, current_scene.get_name() if current_scene else "null"]
	)
	
	# Notify other peers that we've loaded (do this first, don't block)
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s Notifying other peers that we've loaded" % role
	)
	_notify_peer_loaded.rpc(local_peer_id, _current_scene_path)
	
	# Initialize pickup items on host (add NetworkPickupID to pre-placed items)
	# Do this asynchronously after notifying peers, so it doesn't block
	if current_scene:
		if NetworkManager.is_host():
			_initialize_pickup_items_async(current_scene)
		# Initialize interactables on both host and clients
		# Host needs it to send state updates, clients need it to receive them
		_initialize_interactables_async(current_scene)
	
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
	
	# Prevent multiple calls
	if not _is_loading:
		return
	
	var role = "[HOST]" if NetworkManager.is_host() else "[CLIENT]"
	
	# Get all connected peers
	var all_peers = NetworkManager.get_connected_peers()
	all_peers.append(1)  # Add server (peer ID 1)
	
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s Checking if all peers loaded. Total peers: %d" % [role, all_peers.size()]
	)
	
	# Check if all peers have loaded
	var all_loaded = true
	var loaded_peers = []
	var missing_peers = []
	
	for peer_id in all_peers:
		if _peers_loaded.has(peer_id) and _peers_loaded[peer_id]:
			loaded_peers.append(peer_id)
		else:
			all_loaded = false
			missing_peers.append(peer_id)
	
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s Loaded peers: %s, Missing: %s" % [role, loaded_peers, missing_peers]
	)
	
	if all_loaded:
		CogitoGlobals.debug_log(
			true,
			"WorldLoadingManager",
			"%s All peers have loaded scene: %s" % [role, _current_scene_path]
		)
		
		# Mark as not loading to prevent multiple calls
		_is_loading = false
		var scene_path = _current_scene_path
		# Keep _current_scene_path for late-joining clients, don't clear it
		# _current_scene_path = ""  # Don't clear, needed for late join
		
		# Notify all clients that loading is complete
		if NetworkManager.is_host():
			CogitoGlobals.debug_log(
				true,
				"WorldLoadingManager",
				"[HOST] Sending _all_peers_loaded RPC to all clients"
			)
			_all_peers_loaded.rpc()
		
		# Emit signal
		CogitoGlobals.debug_log(
			true,
			"WorldLoadingManager",
			"%s Emitting all_peers_loaded signal" % role
		)
		all_peers_loaded.emit()
		
		# Call callback
		if _on_all_loaded_callback.is_valid():
			CogitoGlobals.debug_log(
				true,
				"WorldLoadingManager",
				"%s Calling on_all_loaded callback" % role
			)
			_on_all_loaded_callback.call()
		else:
			CogitoGlobals.debug_log(
				true,
				"WorldLoadingManager",
				"%s No callback registered" % role
			)


## RPC: Server notifies all clients that all peers have loaded
@rpc("authority", "call_local", "reliable")
func _all_peers_loaded() -> void:
	var is_client = NetworkManager and NetworkManager.is_connected_client()
	var role = "[HOST]" if NetworkManager and NetworkManager.is_host() else "[CLIENT]"
	
	_is_loading = false
	# Keep _current_scene_path for late-joining clients, don't clear it
	# _current_scene_path = ""  # Don't clear, needed for late join
	
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s All peers loaded - ready to spawn players" % role
	)
	
	# Emit signal (for clients)
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s Emitting all_peers_loaded signal" % role
	)
	all_peers_loaded.emit()
	
	# Call callback
	if _on_all_loaded_callback.is_valid():
		CogitoGlobals.debug_log(
			true,
			"WorldLoadingManager",
			"%s Calling on_all_loaded callback" % role
		)
		_on_all_loaded_callback.call()
	else:
		CogitoGlobals.debug_log(
			true,
			"WorldLoadingManager",
			"%s No callback registered" % role
		)


## Check if scene loading is in progress
func is_loading() -> bool:
	return _is_loading


## Get current scene path being loaded
func get_current_scene_path() -> String:
	return _current_scene_path


## Get list of peers that have loaded
func get_loaded_peers() -> Array:
	return _peers_loaded.keys()


## Initialize pickup items on scene asynchronously (add NetworkPickupID to pre-placed items)
## Only called on host, doesn't block the loading process
func _initialize_pickup_items_async(scene_root: Node) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer() or not NetworkManager.is_host():
		return
	
	if not scene_root:
		return
	
	# Wait a frame to ensure scene is fully ready, but do it asynchronously
	await get_tree().process_frame
	
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"[HOST] Initializing pickup items on scene..."
	)
	
	var items_found = 0
	var items_initialized = 0
	
	# Recursively find all nodes with PickupComponent
	var nodes_to_check = []
	nodes_to_check.append_array(scene_root.get_children())
	
	while nodes_to_check.size() > 0:
		var node = nodes_to_check.pop_front()
		if not is_instance_valid(node):
			continue
		
		# Check if this node has PickupComponent
		var has_pickup = false
		var has_network_id = false
		
		for child in node.get_children():
			if child is PickupComponent:
				has_pickup = true
			if child.has_method("get_network_id") or child.has_method("set_network_id"):
				has_network_id = true
				break
		
		# If node has PickupComponent but no NetworkPickupID, add it
		if has_pickup and not has_network_id:
			items_found += 1
			var network_pickup_id_script = preload("res://addons/cogito/network/network_pickup_id.gd")
			var network_pickup_id = Node.new()
			network_pickup_id.set_script(network_pickup_id_script)
			network_pickup_id.name = "NetworkPickupID"
			node.add_child(network_pickup_id)
			items_initialized += 1
			
			CogitoGlobals.debug_log(
				true,
				"WorldLoadingManager",
				"[HOST] Added NetworkPickupID to pre-placed item at path: %s" % node.get_path()
			)
		
		# Add children to check
		for child in node.get_children():
			nodes_to_check.append(child)
		
		# Yield every 10 items to avoid blocking
		if items_found % 10 == 0:
			await get_tree().process_frame
	
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"[HOST] Pickup items initialization complete: found %d items, initialized %d new NetworkPickupID components" % [items_found, items_initialized]
	)


## Initialize interactables on scene asynchronously (add NetworkInteractable to doors and switches)
## Called on both host and clients - host needs it to send state, clients need it to receive state
func _initialize_interactables_async(scene_root: Node) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	if not scene_root:
		return
	
	var role = "[HOST]" if NetworkManager.is_host() else "[CLIENT]"
	
	# Wait a frame to ensure scene is fully ready
	await get_tree().process_frame
	
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s Initializing interactables on scene..." % role
	)
	
	var interactables_found = 0
	var interactables_initialized = 0
	
	# Recursively find all CogitoDoor and CogitoSwitch nodes
	var nodes_to_check = []
	nodes_to_check.append_array(scene_root.get_children())
	
	while nodes_to_check.size() > 0:
		var node = nodes_to_check.pop_front()
		if not is_instance_valid(node):
			continue
		
		# Check if this node is a CogitoDoor or CogitoSwitch
		var is_interactable = false
		var has_network_sync = false
		
		if node is CogitoDoor or node is CogitoSwitch:
			is_interactable = true
			# Check if it already has NetworkInteractable
			for child in node.get_children():
				if child.has_method("_receive_state_update"):
					has_network_sync = true
					break
		
		# If node is interactable but has no NetworkInteractable, add it
		if is_interactable and not has_network_sync:
			interactables_found += 1
			var network_interactable_script = preload("res://addons/cogito/network/network_interactable.gd")
			var network_interactable = Node.new()
			network_interactable.set_script(network_interactable_script)
			network_interactable.name = "NetworkInteractable"
			node.add_child(network_interactable)
			interactables_initialized += 1
			
			CogitoGlobals.debug_log(
				true,
				"WorldLoadingManager",
				"%s Added NetworkInteractable to %s at path: %s" % [role, node.get_class(), node.get_path()]
			)
		
		# Add children to check
		for child in node.get_children():
			nodes_to_check.append(child)
		
		# Yield every 10 items to avoid blocking
		if interactables_found % 10 == 0:
			await get_tree().process_frame
	
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s Interactables initialization complete: found %d interactables, initialized %d new NetworkInteractable components" % [role, interactables_found, interactables_initialized]
	)


## Callback when a peer connects
func _on_network_connected(peer_id: int) -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	var role = "[HOST]"
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s Peer connected: %d | is_loading=%s | current_scene_path='%s'"
		% [role, peer_id, str(_is_loading), _current_scene_path]
	)
	
	# If we don't have any active / remembered scene yet, there's nothing to do.
	# This usually means we're still in the lobby or single‑player menu.
	if _current_scene_path.is_empty():
		CogitoGlobals.debug_log(
			true,
			"WorldLoadingManager",
			"%s No active scene to sync for late join (still in lobby / menu)" % role
		)
		return
	
	# If we're in the middle of loading, or the game is already running,
	# make sure the late‑joining client loads the same scene.
	# The normal loading flow will take care of marking the peer as loaded.
	_request_scene_load.rpc_id(peer_id, _current_scene_path)
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"%s Sent _request_scene_load to late‑joining peer %d for scene: %s"
		% [role, peer_id, _current_scene_path]
	)


## RPC: Host requests all clients to load a scene
@rpc("authority", "call_local", "reliable")
func _request_scene_load(scene_path: String) -> void:
	# Only process on clients (host already loading)
	if NetworkManager and NetworkManager.is_host():
		CogitoGlobals.debug_log(
			true,
			"WorldLoadingManager",
			"_request_scene_load: Ignored on host"
		)
		return
	
	CogitoGlobals.debug_log(
		true,
		"WorldLoadingManager",
		"[CLIENT] Received scene load request from host: %s" % scene_path
	)
	
	# Start loading the scene (allow_client=true because this is called from authorized RPC)
	start_loading_scene(scene_path, Callable(), true)


## Callback when a peer disconnects
func _on_network_disconnected(peer_id: int) -> void:
	# Remove from loaded peers
	if _peers_loaded.has(peer_id):
		_peers_loaded.erase(peer_id)
	
	# Check if we can proceed (maybe we were waiting for this peer)
	if _is_loading:
		_check_all_peers_loaded()

