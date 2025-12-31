extends Resource
## Player Data Resource
## Stores all player information that needs to be synchronized across network

class_name PlayerData

## Peer ID of the player
@export var peer_id: int = -1

## Player name
@export var player_name: String = "Player"

## Player ID (local to this client)
var player_id: int = -1

## Is this the local player?
var is_local: bool = false

## Position (for initial spawn)
var spawn_position: Vector3 = Vector3.ZERO

## Last update time (for cleanup)
var last_update_time: float = 0.0


func _init(p_peer_id: int = -1, p_player_name: String = "Player") -> void:
	peer_id = p_peer_id
	player_name = p_player_name
	last_update_time = Time.get_ticks_msec() / 1000.0


## Serialize to Dictionary for RPC
func to_dict() -> Dictionary:
	return {
		"peer_id": peer_id,
		"player_name": player_name,
		"spawn_position": spawn_position
	}


## Deserialize from Dictionary
func from_dict(data: Dictionary) -> void:
	if data.has("peer_id"):
		peer_id = data["peer_id"]
	if data.has("player_name"):
		player_name = data["player_name"]
	if data.has("spawn_position"):
		spawn_position = data["spawn_position"]
	last_update_time = Time.get_ticks_msec() / 1000.0


## Update from another PlayerData
func update_from(other: PlayerData) -> void:
	if other.player_name != "":
		player_name = other.player_name
	if other.spawn_position != Vector3.ZERO:
		spawn_position = other.spawn_position
	last_update_time = Time.get_ticks_msec() / 1000.0

