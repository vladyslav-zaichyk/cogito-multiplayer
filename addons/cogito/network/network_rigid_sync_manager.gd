extends Node
## Network Rigid Body Sync Manager
## Autoload singleton that automatically injects NetworkRigidSync components
## into all RigidBody3D nodes in the scene

## Enable/disable logging
var enable_logging: bool = true

## Registry of all registered rigid bodies (network_id -> NetworkRigidSync)
var registered_bodies: Dictionary = {}

## Filter groups for synchronization
## Objects in "network_sync" group will be synced
## Objects in "network_no_sync" group will NOT be synced
## If both groups are empty, all RigidBody3D will be synced
var sync_group_name: String = ""  # Optional: only sync objects in this group (empty = sync all)
var no_sync_group_name: String = "network_no_sync"  # Optional: exclude objects in this group

## Component name to inject
const COMPONENT_NAME = "NetworkRigidSync"
const COMPONENT_SCRIPT = preload("res://addons/cogito/network/network_rigid_sync.gd")


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
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSyncManager",
		"Injected NetworkRigidSync into %s" % rigid_body.name
	)


## Check if object should be synced based on groups
func _should_sync_object(rigid_body: RigidBody3D) -> bool:
	# If object is in no_sync group, don't sync
	if not no_sync_group_name.is_empty() and rigid_body.is_in_group(no_sync_group_name):
		return false
	
	# If sync_group_name is set, only sync objects in that group
	if not sync_group_name.is_empty():
		return rigid_body.is_in_group(sync_group_name)
	
	# Default: sync all (if no groups are configured)
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
	
	# Re-inject components with new filter
	_find_and_inject_rigid_bodies()


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


## Enable logging for debugging
func set_logging_enabled(enabled: bool) -> void:
	enable_logging = enabled
	# Also enable logging for all registered components
	for network_id in registered_bodies:
		var component = registered_bodies[network_id]
		if component and component.has("enable_logging"):
			component.enable_logging = enabled
