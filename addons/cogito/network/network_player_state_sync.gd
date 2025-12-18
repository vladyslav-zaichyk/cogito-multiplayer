extends Node
## Network Player State Synchronization Component
## Handles player state synchronization for multiplayer (crouch, sprint, jump, etc.)
## Attach this to a CharacterBody3D (like CogitoPlayer)

## Enable/disable logging
var enable_logging: bool = false

## Sync frequency (how often to send state updates)
@export var sync_rate: float = 10.0  # Updates per second

## Is this the local player?
var is_local: bool = false

## Peer ID of this player
var peer_id: int = -1

## Reference to the parent CharacterBody3D (CogitoPlayer)
var parent_body: CharacterBody3D = null

## Reference to PlayerInteractionComponent (if exists)
var interaction_component: Node = null

## Last synced state values
var last_state: Dictionary = {}

## Timer for sync rate
var sync_timer: float = 0.0

## States to track
var tracked_states: Array[String] = [
	"is_crouching",
	"is_sprinting",
	"is_walking",
	"is_jumping",
	"is_in_air",
	"is_sitting",
	"is_dead",
	"is_free_looking",
	"on_ladder",
	"try_crouch",
	"is_carrying",
	"is_wielding"
]


func _ready() -> void:
	parent_body = get_parent() as CharacterBody3D
	if not parent_body:
		push_error("NetworkPlayerStateSync: Parent must be a CharacterBody3D")
		return
	
	# Wait a frame for player to be initialized
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
		
		# Get peer_id
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
	
	# Find PlayerInteractionComponent
	if parent_body.has_method("get_node_or_null"):
		interaction_component = parent_body.get_node_or_null("PlayerInteractionComponent")
	
	# Initialize last_state with current values
	_update_last_state()
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkPlayerStateSync",
		"Initialized for %s player (peer_id: %d)" % ["local" if is_local else "remote", peer_id]
	)


func _process(delta: float) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	if not is_local:
		return  # Remote players receive updates via RPC
	
	if not is_inside_tree() or not multiplayer or not multiplayer.has_multiplayer_peer():
		return
	
	# Update sync timer
	sync_timer += delta
	var sync_interval = 1.0 / sync_rate
	
	if sync_timer >= sync_interval:
		sync_timer = 0.0
		_check_and_sync_state()


## Check if state changed and sync if needed
func _check_and_sync_state() -> void:
	var current_state = _get_current_state()
	
	# Check if any state changed
	var state_changed = false
	for state_name in tracked_states:
		var current_value = current_state.get(state_name, false)
		var last_value = last_state.get(state_name, false)
		
		if current_value != last_value:
			state_changed = true
			break
	
	if state_changed:
		_send_state_update(current_state)
		last_state = current_state.duplicate()


## Get current state values
func _get_current_state() -> Dictionary:
	var state: Dictionary = {}
	
	if not parent_body:
		return state
	
	# Get states from CogitoPlayer
	for state_name in tracked_states:
		if state_name == "is_carrying":
			# is_carrying is a getter that returns carried_object != null
			if interaction_component:
				# Try to access the property directly (it's a getter)
				var value = interaction_component.get("is_carrying")
				state[state_name] = value if value != null else false
			else:
				state[state_name] = false
		elif state_name == "is_wielding":
			# is_wielding is a getter
			if interaction_component:
				# Try to access the property directly (it's a getter)
				var value = interaction_component.get("is_wielding")
				state[state_name] = value if value != null else false
			else:
				state[state_name] = false
		else:
			# These are from CogitoPlayer
			if parent_body.has_method("get"):
				var value = parent_body.get(state_name)
				state[state_name] = value if value != null else false
			else:
				state[state_name] = false
	
	return state


## Update last_state with current values
func _update_last_state() -> void:
	last_state = _get_current_state()


## Send state update via RPC
func _send_state_update(state: Dictionary) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	if not is_inside_tree() or not multiplayer or not multiplayer.has_multiplayer_peer():
		return
	
	# Get player_id
	var player_id = -1
	if PlayerManager:
		player_id = PlayerManager.get_player_id(parent_body)
	
	if player_id == -1:
		return
	
	# Send RPC
	NetworkManager.sync_player_state.rpc(peer_id, state)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkPlayerStateSync",
		"Sent state update: %s" % str(state)
	)


## Receive state update from network (called via RPC)
func _receive_state_update(state: Dictionary) -> void:
	if is_local:
		return  # Don't update local player's state from network
	
	if not parent_body:
		return
	
	# Update states
	for state_name in tracked_states:
		if not state.has(state_name):
			continue
		
		var new_value = state[state_name]
		
		if state_name == "is_carrying":
			# is_carrying is a getter, we can't set it directly
			# Instead, we would need to set carried_object, but that's complex
			# For now, we'll just track it for information
			# The actual carrying state will be synced through interactions
			pass
		elif state_name == "is_wielding":
			# is_wielding is a getter, we can't set it directly
			# The actual wielding state will be synced through inventory/equipment
			pass
		else:
			# These are from CogitoPlayer
			if parent_body.has_method("set"):
				# Only set if the value actually changed to avoid unnecessary updates
				var current_value = parent_body.get(state_name) if parent_body.has_method("get") else null
				if current_value != new_value:
					parent_body.set(state_name, new_value)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkPlayerStateSync",
		"Received state update: %s" % str(state)
	)
