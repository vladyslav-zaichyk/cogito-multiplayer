extends Node
## Manager for handling multiple players in the system.
## Replaces direct references to CogitoSceneManager._current_player_node
## Note: This is an autoload singleton, not a class_name

const PlayerData = preload("res://addons/cogito/network/player_data.gd")

## Dictionary of registered players: player_id -> player_node
var _players: Dictionary = {}

## Dictionary mapping player_id -> peer_id (for multiplayer)
var _player_peer_ids: Dictionary = {}

## Dictionary mapping player_id -> player_name (for multiplayer)
var _player_names: Dictionary = {}

## Dictionary mapping peer_id -> player_name (for storing names before player registration)
var _peer_names: Dictionary = {}

## Dictionary mapping peer_id -> PlayerData (centralized player data storage)
var _player_data: Dictionary = {}  # peer_id -> PlayerData

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
	
	# Connect to network events for player data synchronization
	if NetworkEventBus:
		NetworkEventBus.network_connected.connect(_on_network_connected)
		NetworkEventBus.network_disconnected.connect(_on_network_disconnected)


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
	
	# Initialize player name (will be set via set_player_name)
	if not _player_names.has(player_id):
		# Check if we have PlayerData for this peer_id (most reliable)
		var stored_name = null
		if NetworkManager and NetworkManager.is_multiplayer():
			var peer_id = _player_peer_ids.get(player_id, -1)
			if peer_id == -1 and is_local:
				peer_id = NetworkManager.get_local_peer_id()
			
			# First check PlayerData
			if peer_id != -1 and _player_data.has(peer_id):
				var player_data = _player_data[peer_id] as PlayerData
				if player_data and player_data.player_name != "" and not player_data.player_name.begins_with("Player "):
					stored_name = player_data.player_name
					CogitoGlobals.debug_log(
						true,  # Always log this
						"PlayerManager",
						"Restored name from PlayerData for player_id %d (peer_id %d): %s" % [player_id, peer_id, stored_name]
					)
			
			# Fallback to _peer_names
			if not stored_name and peer_id != -1 and _peer_names.has(peer_id):
				stored_name = _peer_names[peer_id]
				_peer_names.erase(peer_id)  # Remove from temporary storage
				CogitoGlobals.debug_log(
					true,  # Always log this
					"PlayerManager",
					"Restored stored name for player_id %d (peer_id %d): %s" % [player_id, peer_id, stored_name]
				)
		
		if stored_name:
			_player_names[player_id] = stored_name
		elif is_local:
			_player_names[player_id] = "You"
		else:
			_player_names[player_id] = "Player %d" % player_id
	
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
	_player_names.erase(player_id)
	
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
	if not _players.has(player_id):
		return null
	var player = _players[player_id]
	# Check if player is still valid (not freed)
	if not is_instance_valid(player):
		# Player was freed, remove from registry
		_players.erase(player_id)
		return null
	return player


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


## Set player name by peer_id (for storing names before player registration)
func set_player_name_by_peer_id(peer_id: int, name: String) -> void:
	if name.is_empty():
		return
	
	# Update PlayerData
	var player_data = get_player_data(peer_id)
	player_data.player_name = name
	
	# Also update _peer_names for backward compatibility
	_peer_names[peer_id] = name
	
	CogitoGlobals.debug_log(
		true,  # Always log this for debugging
		"PlayerManager",
		"Stored name for peer_id %d: %s (PlayerData updated)" % [peer_id, name]
	)
	
	# If player is already registered, also update their name in _player_names
	var player_node = get_player_by_peer_id(peer_id)
	if player_node:
		var player_id = get_player_id(player_node)
		if player_id != -1:
			_player_names[player_id] = name
			# Update visual representation
			var visual_rep = player_node.get_node_or_null("PlayerVisualRepresentation")
			if visual_rep and visual_rep.has_method("update_player_name"):
				visual_rep.update_player_name(name)
				CogitoGlobals.debug_log(
					true,  # Always log this
					"PlayerManager",
					"Updated visual representation for registered player %d (peer_id %d): %s" % [player_id, peer_id, name]
				)
	
	# Sync via RPC if in multiplayer
	if NetworkManager and NetworkManager.is_multiplayer():
		NetworkManager.sync_player_data.rpc(player_data.to_dict())
		CogitoGlobals.debug_log(
			true,  # Always log this
			"PlayerManager",
			"Synced player data via RPC for peer_id %d: %s" % [peer_id, name]
		)


## Set player name
func set_player_name(player_id: int, name: String) -> void:
	if not _players.has(player_id):
		# Player not registered yet, try to store by peer_id if available
		if NetworkManager and NetworkManager.is_multiplayer():
			var peer_id = _player_peer_ids.get(player_id, -1)
			if peer_id != -1:
				_peer_names[peer_id] = name
				CogitoGlobals.debug_log(
					enable_logging,
					"PlayerManager",
					"Storing name for peer_id %d (player_id %d not registered yet): %s" % [peer_id, player_id, name]
				)
			else:
				# Try to find peer_id from local player
				if _local_player_id == player_id:
					var local_peer_id = NetworkManager.get_local_peer_id() if NetworkManager else -1
					if local_peer_id != -1:
						_peer_names[local_peer_id] = name
						CogitoGlobals.debug_log(
							enable_logging,
							"PlayerManager",
							"Storing name for local peer_id %d (player_id %d not registered yet): %s" % [local_peer_id, player_id, name]
						)
		CogitoGlobals.debug_log(
			true,
			"PlayerManager",
			"Attempted to set name for non-existent player ID: %d (stored by peer_id if available)" % player_id
		)
		return
	
	_player_names[player_id] = name
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerManager",
		"Player %d name set to: %s" % [player_id, name]
	)
	
	# Update visual representation if player has one
	var player_node = _players[player_id]
	if player_node:
		var visual_rep = player_node.get_node_or_null("PlayerVisualRepresentation")
		if visual_rep:
			if visual_rep.has_method("update_player_name"):
				visual_rep.update_player_name(name)
				CogitoGlobals.debug_log(
					enable_logging,
					"PlayerManager",
					"Updated visual representation for player %d with name: %s" % [player_id, name]
				)
			else:
				CogitoGlobals.debug_log(
					enable_logging,
					"PlayerManager",
					"PlayerVisualRepresentation found but doesn't have update_player_name method"
				)
		else:
			# PlayerVisualRepresentation may not be created yet, try again after a delay
			# This can happen if name is set before PlayerVisualRepresentation._ready() completes
			call_deferred("_update_visual_representation_delayed", player_id, name)
			CogitoGlobals.debug_log(
				enable_logging,
				"PlayerManager",
				"PlayerVisualRepresentation not found for player %d, will retry after delay" % player_id
			)


## Delayed update of visual representation (called via call_deferred)
func _update_visual_representation_delayed(player_id: int, name: String) -> void:
	if not _players.has(player_id):
		return
	
	var player_node = _players[player_id]
	if not player_node:
		return
	
	var visual_rep = player_node.get_node_or_null("PlayerVisualRepresentation")
	if visual_rep and visual_rep.has_method("update_player_name"):
		visual_rep.update_player_name(name)
		CogitoGlobals.debug_log(
			enable_logging,
			"PlayerManager",
			"Delayed update: Updated visual representation for player %d with name: %s" % [player_id, name]
		)


## Get player name
func get_player_name(player_id: int) -> String:
	var name = _player_names.get(player_id, "")
	if name == "" or name == "You" or name.begins_with("Player "):
		# Try to get from PlayerData via peer_id
		var peer_id = _player_peer_ids.get(player_id, -1)
		if peer_id != -1 and _player_data.has(peer_id):
			var player_data = _player_data[peer_id] as PlayerData
			if player_data and player_data.player_name != "" and not player_data.player_name.begins_with("Player "):
				name = player_data.player_name
				# Cache it in _player_names
				_player_names[player_id] = name
				CogitoGlobals.debug_log(
					true,  # Always log this
					"PlayerManager",
					"Got name from PlayerData for player_id %d (peer_id %d): %s" % [player_id, peer_id, name]
				)
	
	if name == "" or name.begins_with("Player "):
		name = "Player %d" % player_id
	
	return name


## Get player name by peer_id (for use before player registration)
func get_player_name_by_peer_id(peer_id: int) -> String:
	# First check PlayerData (most reliable)
	if _player_data.has(peer_id):
		var data = _player_data[peer_id] as PlayerData
		if data and data.player_name != "" and not data.player_name.begins_with("Player "):
			CogitoGlobals.debug_log(
				true,  # Always log this for debugging
				"PlayerManager",
				"Getting name from PlayerData for peer_id %d: %s" % [peer_id, data.player_name]
			)
			return data.player_name
	
	# Fallback to old _peer_names system
	var name = _peer_names.get(peer_id, "")
	if name != "" and not name.begins_with("Player "):
		CogitoGlobals.debug_log(
			true,  # Always log this for debugging
			"PlayerManager",
			"Getting name from _peer_names for peer_id %d: %s" % [peer_id, name]
		)
		return name
	
	# Last resort: try to find by player_id
	for player_id in _player_peer_ids.keys():
		if _player_peer_ids[player_id] == peer_id:
			var found_name = _player_names.get(player_id, "")
			if found_name != "" and found_name != "You" and not found_name.begins_with("Player "):
				CogitoGlobals.debug_log(
					true,  # Always log this for debugging
					"PlayerManager",
					"Getting name from _player_names for peer_id %d (player_id %d): %s" % [peer_id, player_id, found_name]
				)
				return found_name
			break
	
	CogitoGlobals.debug_log(
		true,  # Always log this for debugging
		"PlayerManager",
		"Could not find name for peer_id %d, returning empty string" % peer_id
	)
	return ""


## Get or create PlayerData for a peer_id
func get_player_data(peer_id: int) -> PlayerData:
	if not _player_data.has(peer_id):
		_player_data[peer_id] = PlayerData.new(peer_id, "Player %d" % peer_id)
	return _player_data[peer_id] as PlayerData


## Update player data from Dictionary (received via RPC)
func update_player_data(peer_id: int, data_dict: Dictionary) -> void:
	var player_data = get_player_data(peer_id)
	
	# Check if we already have a valid name (don't overwrite with default)
	var existing_name = player_data.player_name
	var new_name = data_dict.get("player_name", "")
	
	# Only update name if new name is valid and not default
	if new_name != "" and not new_name.begins_with("Player ") and new_name != "You":
		player_data.from_dict(data_dict)
	else:
		# Update other fields but preserve existing name if it's valid
		if data_dict.has("spawn_position"):
			player_data.spawn_position = data_dict["spawn_position"]
		# Don't update name if it's default or empty
	
	CogitoGlobals.debug_log(
		true,  # Always log this
		"PlayerManager",
		"Updated player data for peer_id %d: name=%s (was: %s)" % [peer_id, player_data.player_name, existing_name]
	)
	
	# Update player name if player is registered
	for player_id in _player_peer_ids.keys():
		if _player_peer_ids[player_id] == peer_id:
			# Only update if we have a valid name
			if player_data.player_name != "" and not player_data.player_name.begins_with("Player ") and player_data.player_name != "You":
				# Update _player_names directly to avoid recursion
				_player_names[player_id] = player_data.player_name
				# Also update visual representation
				var player_node = _players.get(player_id)
				if player_node:
					var visual_rep = player_node.get_node_or_null("PlayerVisualRepresentation")
					if visual_rep and visual_rep.has_method("update_player_name"):
						visual_rep.update_player_name(player_data.player_name)
			break
	
	# Also update _peer_names for backward compatibility
	if player_data.player_name != "" and not player_data.player_name.begins_with("Player "):
		_peer_names[peer_id] = player_data.player_name
	
	# Emit event for UI updates
	if NetworkEventBus:
		NetworkEventBus.player_data_updated.emit(peer_id, player_data)


## Get all player data (for syncing to new clients)
func get_all_player_data() -> Dictionary:
	var result = {}
	for peer_id in _player_data.keys():
		var data = _player_data[peer_id] as PlayerData
		if data:
			result[peer_id] = data.to_dict()
	return result


## Callback when a peer connects
func _on_network_connected(peer_id: int) -> void:
	# If we're the host, send our player data to the new client
	if NetworkManager and NetworkManager.is_host():
		var local_peer_id = NetworkManager.get_local_peer_id()
		if local_peer_id != -1:
			var local_data = get_player_data(local_peer_id)
			# Send our data to the new client
			NetworkManager.sync_player_data.rpc_id(peer_id, local_data.to_dict())
			
			# Also send data for all other players
			for other_peer_id in _player_data.keys():
				if other_peer_id != local_peer_id:
					var other_data = _player_data[other_peer_id] as PlayerData
					if other_data:
						NetworkManager.sync_player_data.rpc_id(peer_id, other_data.to_dict())


## Callback when a peer disconnects
func _on_network_disconnected(peer_id: int) -> void:
	# Remove player data
	if _player_data.has(peer_id):
		_player_data.erase(peer_id)
	_peer_names.erase(peer_id)
