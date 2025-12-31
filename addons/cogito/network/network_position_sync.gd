extends Node
## Network Position Synchronization Component
## Handles position synchronization for multiplayer players
## Attach this to a CharacterBody3D (like CogitoPlayer)

## Enable/disable logging
var enable_logging: bool = false

## Sync frequency (how often to send position updates)
@export var sync_rate: float = 20.0  # Updates per second

## Position threshold (only sync if position changed by this amount)
@export var position_threshold: float = 0.01

## Interpolation speed for remote players
@export var interpolation_speed: float = 15.0

## Is this the local player?
var is_local: bool = false

## Peer ID of this player
var peer_id: int = -1

## Last synced position
var last_synced_position: Vector3 = Vector3.ZERO

## Timer for sync rate
var sync_timer: float = 0.0

## Target position for interpolation (remote players)
var target_position: Vector3 = Vector3.ZERO

## Last received position timestamp
var last_position_time: float = 0.0

## Reference to the parent CharacterBody3D
var parent_body: CharacterBody3D = null


func _ready() -> void:
	parent_body = get_parent() as CharacterBody3D
	if not parent_body:
		push_error("NetworkPositionSync: Parent must be a CharacterBody3D")
		return
	
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
	
	# Initialize last synced position
	last_synced_position = parent_body.global_position
	target_position = parent_body.global_position
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkPositionSync",
		"Initialized for %s player (peer_id: %d)" % ["local" if is_local else "remote", peer_id]
	)


func _process(delta: float) -> void:
	# Only send updates in _process (not physics-critical)
	if not parent_body:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# Local player: send position updates
	if is_local:
		sync_timer += delta
		var sync_interval = 1.0 / sync_rate
		
		if sync_timer >= sync_interval:
			sync_timer = 0.0
			_send_position_update()


func _physics_process(_delta: float) -> void:
	# Remote player: apply position in _physics_process (physics-critical)
	if not parent_body:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# Remote player: interpolate to target position using velocity + move_and_slide
	if not is_local:
		_apply_remote_position(_delta)


## Send position update (local player only)
func _send_position_update() -> void:
	if not parent_body:
		return
	
	# Don't send RPC if we're not in the scene tree yet
	if not is_inside_tree():
		return
	
	# Don't send RPC if multiplayer is not ready
	if not multiplayer or not multiplayer.has_multiplayer_peer():
		return
	
	var current_position = parent_body.global_position
	
	# Only send if position changed significantly
	if current_position.distance_to(last_synced_position) < position_threshold:
		return
	
	last_synced_position = current_position
	
	# Emit through NetworkEventBus
	if NetworkEventBus:
		var rotation = Vector3.ZERO
		if parent_body.has_method("get") and parent_body.get("body"):
			var body_node = parent_body.body
			if body_node is Node3D:
				rotation = body_node.global_rotation
		
		NetworkEventBus.player_moved.emit(peer_id, current_position, rotation)
	
	# Send RPC through NetworkManager (autoload singleton, always available)
	if NetworkManager and NetworkManager.is_multiplayer():
		NetworkManager.sync_player_position.rpc(current_position)


## Receive position update (called from NetworkManager RPC)
func _receive_position_update(position: Vector3) -> void:
	# Only process if this is a remote player
	if is_local:
		return
	
	# Update target position for interpolation
	target_position = position
	last_position_time = Time.get_ticks_msec() / 1000.0
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkPositionSync",
		"Received position update for peer %d: %s" % [peer_id, position]
	)


## Apply remote position in _physics_process using velocity + move_and_slide
## This is the correct way to move CharacterBody3D (respects collisions)
func _apply_remote_position(_delta: float) -> void:
	if not parent_body:
		return
	
	var current_position = parent_body.global_position
	var distance = current_position.distance_to(target_position)
	
	# If very close, snap to target
	if distance < position_threshold:
		parent_body.global_position = target_position
		parent_body.velocity = Vector3.ZERO
		return
	
	# Calculate velocity needed to reach target
	# Use interpolation speed to control how fast we move
	var direction = (target_position - current_position).normalized()
	var speed = interpolation_speed * distance  # Speed based on distance
	
	# Set velocity and let move_and_slide handle the movement
	# This respects collisions and physics interactions
	parent_body.velocity = direction * speed
	
	# Move using move_and_slide (this is the correct way for CharacterBody3D)
	parent_body.move_and_slide()


## Force immediate position sync (useful for teleportation, respawn, etc.)
func force_sync_position(position: Vector3) -> void:
	if not parent_body:
		return
	
	parent_body.global_position = position
	last_synced_position = position
	target_position = position
	
	if is_local and NetworkManager and NetworkManager.is_multiplayer():
		NetworkManager.sync_player_position.rpc(position)
