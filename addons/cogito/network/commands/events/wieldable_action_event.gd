extends Event
class_name WieldableActionEvent
## Event emitted when a player performs a wieldable action (primary or secondary).

enum ActionType { PRIMARY, SECONDARY }
var action_type: ActionType
var is_released: bool
var wieldable_item: WieldableItemPD


func _init(player_id_value: int = -1, action_type_value: ActionType = ActionType.PRIMARY, is_released_value: bool = false, wieldable_value: WieldableItemPD = null):
	super._init(player_id_value, "wieldable_action")
	action_type = action_type_value
	is_released = is_released_value
	wieldable_item = wieldable_value


## Serialize event for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	# Serialize wieldable item data
	var item_data = {}
	if wieldable_item:
		item_data = {
			"name": wieldable_item.name,
			"resource_path": wieldable_item.resource_path if wieldable_item.resource_path else "",
			"item_type": wieldable_item.get_script().get_path().get_file().get_basename() if wieldable_item.get_script() else ""
		}
	
	base_data["action_type"] = ActionType.keys()[action_type]
	base_data["is_released"] = is_released
	base_data["wieldable_item"] = item_data
	return base_data


## Deserialize event from network data
static func deserialize(data: Dictionary) -> Event:
	var player_id = data.get("player_id", -1)
	var action_type_str = data.get("action_type", "PRIMARY")
	var is_released = data.get("is_released", false)
	var item_data = data.get("wieldable_item", {})
	
	var action_type = ActionType.PRIMARY
	if action_type_str == "SECONDARY":
		action_type = ActionType.SECONDARY
	
	var wieldable: WieldableItemPD = null
	if item_data.has("resource_path") and not item_data.resource_path.is_empty():
		wieldable = load(item_data.resource_path) as WieldableItemPD
	
	return WieldableActionEvent.new(player_id, action_type, is_released, wieldable)

