extends Node
## Network Rigid Body Sync Component
## Default: Host-authority (host simulates physics, clients apply states)
## During carry: Client-authority (client-owner simulates and sends states, host and other clients apply states)

var parent_rigid_body: RigidBody3D = null
var network_id: int = 0
var network_id_component: Node = null
var sync_enabled: bool = false
var enable_logging: bool = false

var sync_rate: float = 20.0
var _sync_timer: float = 0.0
var last_sent_state: Array = []

var pending_state: Array = []
var has_pending_state: bool = false

var target_transform: Transform3D = Transform3D.IDENTITY
var target_linear_velocity: Vector3 = Vector3.ZERO
var target_angular_velocity: Vector3 = Vector3.ZERO
var has_target: bool = false

var interpolation_frames: int = 2
var interpolation_frame_count: int = 0
var snap_threshold: float = 1.0

var carryable_component: Node = null
var owner_peer_id: int = 1
var ownership_requested: bool = false
var drop_timer: float = 0.0
var drop_timer_duration: float = 1.0


func _ready() -> void:
	parent_rigid_body = get_parent() as RigidBody3D
	if not parent_rigid_body:
		push_error("NetworkRigidSync: Parent must be a RigidBody3D")
		return
	
	await get_tree().process_frame
	_find_network_id_component()
	
	if NetworkManager and NetworkManager.is_multiplayer() and NetworkManager.is_host():
		if not network_id_component:
			network_id = await _generate_network_id()
		else:
			var retries = 0
			while network_id == 0 and retries < 10:
				await get_tree().process_frame
				if network_id_component and network_id_component.has_method("get_network_id"):
					network_id = network_id_component.get_network_id()
				retries += 1
	else:
		var retries = 0
		var max_retries = 40
		while network_id == 0 and retries < max_retries:
			await get_tree().create_timer(0.05).timeout
			_find_network_id_component()
			if network_id_component and network_id_component.has_method("get_network_id"):
				network_id = network_id_component.get_network_id()
			retries += 1
	
	if network_id == 0:
		push_error("NetworkRigidSync: Failed to get network_id for %s after retries" % parent_rigid_body.name)
		_try_register_later()
	elif NetworkRigidSyncManager:
		NetworkRigidSyncManager.register_rigid_body(self)
	
	_find_carryable_component()
	if carryable_component and carryable_component.has_signal("carry_state_changed"):
		carryable_component.carry_state_changed.connect(_on_carry_state_changed)
	
	await get_tree().create_timer(0.5).timeout


func _try_register_later() -> void:
	var check_timer = Timer.new()
	check_timer.wait_time = 0.1
	check_timer.one_shot = false
	check_timer.timeout.connect(_check_and_register)
	add_child(check_timer)
	check_timer.start()
	await get_tree().create_timer(5.0).timeout
	check_timer.queue_free()


func _check_and_register() -> void:
	_find_network_id_component()
	if network_id_component and network_id_component.has_method("get_network_id"):
		var new_network_id = network_id_component.get_network_id()
		if new_network_id != 0 and network_id == 0:
			network_id = new_network_id
			if NetworkRigidSyncManager:
				NetworkRigidSyncManager.register_rigid_body(self)


func is_local_owner() -> bool:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return false
	var local_peer_id = NetworkManager.get_local_peer_id()
	return owner_peer_id == local_peer_id


func _physics_process(_delta: float) -> void:
	if not parent_rigid_body or not is_instance_valid(parent_rigid_body):
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	if has_pending_state and not is_local_owner() and not _is_carried_locally():
		_update_target_from_pending()
	
	if has_target and not is_local_owner() and not _is_carried_locally():
		_interpolate_to_target(_delta)
	
	if sync_enabled and NetworkManager and NetworkManager.is_multiplayer():
		var local_peer_id = NetworkManager.get_local_peer_id()
		
		if owner_peer_id == local_peer_id and network_id == 0:
			_find_network_id_component()
			if network_id_component and network_id_component.has_method("get_network_id"):
				network_id = network_id_component.get_network_id()
		
		if owner_peer_id == local_peer_id:
			var is_carried = _is_carried_locally() if local_peer_id != 1 else _is_carried_on_host()
			
			if network_id == 0:
				_find_network_id_component()
				if network_id_component and network_id_component.has_method("get_network_id"):
					network_id = network_id_component.get_network_id()
			
			if network_id == 0 or not sync_enabled:
				return
			
			var current_sync_rate = sync_rate if not is_carried else sync_rate * 2.0
			_sync_timer += _delta
			
			if _sync_timer >= (1.0 / current_sync_rate):
				_sync_timer = 0.0
				var current_state = _collect_state()
				if current_state.is_empty():
					return
				
				var should_send = last_sent_state.is_empty() or _state_changed(current_state) or is_carried
				if should_send:
					_send_state_update(current_state)
					last_sent_state = current_state.duplicate()
		
		if owner_peer_id != 1 and local_peer_id == owner_peer_id:
			if _is_carried_locally():
				drop_timer = 0.0
			elif drop_timer > 0.0:
				drop_timer += _delta
				if drop_timer >= drop_timer_duration:
					_return_ownership_to_host()


func _find_network_id_component() -> void:
	for child in parent_rigid_body.get_children():
		if child.get_script() and child.get_script().resource_path.ends_with("network_rigid_body_id.gd"):
			network_id_component = child
			if network_id_component.has_method("get_network_id"):
				network_id = network_id_component.get_network_id()
			break


func _generate_network_id() -> int:
	if not NetworkManager or not NetworkManager.is_multiplayer() or not NetworkManager.is_host():
		return 0
	
	_find_network_id_component()
	
	if network_id_component and network_id_component.has_method("get_network_id"):
		var existing_id = network_id_component.get_network_id()
		if existing_id != 0:
			return existing_id
	
	if not network_id_component:
		var network_id_script = preload("res://addons/cogito/network/network_rigid_body_id.gd")
		network_id_component = network_id_script.new()
		network_id_component.name = "NetworkRigidBodyID"
		parent_rigid_body.add_child(network_id_component)
	
	var retries = 0
	while retries < 20:
		await get_tree().create_timer(0.05).timeout
		if network_id_component and network_id_component.has_method("get_network_id"):
			var generated_id = network_id_component.get_network_id()
			if generated_id != 0:
				return generated_id
		retries += 1
	
	return 0


func _collect_state() -> Array:
	if not parent_rigid_body:
		return []
	return [
		network_id,
		parent_rigid_body.global_position,
		parent_rigid_body.quaternion,
		parent_rigid_body.linear_velocity,
		parent_rigid_body.angular_velocity
	]


func _state_changed(new_state: Array) -> bool:
	if last_sent_state.is_empty():
		return true
	
	var old_pos: Vector3 = last_sent_state[1]
	var new_pos: Vector3 = new_state[1]
	var pos_changed = (old_pos - new_pos).length_squared() > 0.00001
	
	var old_rot: Quaternion = last_sent_state[2]
	var new_rot: Quaternion = new_state[2]
	var rot_changed = abs(old_rot.angle_to(new_rot)) > 0.001
	
	return pos_changed or rot_changed


func _send_state_update(state: Array) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	if network_id == 0:
		_find_network_id_component()
		if network_id_component and network_id_component.has_method("get_network_id"):
			network_id = network_id_component.get_network_id()
		if network_id == 0:
			return
	
	var pos: Vector3 = state[1]
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return
	
	NetworkManager.sync_rigid_body_state.rpc(state)


func _receive_state_update(state_data: Array) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	if is_local_owner() or not sync_enabled:
		return
	
	if state_data.is_empty() or state_data.size() < 5:
		return
	
	var received_network_id: int = state_data[0]
	if received_network_id != network_id:
		return
	
	pending_state = state_data
	has_pending_state = true


func _update_target_from_pending() -> void:
	if not has_pending_state or not parent_rigid_body:
		return
	
	var state_data = pending_state
	has_pending_state = false
	
	if state_data.is_empty() or state_data.size() < 5:
		return
	
	var pos: Vector3 = state_data[1]
	var rot: Quaternion = state_data[2]
	var lin_vel: Vector3 = state_data[3]
	var ang_vel: Vector3 = state_data[4]
	
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return
	
	if not (is_finite(rot.x) and is_finite(rot.y) and is_finite(rot.z) and is_finite(rot.w)):
		return
	
	rot = rot.normalized()
	var rot_len_sq = rot.x * rot.x + rot.y * rot.y + rot.z * rot.z + rot.w * rot.w
	if abs(rot_len_sq - 1.0) > 0.1:
		return
	
	var basis = Basis(rot)
	if not (_is_finite(basis.x) and _is_finite(basis.y) and _is_finite(basis.z)):
		return
	
	target_transform = Transform3D(basis, pos)
	
	target_linear_velocity = lin_vel if is_finite(lin_vel.x) and is_finite(lin_vel.y) and is_finite(lin_vel.z) else Vector3.ZERO
	target_angular_velocity = ang_vel if is_finite(ang_vel.x) and is_finite(ang_vel.y) and is_finite(ang_vel.z) else Vector3.ZERO
	
	var current_pos = parent_rigid_body.global_position
	var error = (current_pos - pos).length()
	interpolation_frame_count = interpolation_frames if error > snap_threshold else 0
	has_target = true


func _interpolate_to_target(_delta: float) -> void:
	if not has_target or not parent_rigid_body:
		return
	
	var body_rid = parent_rigid_body.get_rid()
	if not body_rid.is_valid():
		return
	
	interpolation_frame_count += 1
	var alpha = min(float(interpolation_frame_count) / float(interpolation_frames), 1.0)
	
	var current_transform = parent_rigid_body.global_transform
	var current_pos = current_transform.origin
	var target_pos = target_transform.origin
	var lerped_pos = current_pos.lerp(target_pos, alpha)
	
	var current_rot = current_transform.basis.get_rotation_quaternion()
	var target_rot = target_transform.basis.get_rotation_quaternion()
	var slerped_rot = current_rot.slerp(target_rot, alpha)
	
	var interpolated_transform = Transform3D(Basis(slerped_rot), lerped_pos)
	
	var current_lin_vel = parent_rigid_body.linear_velocity
	var current_ang_vel = parent_rigid_body.angular_velocity
	var lerped_lin_vel = current_lin_vel.lerp(target_linear_velocity, alpha)
	var lerped_ang_vel = current_ang_vel.lerp(target_angular_velocity, alpha)
	
	if not (_is_finite(interpolated_transform.origin) and _is_finite(interpolated_transform.basis.x) and _is_finite(interpolated_transform.basis.y) and _is_finite(interpolated_transform.basis.z)):
		return
	
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, interpolated_transform)
	
	if not parent_rigid_body.freeze:
		if _is_finite(lerped_lin_vel):
			PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, lerped_lin_vel)
		if _is_finite(lerped_ang_vel):
			PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, lerped_ang_vel)
	
	if interpolation_frame_count >= interpolation_frames:
		has_target = false
		interpolation_frame_count = 0


func _is_finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func set_sync_enabled(enabled: bool) -> void:
	if not parent_rigid_body:
		return
	
	var freeze_before = parent_rigid_body.freeze
	var sync_enabled_before = sync_enabled
	sync_enabled = enabled
	
	if enabled and NetworkManager and NetworkManager.is_multiplayer():
		var local_peer_id = NetworkManager.get_local_peer_id()
		
		if owner_peer_id == 0:
			owner_peer_id = 1
		
		parent_rigid_body.set_multiplayer_authority(owner_peer_id)
		
		if owner_peer_id == local_peer_id:
			parent_rigid_body.freeze = false
		else:
			parent_rigid_body.freeze = true
			parent_rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func get_network_id() -> int:
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
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return false
	if carryable_component and "is_being_carried" in carryable_component:
		return carryable_component.is_being_carried
	return false


func _is_carried_on_host() -> bool:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return false
	var local_peer_id = NetworkManager.get_local_peer_id()
	if local_peer_id != 1:
		return false
	if carryable_component and "is_being_carried" in carryable_component:
		return carryable_component.is_being_carried
	return false


func _on_carry_state_changed(is_carried: bool) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	var local_peer_id = NetworkManager.get_local_peer_id()
	
	if is_carried:
		if local_peer_id == 1:
			parent_rigid_body.freeze = false
		else:
			_request_ownership()
			drop_timer = 0.0
	else:
		if local_peer_id != 1:
			drop_timer = 0.001


func _request_ownership() -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	var local_peer_id = NetworkManager.get_local_peer_id()
	if local_peer_id == 1 or ownership_requested:
		return
	ownership_requested = true
	NetworkManager.request_rigid_body_ownership.rpc_id(1, network_id)


func _set_ownership(peer_id: int) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	var local_peer_id = NetworkManager.get_local_peer_id()
	
	owner_peer_id = peer_id
	ownership_requested = false
	drop_timer = 0.0  # Reset drop timer
	
	# Set multiplayer authority to the owner
	parent_rigid_body.set_multiplayer_authority(peer_id)
	
	if peer_id == local_peer_id:
		var preserve_velocity = target_linear_velocity if has_target else parent_rigid_body.linear_velocity
		
		parent_rigid_body.freeze = false
		parent_rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		parent_rigid_body.linear_velocity = preserve_velocity
		
		if parent_rigid_body.sleeping:
			parent_rigid_body.sleeping = false
		
		has_target = false
		has_pending_state = false
		
		if network_id == 0:
			_find_network_id_component()
			if network_id_component and network_id_component.has_method("get_network_id"):
				network_id = network_id_component.get_network_id()
			if network_id == 0:
				push_error("NetworkRigidSync: Became owner but network_id is 0 for %s" % parent_rigid_body.name)
				return
		
		if network_id != 0 and NetworkRigidSyncManager:
			var existing = NetworkRigidSyncManager.get_rigid_body(network_id)
			if existing != self:
				NetworkRigidSyncManager.register_rigid_body(self)
		
		if not sync_enabled:
			sync_enabled = true
			parent_rigid_body.set_multiplayer_authority(peer_id)
			parent_rigid_body.freeze = false
		else:
			parent_rigid_body.set_multiplayer_authority(peer_id)
			parent_rigid_body.freeze = false
		
		if parent_rigid_body.freeze:
			push_warning("NetworkRigidSync: freeze was true after becoming owner! Forcing to false for network_id=%d" % network_id)
			parent_rigid_body.freeze = false
	else:
		parent_rigid_body.freeze = true
		parent_rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func _return_ownership_to_host() -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	var local_peer_id = NetworkManager.get_local_peer_id()
	if local_peer_id != owner_peer_id:
		return
	NetworkManager.return_rigid_body_ownership.rpc_id(1, network_id)
	owner_peer_id = 1
	ownership_requested = false
	drop_timer = 0.0
	parent_rigid_body.freeze = true
	parent_rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func _exit_tree() -> void:
	if NetworkRigidSyncManager and network_id != 0:
		NetworkRigidSyncManager.unregister_rigid_body(network_id)
