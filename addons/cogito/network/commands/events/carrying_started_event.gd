extends Event
class_name CarryingStartedEvent
## Event emitted when a player starts carrying an object.

var carryable_parent_path: String = ""
var carryable_network_id: int = -1
var carryable_position: Vector3 = Vector3.ZERO


func _init(player_id_value: int = -1, parent_path: String = "", network_id: int = -1, position: Vector3 = Vector3.ZERO):
	super._init(player_id_value, "carrying_started")
	carryable_parent_path = parent_path
	carryable_network_id = network_id
	carryable_position = position


## Serialize event for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	base_data["carryable_parent_path"] = carryable_parent_path
	base_data["carryable_network_id"] = carryable_network_id
	base_data["carryable_position"] = {
		"x": carryable_position.x,
		"y": carryable_position.y,
		"z": carryable_position.z
	}
	
	return base_data


## Deserialize event from network data
static func deserialize(data: Dictionary) -> Event:
	var player_id = data.get("player_id", -1)
	var parent_path = data.get("carryable_parent_path", "")
	var network_id = data.get("carryable_network_id", -1)
	var position_data = data.get("carryable_position", {})
	
	# Reconstruct position
	var position = Vector3(
		position_data.get("x", 0.0),
		position_data.get("y", 0.0),
		position_data.get("z", 0.0)
	)
	
	return CarryingStartedEvent.new(player_id, parent_path, network_id, position)

