extends RigidBody3D
## Helper script for NetworkRigidSync to use _integrate_forces
## This allows safe state application during physics step
## Note: This script should be attached directly to RigidBody3D nodes

var network_sync_component: Node = null
var target_state: Dictionary = {}
var has_target_state: bool = false

## Flag to enable/disable sync application
var sync_enabled: bool = false

## Interpolation factor (0.0 = snap, 1.0 = full interpolation)
var interpolation_factor: float = 0.3


func _ready():
	# Find NetworkRigidSync component
	await get_tree().process_frame
	for child in get_children():
		if child.name == "NetworkRigidSync":
			network_sync_component = child
			break


func _integrate_forces(state: PhysicsDirectBodyState3D):
	# Called during physics step - safe to modify state
	if not sync_enabled or not has_target_state:
		return
	
	# Extract state data
	var pos_dict = target_state.get("position", {})
	var rot_dict = target_state.get("rotation_quat", {})
	var lin_vel_dict = target_state.get("linear_velocity", {})
	var ang_vel_dict = target_state.get("angular_velocity", {})
	
	var target_pos = Vector3(
		pos_dict.get("x", 0.0),
		pos_dict.get("y", 0.0),
		pos_dict.get("z", 0.0)
	)
	var target_rot = Quaternion(
		rot_dict.get("x", 0.0),
		rot_dict.get("y", 0.0),
		rot_dict.get("z", 0.0),
		rot_dict.get("w", 1.0)
	)
	var target_lin_vel = Vector3(
		lin_vel_dict.get("x", 0.0),
		lin_vel_dict.get("y", 0.0),
		lin_vel_dict.get("z", 0.0)
	)
	var target_ang_vel = Vector3(
		ang_vel_dict.get("x", 0.0),
		ang_vel_dict.get("y", 0.0),
		ang_vel_dict.get("z", 0.0)
	)
	
	# Validate all values
	if not _is_vector_valid(target_pos) or not _is_quaternion_valid(target_rot):
		has_target_state = false
		return
	
	# Normalize quaternion
	target_rot = target_rot.normalized()
	
	# Interpolate current state towards target
	var current_pos = state.transform.origin
	var current_rot = state.transform.basis.get_rotation_quaternion()
	var current_lin_vel = state.linear_velocity
	var current_ang_vel = state.angular_velocity
	
	# Validate current state
	if not _is_vector_valid(current_pos) or not _is_quaternion_valid(current_rot):
		# Current state invalid, snap to target
		current_pos = target_pos
		current_rot = target_rot
		current_lin_vel = target_lin_vel
		current_ang_vel = target_ang_vel
	else:
		# Interpolate
		current_pos = current_pos.lerp(target_pos, interpolation_factor)
		current_rot = current_rot.slerp(target_rot, interpolation_factor).normalized()
		current_lin_vel = current_lin_vel.lerp(target_lin_vel, interpolation_factor)
		current_ang_vel = current_ang_vel.lerp(target_ang_vel, interpolation_factor)
	
	# Final validation before applying
	if _is_vector_valid(current_pos) and _is_quaternion_valid(current_rot):
		# Apply through PhysicsDirectBodyState3D (safe way)
		state.transform.origin = current_pos
		state.transform.basis = Basis(current_rot)
		
		if _is_vector_valid(current_lin_vel):
			state.linear_velocity = current_lin_vel
		if _is_vector_valid(current_ang_vel):
			state.angular_velocity = current_ang_vel
		
		has_target_state = false


func set_target_state(state: Dictionary):
	target_state = state
	has_target_state = true


func set_sync_enabled(enabled: bool):
	sync_enabled = enabled


## Check if vector is valid (not NaN/Infinity)
func _is_vector_valid(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


## Check if quaternion is valid (not NaN/Infinity and normalized)
func _is_quaternion_valid(q: Quaternion) -> bool:
	if not (is_finite(q.x) and is_finite(q.y) and is_finite(q.z) and is_finite(q.w)):
		return false
	# Check if quaternion is normalized (length should be ~1.0)
	var length_sq = q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w
	return abs(length_sq - 1.0) < 0.1  # Allow small error

