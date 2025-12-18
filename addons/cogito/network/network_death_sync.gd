extends Node
## Network Death Sync Component
## Synchronizes player death and respawn in multiplayer
## Attach this to a CogitoPlayer

## Enable/disable logging
var enable_logging: bool = false

## Reference to the parent CogitoPlayer
var parent_body: CogitoPlayer = null

## Is this the local player?
var is_local: bool = false

## Peer ID of this player
var peer_id: int = 0

## Reference to health attribute
var health_attribute: CogitoHealthAttribute = null


func _ready() -> void:
	parent_body = get_parent() as CogitoPlayer
	if not parent_body:
		push_error("NetworkDeathSync: Parent must be a CogitoPlayer")
		return
	
	# Wait a frame for player to be initialized
	await get_tree().process_frame
	
	# Determine if this is local player
	if NetworkManager and NetworkManager.is_multiplayer():
		# Get peer_id from PlayerManager
		if PlayerManager:
			var player_id = PlayerManager.get_player_id(parent_body)
			if player_id != -1:
				peer_id = PlayerManager.get_player_peer_id(player_id)
				var local_peer_id = NetworkManager.get_local_peer_id()
				is_local = (peer_id == local_peer_id)
			else:
				# Player not registered yet, wait a bit
				await get_tree().process_frame
				player_id = PlayerManager.get_player_id(parent_body)
				if player_id != -1:
					peer_id = PlayerManager.get_player_peer_id(player_id)
					var local_peer_id = NetworkManager.get_local_peer_id()
					is_local = (peer_id == local_peer_id)
	else:
		is_local = false
		peer_id = 0
	
	# Get health attribute
	if parent_body.has_method("get") and parent_body.get("player_attributes"):
		var player_attributes = parent_body.player_attributes
		if player_attributes is Dictionary:
			health_attribute = player_attributes.get("health")
			if health_attribute and health_attribute is CogitoHealthAttribute:
				# Connect to death signal
				if not health_attribute.death.is_connected(_on_local_death):
					health_attribute.death.connect(_on_local_death)
				CogitoGlobals.debug_log(
					enable_logging,
					"NetworkDeathSync",
					"Connected to health attribute death signal"
				)
			else:
				CogitoGlobals.debug_log(
					enable_logging,
					"NetworkDeathSync",
					"Health attribute not found or not CogitoHealthAttribute"
				)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkDeathSync",
		"Initialized for %s player (peer_id: %d)" % ["local" if is_local else "remote", peer_id]
	)


## Called when local player dies
func _on_local_death() -> void:
	if not is_local:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# Sync death to all clients
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkDeathSync",
		"Local player died, syncing to all clients"
	)
	
	NetworkManager.sync_player_death.rpc(peer_id)


## Called by RPC when a player dies
func _receive_death(dead_peer_id: int) -> void:
	if not parent_body:
		return
	
	# Only process if this is about a remote player
	if is_local and dead_peer_id == peer_id:
		# This is about ourselves, but we already handled it locally
		return
	
	# Set player as dead
	parent_body.is_dead = true
	
	# Call on_death if it exists
	if parent_body.has_method("_on_death"):
		parent_body._on_death()
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkDeathSync",
		"Received death sync for peer %d" % dead_peer_id
	)

