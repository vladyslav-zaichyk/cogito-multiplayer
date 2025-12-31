extends Event
class_name WieldableReloadedEvent
## Event emitted when a player reloads a wieldable item.

var wieldable_item: WieldableItemPD
var ammo_used: int
var new_charge: float


func _init(player_id_value: int = -1, wieldable_value: WieldableItemPD = null, ammo_used_value: int = 0, new_charge_value: float = 0.0):
	super._init(player_id_value, "wieldable_reloaded")
	wieldable_item = wieldable_value
	ammo_used = ammo_used_value
	new_charge = new_charge_value


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
	base_data["ammo_used"] = ammo_used
	base_data["new_charge"] = new_charge
	return base_data


## Deserialize event from network data
static func deserialize(data: Dictionary) -> Event:
	var player_id = data.get("player_id", -1)
	var item_data = data.get("wieldable_item", {})
	var ammo_used = data.get("ammo_used", 0)
	var new_charge = data.get("new_charge", 0.0)
	
	var wieldable: WieldableItemPD = null
	if item_data.has("resource_path") and not item_data.resource_path.is_empty():
		wieldable = load(item_data.resource_path) as WieldableItemPD
		if wieldable:
			# Restore charge state
			wieldable.charge_current = item_data.get("charge_current", 0.0)
			wieldable.charge_max = item_data.get("charge_max", 0.0)
	
	return WieldableReloadedEvent.new(player_id, wieldable, ammo_used, new_charge)

