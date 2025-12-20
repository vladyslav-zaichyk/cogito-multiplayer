extends Event
class_name DoorInteractedEvent
## Event emitted when a player interacts with a door.

var door_path: String = ""
var door_network_id: String = ""
var action: String = "toggle"  # "toggle", "lock", "unlock"
var is_open: bool = false
var is_locked: bool = false


func _init(player_id_value: int = -1, path: String = "", network_id: String = "", action_value: String = "toggle", open: bool = false, locked: bool = false):
	super._init(player_id_value, "door_interacted")
	door_path = path
	door_network_id = network_id
	action = action_value
	is_open = open
	is_locked = locked


## Serialize event for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	base_data["door_path"] = door_path
	base_data["door_network_id"] = door_network_id
	base_data["action"] = action
	base_data["is_open"] = is_open
	base_data["is_locked"] = is_locked
	
	return base_data


## Deserialize event from network data
static func deserialize(data: Dictionary) -> Event:
	var player_id = data.get("player_id", -1)
	var path = data.get("door_path", "")
	var network_id = data.get("door_network_id", "")
	var action_value = data.get("action", "toggle")
	var is_open_value = data.get("is_open", false)
	var is_locked_value = data.get("is_locked", false)
	
	return DoorInteractedEvent.new(player_id, path, network_id, action_value, is_open_value, is_locked_value)

