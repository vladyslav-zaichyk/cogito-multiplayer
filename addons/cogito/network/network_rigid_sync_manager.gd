extends Node
## Network Rigid Body Sync Manager
## Autoload singleton that automatically injects NetworkRigidSync components
## into all RigidBody3D nodes in the scene

## Enable/disable logging
var enable_logging: bool = true

## Registry of all registered rigid bodies (network_id -> NetworkRigidSync)
var registered_bodies: Dictionary = {}

## Auto-enable sync for all objects in Phase 1 (for testing)
## Set to false to require manual enable_sync_for_group() call
var auto_enable_sync: bool = true

## Phase 1: Simple version - sync ALL RigidBody3D (no filters)
## Filters will be added in later phases
var sync_group_name: String = ""  # Empty = sync all (Phase 1)
var no_sync_group_name: String = ""  # Empty = no exclusions (Phase 1)

## Component name to inject
const COMPONENT_NAME = "NetworkRigidSync"
const COMPONENT_SCRIPT = preload("res://addons/cogito/network/network_rigid_sync.gd")

## Bubble component for rigid bodies (Area3D attached to each RigidBody3D)
const BUBBLE_NAME = "NetworkRigidBubble"
const BUBBLE_SCRIPT = preload("res://addons/cogito/network/network_rigid_bubble.gd")

## Helper script for _integrate_forces (optional)
const HELPER_SCRIPT = preload("res://addons/cogito/network/rigid_body_sync_helper.gd")

## NetworkRigidBodyID script (for stable network IDs)
const NETWORK_ID_SCRIPT = preload("res://addons/cogito/network/network_rigid_body_id.gd")
const NETWORK_ID_NAME = "NetworkRigidBodyID"

## Auto-add helper script to RigidBody3D that don't have scripts (for _integrate_forces)
var auto_add_helper_script: bool = true

## Bubble tracking: network_id -> Array[peer_id] (players currently inside bubble)
var _rigid_body_bubbles: Dictionary = {}


func _ready() -> void:
	# Connect to scene tree signals for dynamic node detection
	if get_tree():
		get_tree().node_added.connect(_on_node_added)
		get_tree().node_removed.connect(_on_node_removed)
	
	# Connect to NetworkEventBus for scene change detection
	if NetworkEventBus:
		NetworkEventBus.scene_changed.connect(_on_scene_changed)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSyncManager",
		"Network Rigid Sync Manager initialized"
	)
	
	# Wait a frame for scene to be fully loaded
	await get_tree().process_frame
	
	# Find and inject components into existing RigidBody3D nodes
	_find_and_inject_rigid_bodies()
	
	# Phase 1: Auto-enable sync for all objects if enabled (for testing)
	if auto_enable_sync and NetworkManager and NetworkManager.is_multiplayer():
		await get_tree().create_timer(1.5).timeout  # Wait for all components to initialize and be ready
		_enable_sync_for_all_registered()


## Called when a new node is added to the scene tree
func _on_node_added(node: Node) -> void:
	# Check if it's a RigidBody3D
	if node is RigidBody3D:
		# Wait for node to be fully initialized, then inject components
		_inject_component_if_needed_async(node)


## Async wrapper for _inject_component_if_needed
func _inject_component_if_needed_async(node: Node) -> void:
	await get_tree().process_frame
	await _inject_component_if_needed(node)


## Called when a node is removed from the scene tree
func _on_node_removed(node: Node) -> void:
	# Check if it's a RigidBody3D with our component
	if node is RigidBody3D:
		var component = node.get_node_or_null(COMPONENT_NAME)
		if component and component.has_method("get_network_id"):
			var network_id = component.get_network_id()
			unregister_rigid_body(network_id)


## Called when scene changes (from NetworkEventBus.scene_changed)
func _on_scene_changed(scene_path: String, scene_name: String) -> void:
	# Clear registry when scene changes
	registered_bodies.clear()
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSyncManager",
		"Scene changed to: %s (%s)" % [scene_name, scene_path]
	)
	
	# Wait for new scene to load
	await get_tree().process_frame
	
	# Find and inject components in new scene
	_find_and_inject_rigid_bodies()


## Find all RigidBody3D nodes in current scene and inject components
func _find_and_inject_rigid_bodies() -> void:
	var scene = get_tree().current_scene
	if not scene:
		return
	
	# Find all RigidBody3D nodes recursively
	var rigid_bodies = _find_rigid_bodies_recursive(scene)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSyncManager",
		"Found %d RigidBody3D nodes in scene" % rigid_bodies.size()
	)
	
	# Inject components (sequentially to avoid race conditions)
	for body in rigid_bodies:
		await _inject_component_if_needed(body)


## Recursively find all RigidBody3D nodes
func _find_rigid_bodies_recursive(node: Node) -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	
	if node is RigidBody3D:
		result.append(node)
	
	# Recursively check children
	for child in node.get_children():
		result.append_array(_find_rigid_bodies_recursive(child))
	
	return result


## Inject NetworkRigidSync component if needed
func _inject_component_if_needed(rigid_body: RigidBody3D) -> void:
	if not rigid_body or not is_instance_valid(rigid_body):
		return
	
	# Check if component already exists
	if rigid_body.get_node_or_null(COMPONENT_NAME):
		return
	
	# Check if object should be synced (filtering)
	if not _should_sync_object(rigid_body):
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkRigidSyncManager",
			"Skipping %s (filtered out)" % rigid_body.name
		)
		return
	
	# First, ensure NetworkRigidBodyID component exists (for stable network IDs)
	if not rigid_body.get_node_or_null(NETWORK_ID_NAME):
		var network_id_component = NETWORK_ID_SCRIPT.new()
		network_id_component.name = NETWORK_ID_NAME
		rigid_body.add_child(network_id_component)
		# Wait a frame for component to initialize
		await get_tree().process_frame
	
	# Create and add NetworkRigidSync component
	var component = COMPONENT_SCRIPT.new()
	component.name = COMPONENT_NAME
	rigid_body.add_child(component)
	
	# Create and add bubble component (Area3D) as child of rigid body
	# Використовується тільки на хості для вибору owner на основі близькості гравців
	if not rigid_body.get_node_or_null(BUBBLE_NAME):
		var bubble: Area3D = BUBBLE_SCRIPT.new()
		bubble.name = BUBBLE_NAME
		# Розмір бульбашки можна буде налаштувати пізніше (через CollisionShape3D)
		rigid_body.add_child(bubble)
	
	# Optionally add helper script if RigidBody3D doesn't have a script
	if auto_add_helper_script and not rigid_body.get_script():
		rigid_body.set_script(HELPER_SCRIPT)
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkRigidSyncManager",
			"Added helper script to %s (no existing script)" % rigid_body.name
		)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSyncManager",
		"Injected NetworkRigidSync into %s" % rigid_body.name
	)


## Check if object should be synced based on groups
## Phase 1: Simple version - sync ALL RigidBody3D (no filters)
func _should_sync_object(rigid_body: RigidBody3D) -> bool:
	# Phase 1: Sync ALL RigidBody3D (no filters)
	# Filters will be added in later phases
	return true


## Register a rigid body sync component
func register_rigid_body(component: Node) -> void:
	if not component or not component.has_method("get_network_id"):
		push_error("NetworkRigidSyncManager: Invalid component passed to register_rigid_body")
		return
	
	var network_id = component.get_network_id()
	if network_id == 0:
		push_error("NetworkRigidSyncManager: Component has invalid network_id (0)")
		return
	
	registered_bodies[network_id] = component
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSyncManager",
		"Registered rigid body: %s" % network_id
	)
	
	# Phase 1: Auto-enable sync if enabled and in multiplayer
	# Note: Don't use await here as it can block registration
	# Instead, use call_deferred to enable sync after component is ready
	if auto_enable_sync and NetworkManager and NetworkManager.is_multiplayer():
		call_deferred("_enable_sync_for_component", component, network_id)


## Unregister a rigid body sync component
func unregister_rigid_body(network_id: int) -> void:
	if registered_bodies.has(network_id):
		registered_bodies.erase(network_id)
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkRigidSyncManager",
			"Unregistered rigid body: %s" % network_id
		)


## Get registered rigid body by network ID
func get_rigid_body(network_id: int) -> Node:
	return registered_bodies.get(network_id, null)


## Get count of registered bodies
func get_registered_count() -> int:
	return registered_bodies.size()


## Enable sync for objects in a specific group
func enable_sync_for_group(group_name: String) -> void:
	sync_group_name = group_name
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSyncManager",
		"Sync enabled for group: %s" % group_name
	)
	
	# Enable sync for all registered bodies in this group
	for network_id in registered_bodies:
		var component = registered_bodies[network_id]
		if component and component.has_method("get_parent_rigid_body"):
			var rigid_body = component.get_parent_rigid_body()
			if rigid_body and rigid_body.is_in_group(group_name):
				if component.has_method("set_sync_enabled"):
					component.set_sync_enabled(true)
					CogitoGlobals.debug_log(
						enable_logging,
						"NetworkRigidSyncManager",
						"Enabled sync for %s (group: %s)" % [network_id, group_name]
					)


## Enable sync for a specific network ID (will be used in Phase 1)
func enable_sync_for_network_id(network_id: int) -> void:
	var component = get_rigid_body(network_id)
	if component and component.has_method("set_sync_enabled"):
		component.set_sync_enabled(true)
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkRigidSyncManager",
			"Sync enabled for network_id: %s" % network_id
		)


## Enable sync for all registered bodies (Phase 1 testing)
func _enable_sync_for_all_registered() -> void:
	var count = 0
	for network_id in registered_bodies:
		var component = registered_bodies[network_id]
		if component and component.has_method("set_sync_enabled"):
			component.set_sync_enabled(true)
			count += 1
	
	CogitoGlobals.debug_log(
		true,  # Always log this
		"NetworkRigidSyncManager",
		"Auto-enabled sync for %d rigid bodies (Phase 1 testing)" % count
	)


## === Bubble callbacks (host-only) ===

## Викликається компонентом NetworkRigidBubble, коли гравець входить у бульбашку рігіда
func _on_rigid_body_entered_bubble(network_id: int, player_peer_id: int) -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	if not _rigid_body_bubbles.has(network_id):
		_rigid_body_bubbles[network_id] = []
	
	var arr: Array = _rigid_body_bubbles[network_id]
	if not arr.has(player_peer_id):
		arr.append(player_peer_id)
		
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkRigidSyncManager",
			"[Bubble] network_id=%d entered by peer=%d (total=%d)" % [
				network_id,
				player_peer_id,
				arr.size()
			]
		)
		
		# Оновлення ownership відбуватиметься в _process, щоб уникати флапання


## Викликається компонентом NetworkRigidBubble, коли гравець виходить з бульбашки рігіда
func _on_rigid_body_exited_bubble(network_id: int, player_peer_id: int) -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	if not _rigid_body_bubbles.has(network_id):
		return
	
	var arr: Array = _rigid_body_bubbles[network_id]
	var idx := arr.find(player_peer_id)
	if idx != -1:
		arr.remove_at(idx)
		
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkRigidSyncManager",
			"[Bubble] network_id=%d exited by peer=%d (remaining=%d)" % [
				network_id,
				player_peer_id,
				arr.size()
			]
		)
		
		if arr.is_empty():
			_rigid_body_bubbles.erase(network_id)


## === Ownership selection based on bubbles (host-only) ===

func _process(_delta: float) -> void:
	# Поки що bubble-логіка працює тільки на хості
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	# Проходимо по всіх зареєстрованих рігідах і при необхідності оновлюємо owner_peer_id
	for network_id in registered_bodies.keys():
		var component = get_rigid_body(network_id)
		if not component or not component.has_method("get_parent_rigid_body"):
			continue
		
		var rb: RigidBody3D = component.get_parent_rigid_body()
		if not rb or not is_instance_valid(rb):
			continue
		
		var bubble_peers: Array = _rigid_body_bubbles.get(network_id, [])
		
		var desired_owner := _choose_owner_for_rigid(network_id, rb, bubble_peers)
		if desired_owner == -1:
			continue
		
		# Отримаємо поточного owner з компонента, якщо він є
		var current_owner: int = 1
		if "owner_peer_id" in component:
			current_owner = component.owner_peer_id
		
		# === ФІКС: Використовуємо RPC замість прямого виклику ===
		# Це гарантує, що всі клієнти дізнаються про зміну власника
		if desired_owner != current_owner:
			# НЕ викликаємо локальний метод напряму!
			# _handle_ownership_grant(network_id, desired_owner) <--- БУЛО (ПОМИЛКА)
			
			# Викликаємо RPC, щоб всі дізналися про нового власника
			# RPC має прапорець "call_local", тому він виконається і на хості, і на всіх клієнтах
			if NetworkManager:
				NetworkManager.grant_rigid_body_ownership.rpc(network_id, desired_owner)


## Вибір бажаного owner для конкретного рігіда
## Правила (поки прості):
## - Якщо немає гравців у бульбашці → owner = 1 (host)
## - Якщо один гравець у бульбашці → owner = цей peer
## - Якщо кілька → owner = найближчий гравець до рігіда (по global_position)
func _choose_owner_for_rigid(network_id: int, rb: RigidBody3D, bubble_peers: Array) -> int:
	if bubble_peers.is_empty():
		return 1  # Host
	
	if bubble_peers.size() == 1:
		return bubble_peers[0] as int
	
	if not PlayerManager:
		return 1
	
	var rb_pos: Vector3 = rb.global_position
	var closest_peer_id := 1
	var closest_dist := INF
	
	for peer_id in bubble_peers:
		var player_node := PlayerManager.get_player_by_peer_id(peer_id)
		if not player_node or not is_instance_valid(player_node):
			continue
		
		if not (player_node is Node3D):
			continue
		
		var dist := rb_pos.distance_to((player_node as Node3D).global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_peer_id = peer_id as int
	
	return closest_peer_id



## Enable sync for a single component (deferred call)
func _enable_sync_for_component(component: Node, network_id: int) -> void:
	# Wait a bit for component to be ready
	await get_tree().create_timer(0.6).timeout  # Slightly longer than is_ready_for_sync delay
	if component and is_instance_valid(component) and component.has_method("set_sync_enabled"):
		component.set_sync_enabled(true)
		CogitoGlobals.debug_log(
			true,
			"NetworkRigidSyncManager",
			"Auto-enabled sync for newly registered: %s" % network_id
		)


## Receive rigid body state from network (called by NetworkManager RPC)
func _receive_rigid_state(state_data: Dictionary, sender_peer_id: int) -> void:
	var network_id_raw = state_data.get("network_id", 0)
	# Ensure network_id is int (handle both int and String for compatibility)
	var network_id: int = 0
	if network_id_raw is int:
		network_id = network_id_raw
	elif network_id_raw is String:
		# Try to convert String to int (for backward compatibility)
		network_id = int(network_id_raw) if network_id_raw.is_valid_int() else 0
	
	if network_id == 0:
		return
	
	# Find the component and apply state
	var component = get_rigid_body(network_id)
	
	# Get local peer ID early (needed for ownership checks)
	var local_peer_id: int = -1
	if NetworkManager and NetworkManager.is_multiplayer():
		local_peer_id = NetworkManager.get_local_peer_id()
	
	# Diagnostic logging вимкнено для зменшення спаму
	# Розкоментуй наступні рядки для діагностики, якщо потрібно:
	# CogitoGlobals.debug_log(
	# 	enable_logging,
	# 	"NetworkRigidSyncManager",
	# 	"[Mgr] peer=%d got state id=%d from=%d has=%s owner=%d" % [
	# 		local_peer_id,
	# 		network_id,
	# 		sender_peer_id,
	# 		str(component != null),
	# 		component.owner_peer_id if component and "owner_peer_id" in component else -1
	# 	]
	# )
	
	if not component or not component.has_method("_receive_state_update"):
		CogitoGlobals.debug_log(
			true,
			"NetworkRigidSyncManager",
			"[DIAG] Host received state but no component: network_id=%d, from=%d, component=%s" % [
				network_id, sender_peer_id, str(component != null)
			]
		)
		return
	
	# Check ownership: don't apply if we are the owner (we send states)
	if NetworkManager and NetworkManager.is_multiplayer():
		# Don't apply if we sent this state (use sender_peer_id instead of timestamp hack)
		if sender_peer_id == local_peer_id:
			CogitoGlobals.debug_log(
				true,
				"NetworkRigidSyncManager",
				"[DIAG] Host ignoring own state: network_id=%d, sender=%d, local=%d" % [
					network_id, sender_peer_id, local_peer_id
				]
			)
			return
		
		# Check if component has ownership info
		if "owner_peer_id" in component:
			var component_owner = component.owner_peer_id
			var is_local_owner_check = false
			if component.has_method("is_local_owner"):
				is_local_owner_check = component.is_local_owner()
			else:
				is_local_owner_check = (component_owner == local_peer_id)
			
			if is_local_owner_check:
				CogitoGlobals.debug_log(
					true,
					"NetworkRigidSyncManager",
					"[DIAG] Host ignoring state: considers self owner! network_id=%d, from=%d, host_owner=%d, component_owner=%d" % [
						network_id, sender_peer_id, local_peer_id, component_owner
					]
				)
				return
	
	CogitoGlobals.debug_log(
		true,
		"NetworkRigidSyncManager",
		"[DIAG] Host forwarding state to component: network_id=%d, from=%d, local=%d, component_owner=%d" % [
			network_id, sender_peer_id, local_peer_id,
			component.owner_peer_id if "owner_peer_id" in component else -1
		]
	)
	component._receive_state_update(state_data)


## Handle ownership request (called from NetworkManager RPC)
func _handle_ownership_request(network_id: int, requesting_peer_id: int) -> void:
	# Only host processes ownership requests
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	var component = get_rigid_body(network_id)
	if not component or not component.has_method("_set_ownership"):
		return
	
	# Grant ownership to requesting client
	component._set_ownership(requesting_peer_id)
	
	# Notify all peers about ownership change
	if NetworkManager:
		NetworkManager.grant_rigid_body_ownership.rpc(network_id, requesting_peer_id)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSyncManager",
		"Granted ownership of %s to peer %d" % [network_id, requesting_peer_id]
	)


## Handle ownership grant (called from NetworkManager RPC)
func _handle_ownership_grant(network_id: int, owner_peer_id: int) -> void:
	var component = get_rigid_body(network_id)
	if not component or not component.has_method("_set_ownership"):
		return
	
	# DIAGNOSTIC: Check current state before granting
	var local_peer_id = NetworkManager.get_local_peer_id() if NetworkManager else -1
	var current_owner = component.owner_peer_id if "owner_peer_id" in component else -1
	var rigid_body = component.get_parent_rigid_body() if component.has_method("get_parent_rigid_body") else null
	var current_authority = rigid_body.get_multiplayer_authority() if rigid_body else -1
	
	CogitoGlobals.debug_log(
		true,
		"NetworkRigidSyncManager",
		"[DIAG] _handle_ownership_grant: network_id=%d, granting_to=%d, local=%d, current_owner=%d, current_authority=%d" % [
			network_id, owner_peer_id, local_peer_id, current_owner, current_authority
		]
	)
	
	# Update ownership locally
	component._set_ownership(owner_peer_id)
	
	# DIAGNOSTIC: Check state after granting
	var new_owner = component.owner_peer_id if "owner_peer_id" in component else -1
	var new_authority = rigid_body.get_multiplayer_authority() if rigid_body else -1
	var new_freeze = rigid_body.freeze if rigid_body else false
	
	CogitoGlobals.debug_log(
		true,
		"NetworkRigidSyncManager",
		"[DIAG] _handle_ownership_grant AFTER: network_id=%d, new_owner=%d, new_authority=%d, freeze=%s, local=%d" % [
			network_id, new_owner, new_authority, new_freeze, local_peer_id
		]
	)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSyncManager",
		"Ownership of %s granted to peer %d" % [network_id, owner_peer_id]
	)


## Handle ownership return (called from NetworkManager RPC)
func _handle_ownership_return(network_id: int) -> void:
	# Only host processes ownership returns
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	var component = get_rigid_body(network_id)
	if not component or not component.has_method("_set_ownership"):
		return
	
	# Return ownership to host
	component._set_ownership(1)
	
	# Notify all peers about ownership change
	if NetworkManager:
		NetworkManager.grant_rigid_body_ownership.rpc(network_id, 1)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSyncManager",
		"Ownership of %s returned to host" % network_id
	)


## Enable logging for debugging
func set_logging_enabled(enabled: bool) -> void:
	enable_logging = enabled
	# Also enable logging for all registered components
	for network_id in registered_bodies:
		var component = registered_bodies[network_id]
		if component and component.has("enable_logging"):
			component.enable_logging = enabled
