extends Event
class_name ContainerInteractedEvent
## Event emitted when a player interacts with a container.

var container_path: String = ""
var container_network_id: String = ""
var is_open: bool = false


func _init(player_id_value: int = -1, path: String = "", network_id: String = "", open: bool = false):
	super._init(player_id_value, "container_interacted")
	container_path = path
	container_network_id = network_id
	is_open = open


## Serialize event for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	base_data["container_path"] = container_path
	base_data["container_network_id"] = container_network_id
	base_data["is_open"] = is_open
	
	return base_data


## Deserialize event from network data
static func deserialize(data: Dictionary) -> Event:
	var player_id = data.get("player_id", -1)
	var path = data.get("container_path", "")
	var network_id = data.get("container_network_id", "")
	var is_open_value = data.get("is_open", false)
	
	return ContainerInteractedEvent.new(player_id, path, network_id, is_open_value)

