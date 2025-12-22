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

## Helper script for _integrate_forces (optional)
const HELPER_SCRIPT = preload("res://addons/cogito/network/rigid_body_sync_helper.gd")

## NetworkRigidBodyID script (for stable network IDs)
const NETWORK_ID_SCRIPT = preload("res://addons/cogito/network/network_rigid_body_id.gd")
const NETWORK_ID_NAME = "NetworkRigidBodyID"

## Auto-add helper script to RigidBody3D that don't have scripts (for _integrate_forces)
var auto_add_helper_script: bool = true


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
	
	# Diagnostic logging
	var local_peer_id = NetworkManager.get_local_peer_id() if NetworkManager else -1
	var component_owner = -1
	if component and "owner_peer_id" in component:
		component_owner = component.owner_peer_id
	
	print("[Mgr] peer=%d got state id=%d from=%d has=%s owner=%d" % [
		local_peer_id,
		network_id,
		sender_peer_id,
		str(component != null),
		component_owner
	])
	
	if not component or not component.has_method("_receive_state_update"):
		return
	
	# Check ownership: don't apply if we are the owner (we send states)
	if NetworkManager and NetworkManager.is_multiplayer():
		# Don't apply if we sent this state (use sender_peer_id instead of timestamp hack)
		if sender_peer_id == local_peer_id:
			return
		
		# Check if component has ownership info
		if "owner_peer_id" in component and component.has_method("is_local_owner"):
			if component.is_local_owner():
				return
		elif "owner_peer_id" in component:
			var owner_peer_id = component.owner_peer_id
			if owner_peer_id == local_peer_id:
				return
	
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
	
	# Update ownership locally
	component._set_ownership(owner_peer_id)
	
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
