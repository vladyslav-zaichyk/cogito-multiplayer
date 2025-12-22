extends Node
## Network Rigid Body Sync Component
## Default: Host-authority (host simulates physics, clients apply states)
## During carry: Client-authority (client-owner simulates and sends states, host and other clients apply states)

var parent_rigid_body: RigidBody3D = null
var network_id: int = 0  # Stable network ID (set by NetworkRigidBodyID component)
var network_id_component: Node = null  # Reference to NetworkRigidBodyID
var sync_enabled: bool = false

# Enable/disable logging
var enable_logging: bool = false

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

# Ownership (for client-carried objects)
var owner_peer_id: int = 1  # Default: host is owner (peer 1)
var ownership_requested: bool = false

# Timer for returning ownership after drop
var drop_timer: float = 0.0
var drop_timer_duration: float = 1.0  # Return ownership after 1 second of not being carried


func _ready() -> void:
	parent_rigid_body = get_parent() as RigidBody3D
	if not parent_rigid_body:
		push_error("NetworkRigidSync: Parent must be a RigidBody3D")
		return
	
	await get_tree().process_frame
	
	# Find or create NetworkRigidBodyID component
	_find_network_id_component()
	
	# Wait for network_id to be set (host generates it and syncs to clients)
	if NetworkManager and NetworkManager.is_multiplayer() and NetworkManager.is_host():
		# Host generates network_id immediately
		if not network_id_component:
			network_id = await _generate_network_id()
		else:
			# Component already exists, wait for it to generate network_id
			var retries = 0
			while network_id == 0 and retries < 10:
				await get_tree().process_frame
				if network_id_component and network_id_component.has_method("get_network_id"):
					network_id = network_id_component.get_network_id()
				retries += 1
	else:
		# Client waits for network_id from host via RPC
		# Retry until network_id is received (up to 2 seconds)
		var retries = 0
		var max_retries = 40  # 40 * 0.05s = 2 seconds
		while network_id == 0 and retries < max_retries:
			await get_tree().create_timer(0.05).timeout
			_find_network_id_component()  # Re-check in case component was added
			if network_id_component and network_id_component.has_method("get_network_id"):
				network_id = network_id_component.get_network_id()
			retries += 1
	
	if network_id == 0:
		push_error("NetworkRigidSync: Failed to get network_id for %s after retries" % parent_rigid_body.name)
		# Try to register later when network_id becomes available
		_try_register_later()
	else:
		# Register immediately if network_id is available
		if NetworkRigidSyncManager:
			NetworkRigidSyncManager.register_rigid_body(self)
	
	# Find carryable component and connect to signal
	_find_carryable_component()
	if carryable_component and carryable_component.has_signal("carry_state_changed"):
		carryable_component.carry_state_changed.connect(_on_carry_state_changed)
	
	await get_tree().create_timer(0.5).timeout


## Try to register later when network_id becomes available
func _try_register_later() -> void:
	# Check periodically if network_id became available
	var check_timer = Timer.new()
	check_timer.wait_time = 0.1
	check_timer.one_shot = false
	check_timer.timeout.connect(_check_and_register)
	add_child(check_timer)
	check_timer.start()
	
	# Stop checking after 5 seconds
	await get_tree().create_timer(5.0).timeout
	check_timer.queue_free()


## Check if network_id is available and register
func _check_and_register() -> void:
	_find_network_id_component()
	if network_id_component and network_id_component.has_method("get_network_id"):
		var new_network_id = network_id_component.get_network_id()
		if new_network_id != 0 and network_id == 0:
			network_id = new_network_id
			if NetworkRigidSyncManager:
				NetworkRigidSyncManager.register_rigid_body(self)


## Check if local peer is the owner
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
	
	# Apply pending state on ANY peer that is NOT the owner (including host when client is owner)
	if has_pending_state and not is_local_owner():
		# Skip if this peer is locally carrying the object
		if not _is_carried_locally():
			_update_target_from_pending()
	
	# Interpolate/apply state on ANY peer that is NOT the owner (including host when client is owner)
	if has_target and not is_local_owner():
		# Skip if this peer is locally carrying the object
		if not _is_carried_locally():
			_interpolate_to_target(_delta)
	
	# Send state only if we are the owner
	if sync_enabled and NetworkManager and NetworkManager.is_multiplayer():
		var local_peer_id = NetworkManager.get_local_peer_id()
		
		# Debug: log why we're not sending (only once per second to avoid spam)
		if owner_peer_id == local_peer_id and network_id != 0:
			# We are owner - check conditions
			pass  # Will send below
		elif owner_peer_id == local_peer_id and network_id == 0:
			# Owner but no network_id - try to get it
			_find_network_id_component()
			if network_id_component and network_id_component.has_method("get_network_id"):
				network_id = network_id_component.get_network_id()
		
		if owner_peer_id == local_peer_id:
			# We are the owner - send states
			var is_carried = _is_carried_locally() if local_peer_id != 1 else _is_carried_on_host()
			
			# Debug: check if we should send but network_id is invalid
			if network_id == 0:
				# Try to get network_id from component
				_find_network_id_component()
				if network_id_component and network_id_component.has_method("get_network_id"):
					network_id = network_id_component.get_network_id()
			
			if network_id == 0:
				# Can't send without network_id
				return
			
			frames_since_last_send += 1
			var interval = send_interval_frames if not is_carried else 1  # Every frame if carried
			
			if frames_since_last_send >= interval:
				var current_state = _collect_state()
				if current_state.is_empty():
					# State collection failed
					return
				
				# If carried, always send (even if position didn't change)
				if last_sent_state.is_empty() or _state_changed(current_state) or is_carried:
					_send_state_update(current_state)
					last_sent_state = current_state.duplicate()
					frames_since_last_send = 0
		
		# Check if object should return ownership to host (timer-based after drop)
		if owner_peer_id != 1 and local_peer_id == owner_peer_id:
			if not _is_carried_locally():
				drop_timer += _delta
				if drop_timer >= drop_timer_duration:
					# Object not carried for drop_timer_duration - return ownership to host
					_return_ownership_to_host()
			else:
				# Object is being carried - reset timer
				drop_timer = 0.0


func _find_network_id_component() -> void:
	# Find existing NetworkRigidBodyID component
	for child in parent_rigid_body.get_children():
		if child.get_script() and child.get_script().resource_path.ends_with("network_rigid_body_id.gd"):
			network_id_component = child
			if network_id_component.has_method("get_network_id"):
				network_id = network_id_component.get_network_id()
			break


func _generate_network_id() -> int:
	# Only host generates network_id
	if not NetworkManager or not NetworkManager.is_multiplayer() or not NetworkManager.is_host():
		return 0
	
	# Re-check for NetworkRigidBodyID component (might have been added by NetworkRigidSyncManager)
	_find_network_id_component()
	
	# Check if NetworkRigidBodyID already exists and has network_id
	if network_id_component and network_id_component.has_method("get_network_id"):
		var existing_id = network_id_component.get_network_id()
		if existing_id != 0:
			return existing_id
	
	# Create NetworkRigidBodyID component if it doesn't exist
	if not network_id_component:
		var network_id_script = preload("res://addons/cogito/network/network_rigid_body_id.gd")
		network_id_component = network_id_script.new()
		network_id_component.name = "NetworkRigidBodyID"
		parent_rigid_body.add_child(network_id_component)
	
	# Wait for component to generate network_id (it generates in _ready)
	var retries = 0
	while retries < 20:  # Wait up to 1 second (20 * 0.05s)
		await get_tree().create_timer(0.05).timeout
		if network_id_component and network_id_component.has_method("get_network_id"):
			var generated_id = network_id_component.get_network_id()
			if generated_id != 0:
				return generated_id
		retries += 1
	
	return 0


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
		},
		"timestamp": Time.get_ticks_msec() / 1000.0
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
	
	# Validate network_id
	if network_id == 0:
		# Try to get network_id from component
		_find_network_id_component()
		if network_id_component and network_id_component.has_method("get_network_id"):
			network_id = network_id_component.get_network_id()
		
		if network_id == 0:
			# Can't send without network_id
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
		"angular_velocity": state.angular_velocity,
		"timestamp": state.get("timestamp", Time.get_ticks_msec() / 1000.0)
	}
	
	# Debug log (only for client-owners to avoid spam)
	var local_peer_id = NetworkManager.get_local_peer_id()
	if local_peer_id != 1 and owner_peer_id == local_peer_id:
		CogitoGlobals.debug_log(
			true,
			"NetworkRigidSync",
			"[CLIENT-OWNER] Sending state for network_id=%d, pos=%s" % [
				network_id,
				Vector3(state.position.x, state.position.y, state.position.z)
			]
		)
	
	NetworkManager.sync_rigid_body_state.rpc(state_data)


func _receive_state_update(state_data: Dictionary) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	var local_peer_id = NetworkManager.get_local_peer_id()
	
	# Diagnostic logging (use debug_log instead of print to avoid spam)
	# Only log if explicitly enabled via enable_logging flag
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidSync",
		"[Sync] peer=%d recv id=%d owner=%d local_owner=%s sync_enabled=%s" % [
			local_peer_id,
			network_id,
			owner_peer_id,
			str(is_local_owner()),
			str(sync_enabled)
		]
	)
	
	# Don't apply if we are the owner (we send states, not apply)
	if is_local_owner():
		return
	
	if not sync_enabled:
		return
	
	var received_network_id_raw = state_data.get("network_id", 0)
	# Ensure network_id is int (handle both int and String for compatibility)
	var received_network_id: int = 0
	if received_network_id_raw is int:
		received_network_id = received_network_id_raw
	elif received_network_id_raw is String:
		# Try to convert String to int (for backward compatibility)
		received_network_id = int(received_network_id_raw) if received_network_id_raw.is_valid_int() else 0
	
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
	
	# Apply interpolated transform
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, interpolated_transform)
	
	# Only apply velocities if body is not frozen (frozen bodies shouldn't have velocities applied)
	# Velocities are only meaningful for dynamic simulation, not for kinematic/frozen bodies
	if not parent_rigid_body.freeze:
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
		var local_peer_id = NetworkManager.get_local_peer_id()
		
		# Initialize ownership: host is default owner (if not already set)
		# Don't overwrite if ownership was already set (e.g., by _set_ownership)
		if owner_peer_id == 0:
			owner_peer_id = 1
		
		parent_rigid_body.set_multiplayer_authority(owner_peer_id)
		
		if owner_peer_id == local_peer_id:
			# We are owner - enable physics
			parent_rigid_body.freeze = false
		else:
			# We are not owner - freeze
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
	# Check if object is being carried locally (works for both host and clients)
	if not NetworkManager or not NetworkManager.is_multiplayer():
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
	
	if is_carried:
		if local_peer_id == 1:
			# Host - no ownership changes needed, unfreeze immediately
			parent_rigid_body.freeze = false
		else:
			# Client picked up object - request ownership
			# DO NOT unfreeze until ownership is granted (in _set_ownership)
			_request_ownership()
			# Keep frozen - will be unfrozen in _set_ownership when grant arrives
	else:
		# Object dropped - reset drop timer
		drop_timer = 0.0
		if local_peer_id == 1:
			# Host - no changes needed
			pass
		else:
			# Client dropped object - ownership will return to host after timer
			# Timer is checked in _physics_process
			pass


func _request_ownership() -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	var local_peer_id = NetworkManager.get_local_peer_id()
	if local_peer_id == 1:  # Host doesn't request
		return
	
	if ownership_requested:
		return  # Already requested
	
	ownership_requested = true
	NetworkManager.request_rigid_body_ownership.rpc_id(1, network_id)  # Request from host


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
		# We became owner - enable physics simulation
		parent_rigid_body.freeze = false  # Enable physics
		
		# Ensure network_id is set (might not be set yet on client)
		if network_id == 0:
			_find_network_id_component()
			if network_id_component and network_id_component.has_method("get_network_id"):
				network_id = network_id_component.get_network_id()
			
			if network_id == 0:
				push_error("NetworkRigidSync: Became owner but network_id is 0 for %s" % parent_rigid_body.name)
				return
		
		# Ensure component is registered (might not be registered yet)
		if network_id != 0 and NetworkRigidSyncManager:
			var existing = NetworkRigidSyncManager.get_rigid_body(network_id)
			if existing != self:
				# Not registered yet, register now
				NetworkRigidSyncManager.register_rigid_body(self)
		
		# Ensure sync is enabled when we become owner (call set_sync_enabled to ensure proper setup)
		if not sync_enabled:
			set_sync_enabled(true)
		else:
			# Even if already enabled, ensure ownership is set correctly
			parent_rigid_body.set_multiplayer_authority(peer_id)
			if owner_peer_id == local_peer_id:
				parent_rigid_body.freeze = false
		
		# Debug log
		CogitoGlobals.debug_log(
			true,
			"NetworkRigidSync",
			"[CLIENT-OWNER] Became owner for network_id=%d, sync_enabled=%s, freeze=%s, registered=%s" % [
				network_id,
				sync_enabled,
				parent_rigid_body.freeze,
				NetworkRigidSyncManager.get_rigid_body(network_id) != null if NetworkRigidSyncManager else false
			]
		)
	else:
		# Someone else became owner - we are not owner
		# Freeze and use kinematic mode to apply states
		parent_rigid_body.freeze = true
		parent_rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func _return_ownership_to_host() -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	var local_peer_id = NetworkManager.get_local_peer_id()
	if local_peer_id != owner_peer_id:
		return  # Not our ownership to return
	
	# Notify host that we're returning ownership
	NetworkManager.return_rigid_body_ownership.rpc_id(1, network_id)
	
	# Reset ownership locally (host will confirm via grant)
	owner_peer_id = 1
	ownership_requested = false
	drop_timer = 0.0
	
	# Freeze until host confirms
	parent_rigid_body.freeze = true
	parent_rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func _exit_tree() -> void:
	if NetworkRigidSyncManager and network_id != 0:
		NetworkRigidSyncManager.unregister_rigid_body(network_id)
