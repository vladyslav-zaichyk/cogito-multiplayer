extends Event
class_name ItemUsedEvent
## Event emitted when a player uses an item from inventory.

var item: InventoryItemPD
var slot_index: int = -1


func _init(player_id_value: int = -1, item_value: InventoryItemPD = null, slot_index_value: int = -1):
	super._init(player_id_value, "item_used")
	item = item_value
	slot_index = slot_index_value


## Serialize event for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	# Serialize item data
	var item_data = {}
	if item:
		item_data = {
			"name": item.name,
			"resource_path": item.resource_path if item.resource_path else "",
			"item_type": item.get_script().get_path().get_file().get_basename() if item.get_script() else ""
		}
	
	base_data["item"] = item_data
	base_data["slot_index"] = slot_index
	
	return base_data


## Deserialize event from network data
static func deserialize(data: Dictionary) -> Event:
	var player_id = data.get("player_id", -1)
	var item_data = data.get("item", {})
	var slot_index = data.get("slot_index", -1)
	
	# Try to load item from resource path
	var item: InventoryItemPD = null
	if item_data.has("resource_path") and not item_data.resource_path.is_empty():
		item = load(item_data.resource_path) as InventoryItemPD
	
	return ItemUsedEvent.new(player_id, item, slot_index)

