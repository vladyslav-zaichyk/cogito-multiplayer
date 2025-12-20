extends Event
class_name WieldableUnequippedEvent
## Event emitted when a player unequips a wieldable item.

var wieldable_item: WieldableItemPD


func _init(player_id_value: int = -1, wieldable_value: WieldableItemPD = null):
	super._init(player_id_value, "wieldable_unequipped")
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
	
	base_data["wieldable_item"] = item_data
	return base_data


## Deserialize event from network data
static func deserialize(data: Dictionary) -> Event:
	var player_id = data.get("player_id", -1)
	var item_data = data.get("wieldable_item", {})
	
	var wieldable: WieldableItemPD = null
	if item_data.has("resource_path") and not item_data.resource_path.is_empty():
		wieldable = load(item_data.resource_path) as WieldableItemPD
	
	return WieldableUnequippedEvent.new(player_id, wieldable)

