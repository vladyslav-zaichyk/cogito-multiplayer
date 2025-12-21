extends Node
## Network Rigid Body Sync Component
## Automatically injected into RigidBody3D nodes for physics synchronization
## Collects physics state and handles network synchronization

## Enable/disable logging
var enable_logging: bool = false

## Reference to the parent RigidBody3D
var parent_rigid_body: RigidBody3D = null

## Unique network ID for this rigid body (based on scene path + node path)
var network_id: String = ""

## Last collected state (for comparison)
var last_state: Dictionary = {}

## Is this object active for synchronization (always true in Phase 0)
var is_active: bool = true

## Is sync enabled (false by default, will be enabled in Phase 1)
var sync_enabled: bool = false


func _ready() -> void:
	parent_rigid_body = get_parent() as RigidBody3D
	if not parent_rigid_body:
		push_error("NetworkRigidSync: Parent must be a RigidBody3D")
		return
	
	# Wait a frame for parent to be fully initialized
	await get_tree().process_frame
	
	# Generate network ID
	network_id = _generate_network_id()
	
	if network_id.is_empty():
		push_error("NetworkRigidSync: Failed to generate network_id for %s" % parent_rigid_body.name)
		return
	
	# Register with NetworkRigidSyncManager
	if NetworkRigidSyncManager:
		NetworkRigidSyncManager.register_rigid_body(self)
	
	# Collect initial state
	last_state = _collect_state()
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSync",
		"Initialized for %s (network_id: %s)" % [parent_rigid_body.name, network_id]
	)


func _physics_process(_delta: float) -> void:
	if not parent_rigid_body or not is_node_valid(parent_rigid_body):
		return
	
	# Collect current state
	var current_state = _collect_state()
	
	# Log state changes (for debugging in Phase 0)
	if enable_logging and _has_state_changed(current_state):
		_log_state_change(current_state)
	
	# Update last state
	last_state = current_state
	
	# Note: Network sending will be added in Phase 1


## Generate unique network ID for this rigid body
func _generate_network_id() -> String:
	var scene = get_tree().current_scene
	if not scene:
		push_error("NetworkRigidSync: No current scene for network_id generation")
		return ""
	
	var scene_path = scene.scene_file_path
	if scene_path.is_empty():
		# Fallback: use scene name
		scene_path = scene.name
	
	var node_path = parent_rigid_body.get_path()
	
	# Combine scene path and node path for unique ID
	var id = "%s::%s" % [scene_path, str(node_path)]
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSync",
		"Generated network_id: %s (scene: %s, path: %s)" % [id, scene_path, node_path]
	)
	
	return id


## Collect current physics state
func _collect_state() -> Dictionary:
	if not parent_rigid_body:
		return {}
	
	var state = {
		"network_id": network_id,
		"position": {
			"x": parent_rigid_body.global_position.x,
			"y": parent_rigid_body.global_position.y,
			"z": parent_rigid_body.global_position.z
		},
		"rotation_quat": {
			"x": parent_rigid_body.quaternion.x,
			"y": parent_rigid_body.quaternion.y,
			"z": parent_rigid_body.quaternion.z,
			"w": parent_rigid_body.quaternion.w
		},
		"linear_velocity": {
			"x": parent_rigid_body.linear_velocity.x,
			"y": parent_rigid_body.linear_velocity.y,
			"z": parent_rigid_body.linear_velocity.z
		},
		"angular_velocity": {
			"x": parent_rigid_body.angular_velocity.x,
			"y": parent_rigid_body.angular_velocity.y,
			"z": parent_rigid_body.angular_velocity.z
		},
		"sleeping": parent_rigid_body.sleeping,
		"timestamp": Time.get_ticks_msec() / 1000.0
	}
	
	return state


## Check if state has changed
func _has_state_changed(new_state: Dictionary) -> bool:
	if last_state.is_empty():
		return true
	
	# Compare key properties
	if not _vectors_equal(
		Vector3(new_state.position.x, new_state.position.y, new_state.position.z),
		Vector3(last_state.position.x, last_state.position.y, last_state.position.z),
		0.001
	):
		return true
	
	if not _quaternions_equal(
		Quaternion(new_state.rotation_quat.x, new_state.rotation_quat.y, new_state.rotation_quat.z, new_state.rotation_quat.w),
		Quaternion(last_state.rotation_quat.x, last_state.rotation_quat.y, last_state.rotation_quat.z, last_state.rotation_quat.w),
		0.001
	):
		return true
	
	if not _vectors_equal(
		Vector3(new_state.linear_velocity.x, new_state.linear_velocity.y, new_state.linear_velocity.z),
		Vector3(last_state.linear_velocity.x, last_state.linear_velocity.y, last_state.linear_velocity.z),
		0.01
	):
		return true
	
	if new_state.sleeping != last_state.get("sleeping", false):
		return true
	
	return false


## Helper: Compare two Vector3 with epsilon
func _vectors_equal(v1: Vector3, v2: Vector3, epsilon: float) -> bool:
	return (v1 - v2).length() < epsilon


## Helper: Compare two Quaternions with epsilon
func _quaternions_equal(q1: Quaternion, q2: Quaternion, epsilon: float) -> bool:
	# Compare using angle between quaternions
	return abs(q1.angle_to(q2)) < epsilon


## Log state change (for debugging)
func _log_state_change(state: Dictionary) -> void:
	var pos = Vector3(state.position.x, state.position.y, state.position.z)
	var lin_vel = Vector3(state.linear_velocity.x, state.linear_velocity.y, state.linear_velocity.z)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSync",
		"[%s] State changed - pos: %s, lin_vel: %s, sleeping: %s" % [
			network_id,
			pos,
			lin_vel,
			state.sleeping
		]
	)


## Get network ID
func get_network_id() -> String:
	return network_id


## Get parent rigid body
func get_parent_rigid_body() -> RigidBody3D:
	return parent_rigid_body


## Enable sync (will be used in Phase 1)
func set_sync_enabled(enabled: bool) -> void:
	sync_enabled = enabled
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSync",
		"[%s] Sync %s" % [network_id, "enabled" if enabled else "disabled"]
	)


func _exit_tree() -> void:
	# Unregister from manager when component is removed
	if NetworkRigidSyncManager and not network_id.is_empty():
		NetworkRigidSyncManager.unregister_rigid_body(network_id)


## Check if node is valid (helper for safety)
func is_node_valid(node: Node) -> bool:
	return node != null and is_instance_valid(node) and node.is_inside_tree()

