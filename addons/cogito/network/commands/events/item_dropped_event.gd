extends Event
class_name ItemDroppedEvent
## Event emitted when a player drops an item.

var item: InventoryItemPD
var slot_data: InventorySlotPD
var position: Vector3


func _init(player_id_value: int = -1, item_value: InventoryItemPD = null, slot_data_value: InventorySlotPD = null, position_value: Vector3 = Vector3.ZERO):
	super._init(player_id_value, "item_dropped")
	item = item_value
	slot_data = slot_data_value
	position = position_value


## Serialize event for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	# Serialize item data
	var item_data = {}
	if item:
		# Try to get resource_path - prefer .tres files over .gd scripts
		var resource_path = item.resource_path
		
		# If resource_path is empty or points to a script (.gd), try to find the .tres file
		if resource_path.is_empty() or resource_path.ends_with(".gd"):
			var item_name = item.name
			if not item_name.is_empty():
				# Try common resource paths (similar to network_wieldable_sync.gd)
				var possible_paths = [
					"res://addons/cogito/inventory_pd/Items/Cogito_%s.tres" % item_name.replace(" ", ""),
					"res://addons/cogito/inventory_pd/Items/Cogito_%s.tres" % item_name.replace(" ", "_"),
					"res://addons/cogito/inventory_pd/Items/%s.tres" % item_name.replace(" ", ""),
					"res://addons/cogito/inventory_pd/Items/%s.tres" % item_name.replace(" ", "_"),
				]
				
				# Special cases
				if item_name == "Foam Pistol":
					possible_paths.insert(0, "res://addons/cogito/inventory_pd/Items/Cogito_Pistol.tres")
				
				for path in possible_paths:
					if ResourceLoader.exists(path):
						var test_resource = load(path) as InventoryItemPD
						if test_resource and test_resource.name == item_name:
							resource_path = path
							break
		
		item_data = {
			"name": item.name,
			"resource_path": resource_path,
			"item_type": item.get_script().get_path().get_file().get_basename() if item.get_script() else ""
		}
	
	# Serialize slot data
	var slot_data_dict = {}
	if slot_data:
		slot_data_dict = {
			"quantity": slot_data.quantity if "quantity" in slot_data else 1,
			"origin_index": slot_data.origin_index if "origin_index" in slot_data else -1
		}
	
	base_data["item"] = item_data
	base_data["slot_data"] = slot_data_dict
	base_data["position"] = {
		"x": position.x,
		"y": position.y,
		"z": position.z
	}
	
	return base_data


## Deserialize event from network data
static func deserialize(data: Dictionary) -> Event:
	var player_id = data.get("player_id", -1)
	var item_data = data.get("item", {})
	var slot_data_dict = data.get("slot_data", {})
	var position_data = data.get("position", {})
	
	# Reconstruct position
	var position = Vector3(
		position_data.get("x", 0.0),
		position_data.get("y", 0.0),
		position_data.get("z", 0.0)
	)
	
	# Try to load item from resource path
	var item: InventoryItemPD = null
	if item_data.has("resource_path") and not item_data["resource_path"].is_empty():
		var resource_path = item_data["resource_path"]
		# Skip .gd scripts - they're not loadable resources
		if not resource_path.ends_with(".gd"):
			item = load(resource_path) as InventoryItemPD
			if not item:
				push_warning("ItemDroppedEvent: Failed to load item from resource_path: %s, trying fallback" % resource_path)
		else:
			push_warning("ItemDroppedEvent: resource_path points to script (.gd), trying fallback: %s" % resource_path)
	
	# Fallback: try to find by name if resource_path failed or missing
	if not item and item_data.has("name"):
		var item_name = item_data["name"]
		# Try common resource paths (similar to network_wieldable_sync.gd)
		var possible_paths = [
			"res://addons/cogito/inventory_pd/Items/Cogito_%s.tres" % item_name.replace(" ", ""),
			"res://addons/cogito/inventory_pd/Items/Cogito_%s.tres" % item_name.replace(" ", "_"),
			"res://addons/cogito/inventory_pd/Items/%s.tres" % item_name.replace(" ", ""),
			"res://addons/cogito/inventory_pd/Items/%s.tres" % item_name.replace(" ", "_"),
		]
		
		# Special cases
		if item_name == "Foam Pistol":
			possible_paths.insert(0, "res://addons/cogito/inventory_pd/Items/Cogito_Pistol.tres")
		
		for path in possible_paths:
			if ResourceLoader.exists(path):
				var test_resource = load(path) as InventoryItemPD
				if test_resource and test_resource.name == item_name:
					item = test_resource
					break
	
	# Create slot data
	var slot_data: InventorySlotPD = null
	if item and slot_data_dict.size() > 0:
		slot_data = InventorySlotPD.new()
		slot_data.inventory_item = item
		slot_data.quantity = slot_data_dict.get("quantity", 1)
		slot_data.origin_index = slot_data_dict.get("origin_index", -1)
	
	return ItemDroppedEvent.new(player_id, item, slot_data, position)

