extends Node
## Network Rigid Body Sync Component
## Host-authority: Host simulates physics, clients apply states
## Client interactions are handled through existing network commands

var parent_rigid_body: RigidBody3D = null
var network_id: String = ""
var sync_enabled: bool = false

# Rate limiting
var send_interval_frames: int = 2  # Send every 2 frames for smoother sync
var frames_since_last_send: int = 0
var last_sent_state: Dictionary = {}

# Client state application
var pending_state: Dictionary = {}
var has_pending_state: bool = false

# Interpolation targets
var target_transform: Transform3D = Transform3D.IDENTITY
var target_linear_velocity: Vector3 = Vector3.ZERO
var target_angular_velocity: Vector3 = Vector3.ZERO
var has_target: bool = false

# Interpolation settings
var interpolation_frames: int = 2  # Interpolate over 2 physics ticks
var interpolation_frame_count: int = 0
var snap_threshold: float = 1.0  # If error > 1.0m, snap instead of interpolate

# Carry handling (for skipping state application when carried locally)
var carryable_component: Node = null


func _ready() -> void:
	parent_rigid_body = get_parent() as RigidBody3D
	if not parent_rigid_body:
		push_error("NetworkRigidSync: Parent must be a RigidBody3D")
		return
	
	await get_tree().process_frame
	
	network_id = _generate_network_id()
	if network_id.is_empty():
		push_error("NetworkRigidSync: Failed to generate network_id")
		return
	
	if NetworkRigidSyncManager:
		NetworkRigidSyncManager.register_rigid_body(self)
	
	# Find carryable component and connect to signal
	_find_carryable_component()
	if carryable_component and carryable_component.has_signal("carry_state_changed"):
		carryable_component.carry_state_changed.connect(_on_carry_state_changed)
	
	await get_tree().create_timer(0.5).timeout


func _physics_process(_delta: float) -> void:
	if not parent_rigid_body or not is_instance_valid(parent_rigid_body):
		return
	
	# Client: Update target from pending state (skip if being carried locally)
	if has_pending_state and NetworkManager and NetworkManager.is_multiplayer():
		var local_peer_id = NetworkManager.get_local_peer_id()
		if local_peer_id != 1:  # Client
			if not _is_carried_locally():
				_update_target_from_pending()
	
	# Client: Interpolate to target (applies state in _physics_process via PhysicsServer3D)
	if has_target and NetworkManager and NetworkManager.is_multiplayer():
		var local_peer_id = NetworkManager.get_local_peer_id()
		if local_peer_id != 1 and not _is_carried_locally():  # Client
			_interpolate_to_target(_delta)
	
	# Host: Send state
	if sync_enabled and NetworkManager and NetworkManager.is_multiplayer():
		var local_peer_id = NetworkManager.get_local_peer_id()
		if local_peer_id == 1:  # Host
			frames_since_last_send += 1
			
			# If object is being carried, send more frequently
			var is_carried = _is_carried_on_host()
			var interval = send_interval_frames if not is_carried else 1  # Every frame if carried
			
			if frames_since_last_send >= interval:
				var current_state = _collect_state()
				# If carried, always send (even if position didn't change)
				# This prevents client from "resuming" physics when host stops moving
				if last_sent_state.is_empty() or _state_changed(current_state) or is_carried:
					_send_state_update(current_state)
					last_sent_state = current_state.duplicate()
					frames_since_last_send = 0


func _generate_network_id() -> String:
	var scene = get_tree().current_scene
	if not scene:
		return ""
	
	var scene_path = scene.scene_file_path
	if scene_path.is_empty():
		scene_path = scene.name
	
	var node_path = parent_rigid_body.get_path()
	return "%s::%s" % [scene_path, str(node_path)]


func _collect_state() -> Dictionary:
	if not parent_rigid_body:
		return {}
	
	return {
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
		}
	}


func _state_changed(new_state: Dictionary) -> bool:
	if last_sent_state.is_empty():
		return true
	
	var old_pos = Vector3(
		last_sent_state.position.x,
		last_sent_state.position.y,
		last_sent_state.position.z
	)
	var new_pos = Vector3(
		new_state.position.x,
		new_state.position.y,
		new_state.position.z
	)
	
	# Check position change (smaller threshold for smoother sync)
	var pos_changed = (old_pos - new_pos).length_squared() > 0.00001
	
	# Check rotation change
	var old_rot = Quaternion(
		last_sent_state.rotation_quat.x,
		last_sent_state.rotation_quat.y,
		last_sent_state.rotation_quat.z,
		last_sent_state.rotation_quat.w
	)
	var new_rot = Quaternion(
		new_state.rotation_quat.x,
		new_state.rotation_quat.y,
		new_state.rotation_quat.z,
		new_state.rotation_quat.w
	)
	var rot_changed = abs(old_rot.angle_to(new_rot)) > 0.001
	
	return pos_changed or rot_changed


func _send_state_update(state: Dictionary) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# Validate
	var pos = Vector3(state.position.x, state.position.y, state.position.z)
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return
	
	var state_data = {
		"network_id": network_id,
		"position": state.position,
		"rotation_quat": state.rotation_quat,
		"linear_velocity": state.linear_velocity,
		"angular_velocity": state.angular_velocity
	}
	
	NetworkManager.sync_rigid_body_state.rpc(state_data)


func _receive_state_update(state_data: Dictionary) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	var local_peer_id = NetworkManager.get_local_peer_id()
	if local_peer_id == 1:  # Host doesn't apply
		return
	
	if not sync_enabled:
		return
	
	var received_network_id = state_data.get("network_id", "")
	if received_network_id != network_id:
		return
	
	pending_state = state_data
	has_pending_state = true


func _update_target_from_pending() -> void:
	if not has_pending_state or not parent_rigid_body:
		return
	
	var state_data = pending_state
	has_pending_state = false
	
	# Extract data
	var pos = Vector3(
		state_data.position.x,
		state_data.position.y,
		state_data.position.z
	)
	var rot = Quaternion(
		state_data.rotation_quat.x,
		state_data.rotation_quat.y,
		state_data.rotation_quat.z,
		state_data.rotation_quat.w
	)
	var lin_vel = Vector3(
		state_data.linear_velocity.x,
		state_data.linear_velocity.y,
		state_data.linear_velocity.z
	)
	var ang_vel = Vector3(
		state_data.angular_velocity.x,
		state_data.angular_velocity.y,
		state_data.angular_velocity.z
	)
	
	# Validate
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return
	
	if not (is_finite(rot.x) and is_finite(rot.y) and is_finite(rot.z) and is_finite(rot.w)):
		return
	
	# Normalize quaternion
	rot = rot.normalized()
	
	# Validate normalized quaternion
	var rot_len_sq = rot.x * rot.x + rot.y * rot.y + rot.z * rot.z + rot.w * rot.w
	if abs(rot_len_sq - 1.0) > 0.1:
		return
	
	# Create target transform
	var basis = Basis(rot)
	if not (_is_finite(basis.x) and _is_finite(basis.y) and _is_finite(basis.z)):
		return
	
	target_transform = Transform3D(basis, pos)
	
	# Validate velocities
	if is_finite(lin_vel.x) and is_finite(lin_vel.y) and is_finite(lin_vel.z):
		target_linear_velocity = lin_vel
	else:
		target_linear_velocity = Vector3.ZERO
	
	if is_finite(ang_vel.x) and is_finite(ang_vel.y) and is_finite(ang_vel.z):
		target_angular_velocity = ang_vel
	else:
		target_angular_velocity = Vector3.ZERO
	
	# Check if we should snap (large error)
	var current_pos = parent_rigid_body.global_position
	var error = (current_pos - pos).length()
	
	if error > snap_threshold:
		# Large error - snap immediately (set frame count to max)
		interpolation_frame_count = interpolation_frames
	else:
		# Small error - interpolate (start from 0)
		interpolation_frame_count = 0
	
	has_target = true


## Interpolate to target state (called from _physics_process)
## Applies state via PhysicsServer3D.body_set_state() in _physics_process
## This is the correct place to modify RigidBody3D state
func _interpolate_to_target(_delta: float) -> void:
	if not has_target or not parent_rigid_body:
		return
	
	var body_rid = parent_rigid_body.get_rid()
	if not body_rid.is_valid():
		return
	
	# Update frame count
	interpolation_frame_count += 1
	
	# Calculate interpolation alpha (0.0 to 1.0)
	var alpha = float(interpolation_frame_count) / float(interpolation_frames)
	if alpha > 1.0:
		alpha = 1.0
	
	# Get current transform
	var current_transform = parent_rigid_body.global_transform
	
	# Interpolate position (lerp)
	var current_pos = current_transform.origin
	var target_pos = target_transform.origin
	var lerped_pos = current_pos.lerp(target_pos, alpha)
	
	# Interpolate rotation (slerp quaternion)
	var current_rot = current_transform.basis.get_rotation_quaternion()
	var target_rot = target_transform.basis.get_rotation_quaternion()
	var slerped_rot = current_rot.slerp(target_rot, alpha)
	
	# Create interpolated transform
	var interpolated_transform = Transform3D(Basis(slerped_rot), lerped_pos)
	
	# Interpolate velocities (lerp)
	var current_lin_vel = parent_rigid_body.linear_velocity
	var current_ang_vel = parent_rigid_body.angular_velocity
	var lerped_lin_vel = current_lin_vel.lerp(target_linear_velocity, alpha)
	var lerped_ang_vel = current_ang_vel.lerp(target_angular_velocity, alpha)
	
	# Validate before applying
	if not (_is_finite(interpolated_transform.origin) and _is_finite(interpolated_transform.basis.x) and _is_finite(interpolated_transform.basis.y) and _is_finite(interpolated_transform.basis.z)):
		return
	
	# Apply interpolated state
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, interpolated_transform)
	
	if _is_finite(lerped_lin_vel):
		PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, lerped_lin_vel)
	if _is_finite(lerped_ang_vel):
		PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, lerped_ang_vel)
	
	# If interpolation complete, reset
	if interpolation_frame_count >= interpolation_frames:
		has_target = false
		interpolation_frame_count = 0


func _is_finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func set_sync_enabled(enabled: bool) -> void:
	if not parent_rigid_body:
		return
	
	sync_enabled = enabled
	
	if enabled and NetworkManager and NetworkManager.is_multiplayer():
		parent_rigid_body.set_multiplayer_authority(1)
		
		var local_peer_id = NetworkManager.get_local_peer_id()
		if local_peer_id == 1:  # Host
			parent_rigid_body.freeze = false  # Host simulates physics
		else:  # Client
			parent_rigid_body.freeze = true  # Client only receives states (no local physics)
			parent_rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func get_network_id() -> String:
	return network_id


func get_parent_rigid_body() -> RigidBody3D:
	return parent_rigid_body


func _find_carryable_component() -> void:
	if not parent_rigid_body:
		return
	
	for child in parent_rigid_body.get_children():
		if child is CogitoCarryableComponent:
			carryable_component = child
			break


func _is_carried_locally() -> bool:
	# Only check on clients
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return false
	
	var local_peer_id = NetworkManager.get_local_peer_id()
	if local_peer_id == 1:  # Host
		return false
	
	# Check if object is being carried locally
	if carryable_component and "is_being_carried" in carryable_component:
		return carryable_component.is_being_carried
	
	return false


func _is_carried_on_host() -> bool:
	# Only check on host
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return false
	
	var local_peer_id = NetworkManager.get_local_peer_id()
	if local_peer_id != 1:  # Not host
		return false
	
	# Check if object is being carried on host
	if carryable_component and "is_being_carried" in carryable_component:
		return carryable_component.is_being_carried
	
	return false


func _on_carry_state_changed(is_carried: bool) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	var local_peer_id = NetworkManager.get_local_peer_id()
	if local_peer_id == 1:  # Host - no changes needed
		return
	
	# On client: when object is carried, temporarily unfreeze for carry system
	# When dropped, freeze again to prevent local physics simulation
	if is_carried:
		parent_rigid_body.freeze = false  # Temporarily unfreeze for carry
	else:
		parent_rigid_body.freeze = true  # Freeze again (network-controlled)


func _exit_tree() -> void:
	if NetworkRigidSyncManager and not network_id.is_empty():
		NetworkRigidSyncManager.unregister_rigid_body(network_id)
