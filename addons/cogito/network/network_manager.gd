extends Node
## Network Manager for handling multiplayer connections.
## Provides abstraction over Godot's Multiplayer API.
## Note: This is an autoload singleton, not a class_name

## Enable/disable logging
var enable_logging: bool = false

## Current game mode: SINGLE_PLAYER or MULTIPLAYER
enum GameMode { SINGLE_PLAYER, MULTIPLAYER }
var current_game_mode: GameMode = GameMode.SINGLE_PLAYER

## Multiplayer peer (ENetMultiplayerPeer, WebSocketMultiplayerPeer, etc.)
var multiplayer_peer: MultiplayerPeer = null

## Is this instance the server/host?
var is_server: bool = false

## Is this instance a client?
var is_client: bool = false

## Local peer ID (1 for server, >1 for clients)
var local_peer_id: int = 1

## Port for multiplayer connections
var multiplayer_port: int = 7777

## Max number of players
var max_players: int = 4


func _ready() -> void:
	# Set up multiplayer connection handlers
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	CogitoGlobals.debug_log(
		true, "NetworkManager", "Network Manager initialized (Single-player mode)"
	)


## Start hosting a multiplayer game
func start_hosting(port: int = 7777, max_peers: int = 4) -> bool:
	if current_game_mode == GameMode.MULTIPLAYER:
		CogitoGlobals.debug_log(
			true, "NetworkManager", "Already in multiplayer mode!"
		)
		return false
	
	multiplayer_port = port
	max_players = max_peers
	
	# Create ENet peer for hosting
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, max_peers)
	
	if error != OK:
		CogitoGlobals.debug_log(
			true, "NetworkManager", "Failed to create server: %d" % error
		)
		if NetworkEventBus:
			NetworkEventBus.network_error.emit("Failed to create server: %d" % error)
		return false
	
	multiplayer_peer = peer
	multiplayer.multiplayer_peer = peer
	
	is_server = true
	is_client = false
	local_peer_id = 1
	current_game_mode = GameMode.MULTIPLAYER
	
	CogitoGlobals.debug_log(
		enable_logging, "NetworkManager", "Server started on port %d" % port
	)
	
	if NetworkEventBus:
		NetworkEventBus.network_connected.emit(local_peer_id)
	
	return true


## Join a multiplayer game
func join_game(address: String, port: int = 7777) -> bool:
	if current_game_mode == GameMode.MULTIPLAYER:
		CogitoGlobals.debug_log(
			true, "NetworkManager", "Already in multiplayer mode!"
		)
		return false
	
	multiplayer_port = port
	
	# Create ENet peer for client
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		CogitoGlobals.debug_log(
			true, "NetworkManager", "Failed to create client: %d" % error
		)
		if NetworkEventBus:
			NetworkEventBus.network_error.emit("Failed to create client: %d" % error)
		return false
	
	multiplayer_peer = peer
	multiplayer.multiplayer_peer = peer
	
	is_server = false
	is_client = true
	current_game_mode = GameMode.MULTIPLAYER
	
	CogitoGlobals.debug_log(
		enable_logging, "NetworkManager", "Connecting to %s:%d" % [address, port]
	)
	
	return true


## Disconnect from multiplayer game
func disconnect_from_game() -> void:
	if current_game_mode == GameMode.SINGLE_PLAYER:
		return
	
	if multiplayer_peer:
		multiplayer_peer.close()
		multiplayer_peer = null
	
	multiplayer.multiplayer_peer = null
	
	is_server = false
	is_client = false
	local_peer_id = 1
	current_game_mode = GameMode.SINGLE_PLAYER
	
	CogitoGlobals.debug_log(
		enable_logging, "NetworkManager", "Disconnected from multiplayer"
	)
	
	if NetworkEventBus:
		NetworkEventBus.network_disconnected.emit(local_peer_id)


## Check if we're in multiplayer mode
func is_multiplayer() -> bool:
	return current_game_mode == GameMode.MULTIPLAYER


## Check if we're in single-player mode
func is_single_player() -> bool:
	return current_game_mode == GameMode.SINGLE_PLAYER


## Get local peer ID
func get_local_peer_id() -> int:
	if is_multiplayer():
		return multiplayer.get_unique_id()
	return 1


## Check if this is the server
func is_host() -> bool:
	return is_server


## Check if this is a client
func is_connected_client() -> bool:
	return is_client


## Get all connected peer IDs
func get_connected_peers() -> Array:
	if not is_multiplayer():
		return []
	
	var peers = []
	for peer_id in multiplayer.get_peers():
		peers.append(peer_id)
	return peers


## Callback when a peer connects
func _on_peer_connected(peer_id: int) -> void:
	CogitoGlobals.debug_log(
		enable_logging, "NetworkManager", "Peer connected: %d" % peer_id
	)
	
	if NetworkEventBus:
		NetworkEventBus.network_connected.emit(peer_id)


## Callback when a peer disconnects
func _on_peer_disconnected(peer_id: int) -> void:
	CogitoGlobals.debug_log(
		enable_logging, "NetworkManager", "Peer disconnected: %d" % peer_id
	)
	
	# Unregister player if exists
	if PlayerManager:
		var player = PlayerManager.get_player(peer_id)
		if player:
			PlayerManager.unregister_player(peer_id)
	
	if NetworkEventBus:
		NetworkEventBus.network_disconnected.emit(peer_id)


## Callback when connected to server
func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	CogitoGlobals.debug_log(
		enable_logging, "NetworkManager", "Connected to server as peer: %d" % local_peer_id
	)
	
	if NetworkEventBus:
		NetworkEventBus.network_connected.emit(local_peer_id)


## Callback when connection fails
func _on_connection_failed() -> void:
	CogitoGlobals.debug_log(
		true, "NetworkManager", "Connection to server failed"
	)
	
	disconnect_from_game()
	
	if NetworkEventBus:
		NetworkEventBus.network_error.emit("Connection to server failed")


## Callback when server disconnects
func _on_server_disconnected() -> void:
	CogitoGlobals.debug_log(
		true, "NetworkManager", "Server disconnected"
	)
	
	disconnect_from_game()
	
	if NetworkEventBus:
		NetworkEventBus.network_error.emit("Server disconnected")


## RPC: Sync player position (called from NetworkPositionSync)
@rpc("any_peer", "call_local", "unreliable")
func sync_player_position(peer_id: int, position: Vector3) -> void:
	# Route to the correct player's NetworkPositionSync component
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var position_sync = player_node.get_node_or_null("NetworkPositionSync")
			if position_sync:
				position_sync._receive_position_update(position)


## RPC: Sync player rotation (called from NetworkRotationSync)
@rpc("any_peer", "call_local", "unreliable")
func sync_player_rotation(peer_id: int, body_rotation: float, head_rotation: float) -> void:
	# Route to the correct player's NetworkRotationSync component
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var rotation_sync = player_node.get_node_or_null("NetworkRotationSync")
			if rotation_sync:
				rotation_sync._receive_rotation_update(body_rotation, head_rotation)


## RPC: Sync player attribute (called from NetworkAttributeSync)
@rpc("any_peer", "call_local", "reliable")
func sync_player_attribute(peer_id: int, attribute_name: String, current_value: float, max_value: float) -> void:
	# Route to the correct player's NetworkAttributeSync component
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var attribute_sync = player_node.get_node_or_null("NetworkAttributeSync")
			if attribute_sync:
				attribute_sync._receive_attribute_update(attribute_name, current_value, max_value)


## RPC: Sync player state (called from NetworkPlayerStateSync)
@rpc("any_peer", "call_local", "unreliable")
func sync_player_state(peer_id: int, state: Dictionary) -> void:
	# Route to the correct player's NetworkPlayerStateSync component
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var state_sync = player_node.get_node_or_null("NetworkPlayerStateSync")
			if state_sync:
				state_sync._receive_state_update(state)


## RPC: Sync player name (called from lobby or when player joins)
@rpc("any_peer", "call_local", "reliable")
func sync_player_name(peer_id: int, player_name: String) -> void:
	# Route to PlayerManager to update the name
	if PlayerManager:
		var player_node = PlayerManager.get_player_by_peer_id(peer_id)
		if player_node:
			var player_id = PlayerManager.get_player_id(player_node)
			if player_id != -1:
				PlayerManager.set_player_name(player_id, player_name)

