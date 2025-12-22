extends Node
## Network Rotation Synchronization Component
## Handles rotation synchronization for multiplayer players
## Attach this to a CharacterBody3D (like CogitoPlayer)

## Enable/disable logging
var enable_logging: bool = false  # Disabled by default

## Sync frequency (how often to send rotation updates)
@export var sync_rate: float = 20.0  # Updates per second

## Rotation threshold (only sync if rotation changed by this amount in degrees)
@export var rotation_threshold: float = 0.5

## Interpolation speed for remote players
@export var interpolation_speed: float = 15.0

## Is this the local player?
var is_local: bool = false

## Peer ID of this player
var peer_id: int = -1

## Last synced body rotation
var last_synced_body_rotation: float = 0.0

## Last synced neck rotation
var last_synced_neck_rotation: float = 0.0

## Last synced head rotation
var last_synced_head_rotation: float = 0.0

## Timer for sync rate
var sync_timer: float = 0.0

## Target rotations for interpolation (remote players)
var target_body_rotation: float = 0.0
var target_neck_rotation: float = 0.0
var target_head_rotation: float = 0.0

## Reference to the parent CharacterBody3D
var parent_body: CharacterBody3D = null

## References to body, neck, and head nodes
var body_node: Node3D = null
var neck_node: Node3D = null
var head_node: Node3D = null


func _ready() -> void:
	parent_body = get_parent() as CharacterBody3D
	if not parent_body:
		push_error("NetworkRotationSync: Parent must be a CharacterBody3D")
		return
	
	# Wait a frame for nodes to be ready
	await get_tree().process_frame
	
	# Find body, neck, and head nodes
	# body, neck, head are @onready vars in CogitoPlayer
	# Try to get body node - first try direct property access, then get_node
	if "body" in parent_body and parent_body.body != null:
		body_node = parent_body.body
	else:
		body_node = parent_body.get_node_or_null("Body")
	
	if body_node:
		# Try to get neck node
		if "neck" in body_node and body_node.neck != null:
			neck_node = body_node.neck
		else:
			neck_node = body_node.get_node_or_null("Neck")
		
		# Try to get head node
		if neck_node:
			if "head" in neck_node and neck_node.head != null:
				head_node = neck_node.head
			else:
				head_node = neck_node.get_node_or_null("Head")
		
		# Debug: log what we found
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkRotationSync",
			"Found nodes: body=%s, neck=%s, head=%s" % [
				"found" if body_node else "null",
				"found" if neck_node else "null",
				"found" if head_node else "null"
			]
		)
	
	if not body_node:
		push_error("NetworkRotationSync: Could not find body node")
		return
	
	if not head_node:
		# Head node is optional - we can still sync body rotation
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkRotationSync",
			"Head node not found, will only sync body rotation"
		)
	
	# Wait a frame for authority to be set
	await get_tree().process_frame
	
	# Determine if this is local player
	if NetworkManager and NetworkManager.is_multiplayer() and multiplayer:
		var local_peer_id = NetworkManager.get_local_peer_id()
		
		# Check if parent has is_local_player property (CogitoPlayer)
		if parent_body.has_method("get") and parent_body.get("is_local_player") != null:
			is_local = parent_body.is_local_player
		elif PlayerManager:
			# Check if this player is registered as local player
			var player_id = PlayerManager.get_player_id(parent_body)
			is_local = (PlayerManager.has_local_player() and PlayerManager.get_local_player_id() == player_id)
		else:
			# Fallback: assume local if we're the host
			is_local = NetworkManager.is_host()
		
		# Get peer_id - use local_peer_id for local player, or get from PlayerManager for remote
		if is_local:
			peer_id = local_peer_id
		else:
			# For remote players, get peer_id from PlayerManager
			if PlayerManager:
				var player_id = PlayerManager.get_player_id(parent_body)
				if player_id != -1:
					peer_id = PlayerManager.get_player_peer_id(player_id)
					if peer_id == -1:
						# Fallback: try to get from parent if it has peer_id
						if parent_body.has_method("get") and parent_body.get("peer_id") != null:
							peer_id = parent_body.peer_id
						else:
							peer_id = local_peer_id  # Temporary fallback
				else:
					peer_id = local_peer_id  # Temporary fallback
			else:
				peer_id = local_peer_id  # Temporary fallback
	else:
		# Single-player: always local
		is_local = true
		peer_id = 1
	
	# Initialize last synced rotations
	if body_node:
		last_synced_body_rotation = rad_to_deg(body_node.rotation.y)
		target_body_rotation = last_synced_body_rotation
	if neck_node:
		last_synced_neck_rotation = rad_to_deg(neck_node.rotation.y)
		target_neck_rotation = last_synced_neck_rotation
	if head_node:
		last_synced_head_rotation = rad_to_deg(head_node.rotation.x)
		target_head_rotation = last_synced_head_rotation
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRotationSync",
		"Initialized for %s player (peer_id: %d)" % ["local" if is_local else "remote", peer_id]
	)


func _process(delta: float) -> void:
	# Only send updates in _process (not physics-critical)
	if not parent_body or not body_node:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# Local player: send rotation updates
	if is_local:
		sync_timer += delta
		var sync_interval = 1.0 / sync_rate
		
		if sync_timer >= sync_interval:
			sync_timer = 0.0
			_send_rotation_update()


func _physics_process(_delta: float) -> void:
	# Remote player: apply rotation in _physics_process (for consistency with position sync)
	if not parent_body or not body_node:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# Remote player: interpolate to target rotation
	if not is_local:
		_interpolate_rotation(_delta)


## Send rotation update (local player only)
func _send_rotation_update() -> void:
	if not body_node:
		return
	
	# Don't send RPC if we're not in the scene tree yet
	if not is_inside_tree():
		return
	
	# Don't send RPC if multiplayer is not ready
	if not multiplayer or not multiplayer.has_multiplayer_peer():
		return
	
	var current_body_rotation = rad_to_deg(body_node.rotation.y)
	var current_neck_rotation = 0.0
	if neck_node:
		current_neck_rotation = rad_to_deg(neck_node.rotation.y)
	var current_head_rotation = 0.0
	if head_node:
		current_head_rotation = rad_to_deg(head_node.rotation.x)
	
	# Only send if rotation changed significantly
	var body_diff = abs(current_body_rotation - last_synced_body_rotation)
	var neck_diff = 0.0
	if neck_node:
		neck_diff = abs(current_neck_rotation - last_synced_neck_rotation)
	var head_diff = 0.0
	if head_node:
		head_diff = abs(current_head_rotation - last_synced_head_rotation)
	
	# Normalize angles for comparison (handle wrap-around)
	if body_diff > 180:
		body_diff = 360 - body_diff
	if neck_node and neck_diff > 180:
		neck_diff = 360 - neck_diff
	if head_node and head_diff > 180:
		head_diff = 360 - head_diff
	
	# Send if ANY rotation changed significantly (use OR, not AND)
	var should_send = false
	if body_diff >= rotation_threshold:
		should_send = true
	if neck_node and neck_diff >= rotation_threshold:
		should_send = true
	if head_node and head_diff >= rotation_threshold:
		should_send = true
	
	if not should_send:
		return
	
	last_synced_body_rotation = current_body_rotation
	if neck_node:
		last_synced_neck_rotation = current_neck_rotation
	if head_node:
		last_synced_head_rotation = current_head_rotation
	
	# Emit through NetworkEventBus
	if NetworkEventBus and head_node:
		var position = parent_body.global_position
		var rotation = Vector3(head_node.rotation.x, body_node.rotation.y, 0)
		NetworkEventBus.player_moved.emit(peer_id, position, rotation)
	
	# Send RPC through NetworkManager (autoload singleton, always available)
	if NetworkManager and NetworkManager.is_multiplayer():
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkRotationSync",
			"[LOCAL] Sending rotation: body=%.2f, neck=%.2f, head=%.2f" % [
				current_body_rotation,
				current_neck_rotation,
				current_head_rotation
			]
		)
		NetworkManager.sync_player_rotation.rpc(peer_id, current_body_rotation, current_neck_rotation, current_head_rotation)


## Receive rotation update (called from NetworkManager RPC)
func _receive_rotation_update(body_rotation: float, neck_rotation: float, head_rotation: float) -> void:
	# Only process if this is a remote player
	if is_local:
		return
	
	# Update target rotations for interpolation
	target_body_rotation = body_rotation
	target_neck_rotation = neck_rotation
	target_head_rotation = head_rotation
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRotationSync",
		"Received rotation update for peer %d: body=%.2f, neck=%.2f, head=%.2f" % [
			peer_id, 
			body_rotation, 
			neck_rotation, 
			head_rotation
		]
	)


## Interpolate rotation for remote players
func _interpolate_rotation(delta: float) -> void:
	if not body_node:
		return
	
	var current_body_rotation = rad_to_deg(body_node.rotation.y)
	var current_neck_rotation = 0.0
	if neck_node:
		current_neck_rotation = rad_to_deg(neck_node.rotation.y)
	var current_head_rotation = 0.0
	if head_node:
		current_head_rotation = rad_to_deg(head_node.rotation.x)
	
	# Normalize angles for interpolation (handle wrap-around)
	var body_diff = target_body_rotation - current_body_rotation
	if body_diff > 180:
		body_diff -= 360
	elif body_diff < -180:
		body_diff += 360
	
	# Interpolate body rotation (Y-axis)
	if abs(body_diff) > rotation_threshold:
		var new_body_rotation = current_body_rotation + body_diff * interpolation_speed * delta
		body_node.rotation.y = deg_to_rad(new_body_rotation)
	else:
		body_node.rotation.y = deg_to_rad(target_body_rotation)
	
	# Interpolate neck rotation (Y-axis) - if neck node exists
	if neck_node:
		var neck_diff = target_neck_rotation - current_neck_rotation
		if neck_diff > 180:
			neck_diff -= 360
		elif neck_diff < -180:
			neck_diff += 360
		
		if abs(neck_diff) > rotation_threshold:
			var new_neck_rotation = current_neck_rotation + neck_diff * interpolation_speed * delta
			neck_node.rotation.y = deg_to_rad(new_neck_rotation)
		else:
			neck_node.rotation.y = deg_to_rad(target_neck_rotation)
	
	# Interpolate head rotation (X-axis) - if head node exists
	if head_node:
		var head_diff = target_head_rotation - current_head_rotation
		if head_diff > 180:
			head_diff -= 360
		elif head_diff < -180:
			head_diff += 360
		
		if abs(head_diff) > rotation_threshold:
			var new_head_rotation = current_head_rotation + head_diff * interpolation_speed * delta
			head_node.rotation.x = deg_to_rad(new_head_rotation)
		else:
			head_node.rotation.x = deg_to_rad(target_head_rotation)


## Force immediate rotation sync (useful for respawn, etc.)
func force_sync_rotation(body_rotation: float, neck_rotation: float, head_rotation: float) -> void:
	if not body_node:
		return
	
	body_node.rotation.y = deg_to_rad(body_rotation)
	if neck_node:
		neck_node.rotation.y = deg_to_rad(neck_rotation)
	if head_node:
		head_node.rotation.x = deg_to_rad(head_rotation)
	
	last_synced_body_rotation = body_rotation
	if neck_node:
		last_synced_neck_rotation = neck_rotation
	if head_node:
		last_synced_head_rotation = head_rotation
	target_body_rotation = body_rotation
	if neck_node:
		target_neck_rotation = neck_rotation
	if head_node:
		target_head_rotation = head_rotation
	
	if is_local and NetworkManager and NetworkManager.is_multiplayer():
		NetworkManager.sync_player_rotation.rpc(peer_id, body_rotation, neck_rotation, head_rotation)
