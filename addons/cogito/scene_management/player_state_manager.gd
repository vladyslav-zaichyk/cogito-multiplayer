extends Node
## Player State Manager for handling per-player state operations.
## Provides abstraction for managing individual player states in multiplayer.
## Note: This is an autoload singleton, not a class_name

## Enable/disable logging
var enable_logging: bool = false

## Dictionary to store player-specific state data
## Key: player_id, Value: Dictionary with state info
var _player_states: Dictionary = {}


func _ready() -> void:
	CogitoGlobals.debug_log(
		true, "PlayerStateManager", "Player State Manager initialized and ready."
	)
	
	# Connect to player registration events
	if NetworkEventBus:
		NetworkEventBus.player_registered.connect(_on_player_registered)
		NetworkEventBus.player_unregistered.connect(_on_player_unregistered)


## Save state for a specific player
func save_player_state(player_id: int, player: Node, slot: String) -> void:
	if not player:
		push_error("PlayerStateManager: Cannot save state for null player")
		return
	
	# Use SaveManager for actual save operation
	if SaveManager:
		SaveManager.save_player_state(player, slot, player_id)
	
	# Track that we have state for this player
	if not _player_states.has(player_id):
		_player_states[player_id] = {}
	
	_player_states[player_id]["slot"] = slot
	_player_states[player_id]["last_saved"] = Time.get_unix_time_from_system()
	
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerStateManager",
		"Saved state for player %d in slot %s" % [player_id, slot]
	)


## Load state for a specific player
func load_player_state(player_id: int, player: Node, slot: String) -> void:
	if not player:
		push_error("PlayerStateManager: Cannot load state for null player")
		return
	
	# Use SaveManager for actual load operation
	if SaveManager:
		SaveManager.load_player_state(player, slot, player_id)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerStateManager",
		"Loaded state for player %d from slot %s" % [player_id, slot]
	)


## Check if player has saved state
func has_player_state(player_id: int, slot: String) -> bool:
	if not _player_states.has(player_id):
		return false
	
	if SaveManager:
		var player_state = SaveManager.get_existing_player_state(slot)
		return player_state != null and player_state.state_exists(slot)
	
	return false


## Get all player IDs that have saved state
func get_players_with_state() -> Array:
	return _player_states.keys()


## Clear state for a specific player
func clear_player_state(player_id: int) -> void:
	if _player_states.has(player_id):
		_player_states.erase(player_id)
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerStateManager",
			"Cleared state tracking for player %d" % player_id
		)


## Clear all player states
func clear_all_player_states() -> void:
	_player_states.clear()
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerStateManager",
		"Cleared all player state tracking"
	)


## Callback when a player is registered
func _on_player_registered(player_id: int, player_node: Node) -> void:
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerStateManager",
		"Player %d registered, initializing state tracking" % player_id
	)
	
	if not _player_states.has(player_id):
		_player_states[player_id] = {}


## Callback when a player is unregistered
func _on_player_unregistered(player_id: int) -> void:
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerStateManager",
		"Player %d unregistered, clearing state tracking" % player_id
	)
	
	clear_player_state(player_id)

