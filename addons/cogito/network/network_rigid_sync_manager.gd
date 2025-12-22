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
		# Use call_deferred to wait for node to be fully initialized
		call_deferred("_inject_component_if_needed", node)


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
	
	# Inject components
	for body in rigid_bodies:
		_inject_component_if_needed(body)


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
	
	# Create and add component
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
	if network_id.is_empty():
		push_error("NetworkRigidSyncManager: Component has empty network_id")
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
func unregister_rigid_body(network_id: String) -> void:
	if registered_bodies.has(network_id):
		registered_bodies.erase(network_id)
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkRigidSyncManager",
			"Unregistered rigid body: %s" % network_id
		)


## Get registered rigid body by network ID
func get_rigid_body(network_id: String) -> Node:
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
func enable_sync_for_network_id(network_id: String) -> void:
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
func _enable_sync_for_component(component: Node, network_id: String) -> void:
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
func _receive_rigid_state(state_data: Dictionary) -> void:
	var network_id = state_data.get("network_id", "")
	if network_id.is_empty():
		return
	
	# Find the component and apply state
	var component = get_rigid_body(network_id)
	if not component or not component.has_method("_receive_state_update"):
		return
	
	# Phase 1: Don't apply if we're the host (host is authority, only sends)
	# Check if we're the host (peer 1)
	if NetworkManager and NetworkManager.is_multiplayer():
		var local_peer_id = NetworkManager.get_local_peer_id()
		if local_peer_id == 1:  # Host doesn't apply states
			return
	
	# Check if this component sent the state (by comparing with last_sent_state)
	# This prevents applying our own state when call_local is used
	if "last_sent_state" in component:
		var sent_state = component.last_sent_state
		if not sent_state.is_empty():
			var received_timestamp = state_data.get("timestamp", 0.0)
			var sent_timestamp = sent_state.get("timestamp", 0.0)
			
			# If timestamps match closely (within 0.05s), this is likely our own state
			# Use larger threshold because of network delay
			if abs(received_timestamp - sent_timestamp) < 0.05:
				# This is our own state, don't apply it
				return
	
	component._receive_state_update(state_data)


## Enable logging for debugging
func set_logging_enabled(enabled: bool) -> void:
	enable_logging = enabled
	# Also enable logging for all registered components
	for network_id in registered_bodies:
		var component = registered_bodies[network_id]
		if component and component.has("enable_logging"):
			component.enable_logging = enabled
