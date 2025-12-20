extends Event
class_name CarryingStoppedEvent
## Event emitted when a player stops carrying an object.

var carryable_parent_path: String = ""
var carryable_network_id: int = -1
var drop_force: float = 0.0  # Force applied when dropping (0.0 = drop, >0.0 = throw)


func _init(player_id_value: int = -1, parent_path: String = "", network_id: int = -1, drop_force_value: float = 0.0):
	super._init(player_id_value, "carrying_stopped")
	carryable_parent_path = parent_path
	carryable_network_id = network_id
	drop_force = drop_force_value


## Serialize event for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	base_data["carryable_parent_path"] = carryable_parent_path
	base_data["carryable_network_id"] = carryable_network_id
	base_data["drop_force"] = drop_force
	
	return base_data


## Deserialize event from network data
static func deserialize(data: Dictionary) -> Event:
	var player_id = data.get("player_id", -1)
	var parent_path = data.get("carryable_parent_path", "")
	var network_id = data.get("carryable_network_id", -1)
	var drop_force_value = data.get("drop_force", 0.0)
	
	return CarryingStoppedEvent.new(player_id, parent_path, network_id, drop_force_value)

