extends Node
## Manager for handling multiple players in the system.
## Replaces direct references to CogitoSceneManager._current_player_node
## Note: This is an autoload singleton, not a class_name

## Dictionary of registered players: player_id -> player_node
var _players: Dictionary = {}

## Dictionary mapping player_id -> peer_id (for multiplayer)
var _player_peer_ids: Dictionary = {}

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
	
	# Store peer_id for multiplayer
	if NetworkManager and NetworkManager.is_multiplayer():
		var peer_id = NetworkManager.get_local_peer_id() if is_local else -1
		# For remote players, we'll set peer_id when we receive spawn info
		# For now, store local peer_id for local player
		if is_local:
			_player_peer_ids[player_id] = peer_id
		else:
			# Will be set when we receive spawn info via RPC
			_player_peer_ids[player_id] = -1
	
	if is_local:
		_local_player_id = player_id
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerManager",
			"Local player registered with ID: %d (peer_id: %d)" % [player_id, _player_peer_ids.get(player_id, -1)]
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
	_player_peer_ids.erase(player_id)
	
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
	if _local_player_id != -1:
		return _local_player_id
	
	# Try to get from NetworkManager if available
	if NetworkManager and NetworkManager.is_multiplayer():
		return NetworkManager.get_local_peer_id()
	
	return -1


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
	_player_peer_ids.clear()
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


## Get player by peer ID (for multiplayer)
func get_player_by_peer_id(peer_id: int) -> Node:
	# Search through all players using stored peer_id mapping
	for player_id in _players.keys():
		if _player_peer_ids.has(player_id) and _player_peer_ids[player_id] == peer_id:
			CogitoGlobals.debug_log(
				enable_logging,
				"PlayerManager",
				"Found player_id %d for peer_id %d via mapping" % [player_id, peer_id]
			)
			return _players[player_id]
	
	# Fallback: check local player
	# NOTE: This should only match if peer_id matches the local player's peer_id
	# NOT if peer_id == 1 on a client (that would be the host)
	if _local_player_id != -1:
		var local_peer_id = -1
		if NetworkManager and NetworkManager.is_multiplayer():
			local_peer_id = NetworkManager.get_local_peer_id()
		
		# Only return local player if peer_id matches local peer_id
		# This prevents clients from matching peer_id=1 (host) with their local player
		if local_peer_id == peer_id and local_peer_id != -1:
			CogitoGlobals.debug_log(
				enable_logging,
				"PlayerManager",
				"Found local player (player_id %d) for peer_id %d" % [_local_player_id, peer_id]
			)
			return _players[_local_player_id]
	
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerManager",
		"No player found for peer_id %d (local_player_id=%d, total_players=%d)" % [peer_id, _local_player_id, _players.size()]
	)
	return null


## Get peer ID for a player ID
func get_player_peer_id(player_id: int) -> int:
	if _player_peer_ids.has(player_id):
		return _player_peer_ids[player_id]
	return -1


## Set peer ID for a player (called when player spawns via RPC)
func set_player_peer_id(player_id: int, peer_id: int) -> void:
	if _players.has(player_id):
		_player_peer_ids[player_id] = peer_id
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerManager",
			"Set peer_id %d for player_id %d" % [peer_id, player_id]
		)


## Check if player exists by peer ID
func has_player_by_peer_id(peer_id: int) -> bool:
	return get_player_by_peer_id(peer_id) != null


## Get player ID for a player node
func get_player_id(player_node: Node) -> int:
	for player_id in _players.keys():
		if _players[player_id] == player_node:
			return player_id
	return -1
