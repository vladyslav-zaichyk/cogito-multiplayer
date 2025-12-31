extends Event
class_name WieldableEquippedEvent
## Event emitted when a player equips a wieldable item.

var wieldable_item: WieldableItemPD
var slot_index: int = -1


func _init(player_id_value: int = -1, wieldable_value: WieldableItemPD = null, slot_index_value: int = -1):
	super._init(player_id_value, "wieldable_equipped")
	wieldable_item = wieldable_value
	slot_index = slot_index_value


## Serialize event for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	# Serialize wieldable item data
	var item_data = {}
	if wieldable_item:
		item_data = {
			"name": wieldable_item.name,
			"resource_path": wieldable_item.resource_path if wieldable_item.resource_path else "",
			"item_type": wieldable_item.get_script().get_path().get_file().get_basename() if wieldable_item.get_script() else "",
			"charge_current": wieldable_item.charge_current,
			"charge_max": wieldable_item.charge_max
		}
	
	base_data["wieldable_item"] = item_data
	base_data["slot_index"] = slot_index
	return base_data


## Deserialize event from network data
static func deserialize(data: Dictionary) -> Event:
	var player_id = data.get("player_id", -1)
	var item_data = data.get("wieldable_item", {})
	var slot_index = data.get("slot_index", -1)
	
	var wieldable: WieldableItemPD = null
	if item_data.has("resource_path") and not item_data.resource_path.is_empty():
		wieldable = load(item_data.resource_path) as WieldableItemPD
		if wieldable:
			# Restore charge state
			wieldable.charge_current = item_data.get("charge_current", 0.0)
			wieldable.charge_max = item_data.get("charge_max", 0.0)
	
	return WieldableEquippedEvent.new(player_id, wieldable, slot_index)

