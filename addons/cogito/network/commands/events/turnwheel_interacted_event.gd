extends Event
class_name TurnwheelInteractedEvent
## Event emitted when a player interacts with a turnwheel.

var turnwheel_path: String = ""
var turnwheel_network_id: String = ""
var interaction_type: String = "complete"  # "start" or "complete"
var has_been_turned: bool = false


func _init(player_id_value: int = -1, path: String = "", network_id: String = "", type: String = "complete", turned: bool = false):
	super._init(player_id_value, "turnwheel_interacted")
	turnwheel_path = path
	turnwheel_network_id = network_id
	interaction_type = type
	has_been_turned = turned


func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	base_data["turnwheel_path"] = turnwheel_path
	base_data["turnwheel_network_id"] = turnwheel_network_id
	base_data["interaction_type"] = interaction_type
	base_data["has_been_turned"] = has_been_turned
	
	return base_data


static func deserialize(data: Dictionary) -> Event:
	var player_id = data.get("player_id", -1)
	var path = data.get("turnwheel_path", "")
	var network_id = data.get("turnwheel_network_id", "")
	var type = data.get("interaction_type", "complete")
	var turned = data.get("has_been_turned", false)
	
	return TurnwheelInteractedEvent.new(player_id, path, network_id, type, turned)

