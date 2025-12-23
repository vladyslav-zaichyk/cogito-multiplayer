extends Node
## Network Rigid Body Sync Component
## Default: Host-authority (host simulates physics, clients apply states)
## During carry: Client-authority (client-owner simulates and sends states, host and other clients apply states)

const RigidSnapshot = preload("res://addons/cogito/network/rigid_snapshot.gd")

var parent_rigid_body: RigidBody3D = null
var network_id: int = 0
var network_id_component: Node = null
var sync_enabled: bool = false
var enable_logging: bool = false

var sync_rate: float = 20.0
var _sync_timer: float = 0.0
var last_sent_state: Array = []

var snapshot_buffer: Array = []  # Array of RigidSnapshot
var max_buffer_size: int = 40
var interpolation_back_time: float = 0.12  # 120ms
var extrapolation_limit: float = 0.2  # 200ms
var snap_threshold: float = 1.0
var teleport_threshold: float = 5.0

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
	
	if not is_local_owner() and not _is_carried_locally():
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
	var host_time: float = Time.get_ticks_msec() / 1000.0
	if has_node("/root/NetworkClock"):
		var clock = get_node("/root/NetworkClock")
		if clock and clock.has_method("get_estimated_host_time"):
			host_time = clock.get_estimated_host_time()
	return [
		network_id,
		host_time,  # timestamp
		parent_rigid_body.global_position,
		parent_rigid_body.quaternion,
		parent_rigid_body.linear_velocity,
		parent_rigid_body.angular_velocity
	]


func _state_changed(new_state: Array) -> bool:
	if last_sent_state.is_empty():
		return true
	
	# Тепер позиція на індексі 2 (після network_id та timestamp)
	var old_pos: Vector3 = last_sent_state[2]
	var new_pos: Vector3 = new_state[2]
	var pos_changed = (old_pos - new_pos).length_squared() > 0.00001
	
	var old_rot: Quaternion = last_sent_state[3]
	var new_rot: Quaternion = new_state[3]
	var rot_changed = abs(old_rot.angle_to(new_rot)) > 0.001
	
	return pos_changed or rot_changed


func _send_state_update(state: Array, flags: int = 0) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	if network_id == 0:
		_find_network_id_component()
		if network_id_component and network_id_component.has_method("get_network_id"):
			network_id = network_id_component.get_network_id()
		if network_id == 0:
			return
	
	var pos: Vector3 = state[2]  # Тепер позиція на індексі 2 (після timestamp)
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return
	
	# Додаємо flags в кінець
	state.append(flags)
	NetworkManager.sync_rigid_body_state.rpc(state)


func _receive_state_update(state_data: Array) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	if is_local_owner() or not sync_enabled:
		return
	
	if state_data.is_empty() or state_data.size() < 6:  # Тепер 6 елементів (додали timestamp)
		return
	
	var received_network_id: int = state_data[0]
	if received_network_id != network_id:
		return
	
	var timestamp: float = state_data[1]
	var pos: Vector3 = state_data[2]
	var rot: Quaternion = state_data[3]
	var lin_vel: Vector3 = state_data[4]
	var ang_vel: Vector3 = state_data[5]
	var flags: int = state_data[6] if state_data.size() > 6 else 0
	
	# Валідація
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return
	
	if not (is_finite(rot.x) and is_finite(rot.y) and is_finite(rot.z) and is_finite(rot.w)):
		return
	
	rot = rot.normalized()
	
	# Створюємо snapshot
	var snapshot = RigidSnapshot.new()
	snapshot.timestamp = timestamp
	snapshot.position = pos
	snapshot.rotation = rot
	snapshot.linear_velocity = lin_vel
	snapshot.angular_velocity = ang_vel
	snapshot.flags = flags
	
	# Якщо keyframe/teleport/ownership_change - очищаємо буфер і робимо snap
	if flags & (RigidSnapshot.FLAG_KEYFRAME | RigidSnapshot.FLAG_TELEPORT | RigidSnapshot.FLAG_OWNERSHIP_CHANGE):
		snapshot_buffer.clear()
		_apply_snapshot_immediate(snapshot)
		snapshot_buffer.append(snapshot)
		return
	
	# Перевірка на телепорт (велика зміна позиції)
	if snapshot_buffer.size() > 0:
		var last_snap = snapshot_buffer[snapshot_buffer.size() - 1]
		var dist = last_snap.position.distance_to(pos)
		if dist > teleport_threshold:
			snapshot.flags |= RigidSnapshot.FLAG_TELEPORT
			snapshot_buffer.clear()
			_apply_snapshot_immediate(snapshot)
			snapshot_buffer.append(snapshot)
			return
	
	# Вставляємо в буфер
	_insert_snapshot(snapshot)


func _insert_snapshot(snapshot: RigidSnapshot) -> void:
	# Вставляємо в відсортований масив за timestamp
	var inserted = false
	for i in range(snapshot_buffer.size()):
		if snapshot_buffer[i].timestamp > snapshot.timestamp:
			snapshot_buffer.insert(i, snapshot)
			inserted = true
			break
	
	if not inserted:
		snapshot_buffer.append(snapshot)
	
	# Обмежуємо розмір буфера
	if snapshot_buffer.size() > max_buffer_size:
		snapshot_buffer.pop_front()


func _cleanup_old_snapshots() -> void:
	var host_time: float = Time.get_ticks_msec() / 1000.0
	if has_node("/root/NetworkClock"):
		var clock = get_node("/root/NetworkClock")
		if clock and clock.has_method("get_estimated_host_time"):
			host_time = clock.get_estimated_host_time()
	var cutoff_time = host_time - 1.0  # Видаляємо старші за 1 секунду
	
	while snapshot_buffer.size() > 0 and snapshot_buffer[0].timestamp < cutoff_time:
		snapshot_buffer.pop_front()


func _interpolate_to_target(_delta: float) -> void:
	if not parent_rigid_body:
		return
	
	var body_rid = parent_rigid_body.get_rid()
	if not body_rid.is_valid():
		return
	
	# Очищаємо старі snapshot'и
	_cleanup_old_snapshots()
	
	if snapshot_buffer.size() < 2:
		# Недостатньо даних - hold last або екстраполяція
		if snapshot_buffer.size() == 1:
			var host_time: float = Time.get_ticks_msec() / 1000.0
			if has_node("/root/NetworkClock"):
				var clock = get_node("/root/NetworkClock")
				if clock and clock.has_method("get_estimated_host_time"):
					host_time = clock.get_estimated_host_time()
			var render_time = host_time - interpolation_back_time
			var time_passed = render_time - snapshot_buffer[0].timestamp
			if time_passed > 0.0 and time_passed <= extrapolation_limit:
				_extrapolate_from_snapshot(snapshot_buffer[0], time_passed)
			else:
				_apply_snapshot_immediate(snapshot_buffer[0])
		return
	
	# Визначаємо render time (минуле)
	var host_time: float = Time.get_ticks_msec() / 1000.0
	if has_node("/root/NetworkClock"):
		var clock = get_node("/root/NetworkClock")
		if clock and clock.has_method("get_estimated_host_time"):
			host_time = clock.get_estimated_host_time()
	var render_time = host_time - interpolation_back_time
	
	# Шукаємо два snapshot'и навколо render_time
	var prev_snap: RigidSnapshot = null
	var next_snap: RigidSnapshot = null
	
	for i in range(snapshot_buffer.size() - 1):
		if snapshot_buffer[i].timestamp <= render_time and snapshot_buffer[i + 1].timestamp >= render_time:
			prev_snap = snapshot_buffer[i]
			next_snap = snapshot_buffer[i + 1]
			break
	
	if prev_snap and next_snap:
		# ІНТЕРПОЛЯЦІЯ
		var total_time = next_snap.timestamp - prev_snap.timestamp
		if total_time <= 0.0:
			total_time = 0.001
		
		var time_since_prev = render_time - prev_snap.timestamp
		var alpha = clamp(time_since_prev / total_time, 0.0, 1.0)
		
		var interp_pos = prev_snap.position.lerp(next_snap.position, alpha)
		var interp_rot = prev_snap.rotation.slerp(next_snap.rotation, alpha)
		var interp_lin_vel = prev_snap.linear_velocity.lerp(next_snap.linear_velocity, alpha)
		var interp_ang_vel = prev_snap.angular_velocity.lerp(next_snap.angular_velocity, alpha)
		
		var interp_transform = Transform3D(Basis(interp_rot), interp_pos)
		
		# Валідація
		if not (_is_finite(interp_transform.origin) and _is_finite(interp_transform.basis.x) and _is_finite(interp_transform.basis.y) and _is_finite(interp_transform.basis.z)):
			return
		
		# Застосовуємо через PhysicsServer (правильний спосіб для kinematic)
		PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, interp_transform)
		PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, interp_lin_vel)
		PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, interp_ang_vel)
		
	elif snapshot_buffer.size() > 0:
		# ЕКСТРАПОЛЯЦІЯ (немає наступного snapshot'а)
		var latest = snapshot_buffer[snapshot_buffer.size() - 1]
		var time_passed = render_time - latest.timestamp
		
		if time_passed > 0.0 and time_passed <= extrapolation_limit:
			_extrapolate_from_snapshot(latest, time_passed)
		else:
			# Hold last
			_apply_snapshot_immediate(latest)


func _extrapolate_from_snapshot(snap: RigidSnapshot, dt: float) -> void:
	var body_rid = parent_rigid_body.get_rid()
	if not body_rid.is_valid():
		return
	
	var extrapolated_pos = snap.position + (snap.linear_velocity * dt)
	var extrapolated_rot = snap.rotation  # Спрощено - можна інтегрувати angular_velocity
	
	var extrapolated_transform = Transform3D(Basis(extrapolated_rot), extrapolated_pos)
	
	# Валідація
	if not (_is_finite(extrapolated_transform.origin) and _is_finite(extrapolated_transform.basis.x) and _is_finite(extrapolated_transform.basis.y) and _is_finite(extrapolated_transform.basis.z)):
		return
	
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, extrapolated_transform)
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, snap.linear_velocity)


func _apply_snapshot_immediate(snap: RigidSnapshot) -> void:
	var body_rid = parent_rigid_body.get_rid()
	if not body_rid.is_valid():
		return
	
	var transform = Transform3D(Basis(snap.rotation), snap.position)
	
	# Валідація
	if not (_is_finite(transform.origin) and _is_finite(transform.basis.x) and _is_finite(transform.basis.y) and _is_finite(transform.basis.z)):
		return
	
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, transform)
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, snap.linear_velocity)
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, snap.angular_velocity)


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
		# Стали owner - відправляємо keyframe
		var preserve_velocity = parent_rigid_body.linear_velocity
		if snapshot_buffer.size() > 0:
			var last_snap = snapshot_buffer[snapshot_buffer.size() - 1]
			preserve_velocity = last_snap.linear_velocity
		
		parent_rigid_body.freeze = false
		parent_rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		parent_rigid_body.linear_velocity = preserve_velocity
		
		if parent_rigid_body.sleeping:
			parent_rigid_body.sleeping = false
		
		# Очищаємо буфер і відправляємо keyframe
		snapshot_buffer.clear()
		var state = _collect_state()
		if not state.is_empty():
			_send_state_update(state, RigidSnapshot.FLAG_KEYFRAME | RigidSnapshot.FLAG_OWNERSHIP_CHANGE)
		
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
		# Перестали бути owner - очищаємо буфер
		snapshot_buffer.clear()
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
