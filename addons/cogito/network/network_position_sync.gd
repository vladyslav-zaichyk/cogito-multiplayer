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
		var authority = multiplayer.get_authority(parent_body.get_path())
		is_local = (authority == local_peer_id)
		peer_id = authority if authority > 0 else local_peer_id
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
	
	# Remote player: interpolate to target position
	else:
		_interpolate_position(delta)


## Send position update (local player only)
func _send_position_update() -> void:
	if not parent_body:
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
	
	# Send RPC to all peers
	if multiplayer:
		_sync_position_rpc.rpc(current_position)


## RPC: Sync position to all clients
@rpc("any_peer", "call_local", "unreliable")
func _sync_position_rpc(position: Vector3) -> void:
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


## Interpolate position for remote players
func _interpolate_position(delta: float) -> void:
	if not parent_body:
		return
	
	var current_position = parent_body.global_position
	
	# Interpolate towards target position
	if current_position.distance_to(target_position) > position_threshold:
		parent_body.global_position = current_position.lerp(
			target_position,
			interpolation_speed * delta
		)
	else:
		# Close enough, snap to target
		parent_body.global_position = target_position


## Force immediate position sync (useful for teleportation, respawn, etc.)
func force_sync_position(position: Vector3) -> void:
	if not parent_body:
		return
	
	parent_body.global_position = position
	last_synced_position = position
	target_position = position
	
	if is_local and multiplayer:
		_sync_position_rpc.rpc(position)

