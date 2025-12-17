extends Node
## Manager for handling multiple players in the system.
## Replaces direct references to CogitoSceneManager._current_player_node
## Note: This is an autoload singleton, not a class_name

## Dictionary of registered players: player_id -> player_node
var _players: Dictionary = {}

## ID of the local player (the player controlled by this client)
var _local_player_id: int = -1

## Counter for generating unique player IDs
var _next_player_id: int = 1

## Enable/disable logging
var enable_logging: bool = false


func _ready() -> void:
	CogitoGlobals.debug_log(
		true, "PlayerManager", "Player Manager initialized and ready."
	)


## Register a player in the system
## Returns the assigned player_id
func register_player(player_node: Node, is_local: bool = false) -> int:
	if not player_node:
		push_error("PlayerManager: Cannot register null player node")
		return -1
	
	# Generate or use existing player ID
	var player_id: int = _next_player_id
	_next_player_id += 1
	
	_players[player_id] = player_node
	
	if is_local:
		_local_player_id = player_id
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerManager",
			"Local player registered with ID: %d" % player_id
		)
	else:
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerManager",
			"Player registered with ID: %d" % player_id
		)
	
	# Emit event through Event Bus
	NetworkEventBus.emit_player_registered(player_id, player_node)
	
	return player_id


## Unregister a player from the system
func unregister_player(player_id: int) -> void:
	if not _players.has(player_id):
		CogitoGlobals.debug_log(
			true,
			"PlayerManager",
			"Attempted to unregister non-existent player ID: %d" % player_id
		)
		return
	
	var player_node = _players[player_id]
	_players.erase(player_id)
	
	if _local_player_id == player_id:
		_local_player_id = -1
	
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerManager",
		"Player unregistered with ID: %d" % player_id
	)
	
	# Emit event through Event Bus
	NetworkEventBus.emit_player_unregistered(player_id)


## Get a player by ID
func get_player(player_id: int) -> Node:
	return _players.get(player_id)


## Get the local player node
func get_local_player() -> Node:
	if _local_player_id == -1:
		return null
	return _players.get(_local_player_id)


## Get the local player ID
func get_local_player_id() -> int:
	return _local_player_id


## Check if a player is registered
func has_player(player_id: int) -> bool:
	return _players.has(player_id)


## Check if local player is registered
func has_local_player() -> bool:
	return _local_player_id != -1 and _players.has(_local_player_id)


## Get all registered player IDs
func get_all_player_ids() -> Array:
	return _players.keys()


## Get all registered players
func get_all_players() -> Array:
	return _players.values()


## Get player count
func get_player_count() -> int:
	return _players.size()


## Clear all registered players (useful for scene transitions)
func clear_all_players() -> void:
	var player_ids = _players.keys().duplicate()
	for player_id in player_ids:
		unregister_player(player_id)
	
	_players.clear()
	_local_player_id = -1
	_next_player_id = 1
	
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerManager",
		"All players cleared"
	)


## Helper function for backward compatibility
## Returns the local player, or falls back to CogitoSceneManager._current_player_node
func get_current_player() -> Node:
	var local_player = get_local_player()
	if local_player:
		return local_player
	
	# Fallback for backward compatibility
	if CogitoSceneManager and CogitoSceneManager.has_method("get") and CogitoSceneManager.get("_current_player_node"):
		return CogitoSceneManager._current_player_node
	
	return null

