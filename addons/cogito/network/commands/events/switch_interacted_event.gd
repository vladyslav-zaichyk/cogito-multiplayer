extends Event
class_name SwitchInteractedEvent
## Event emitted when a player interacts with a switch.

var switch_path: String = ""
var switch_network_id: String = ""
var is_on: bool = false


func _init(player_id_value: int = -1, path: String = "", network_id: String = "", on: bool = false):
	super._init(player_id_value, "switch_interacted")
	switch_path = path
	switch_network_id = network_id
	is_on = on


## Serialize event for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	base_data["switch_path"] = switch_path
	base_data["switch_network_id"] = switch_network_id
	base_data["is_on"] = is_on
	
	return base_data


## Deserialize event from network data
static func deserialize(data: Dictionary) -> Event:
	var player_id = data.get("player_id", -1)
	var path = data.get("switch_path", "")
	var network_id = data.get("switch_network_id", "")
	var is_on_value = data.get("is_on", false)
	
	return SwitchInteractedEvent.new(player_id, path, network_id, is_on_value)

