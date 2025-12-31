extends Command
class_name PickupItemCommand
## Command for picking up an item from the world.
## This command handles the pickup logic and emits ItemPickedEvent on success.

## Slot data of the item to pick up
var slot_data: InventorySlotPD
## Position of the item in the world (for identification)
var item_position: Vector3
## Network ID of the item (if available)
var item_network_id: int = -1
## Scene path of the item (for identification)
var item_scene_path: String = ""


func _init(player_id_value: int, slot_data_value: InventorySlotPD, position: Vector3, network_id: int = -1, scene_path: String = ""):
	super._init(player_id_value)
	slot_data = slot_data_value
	item_position = position
	item_network_id = network_id
	item_scene_path = scene_path
	validation_type = ValidationType.HOST_VALIDATION  # Host validates item pickups


## Execute the command
func execute() -> CommandResult:
	# Get player's inventory
	var player = null
	if PlayerManager:
		player = PlayerManager.get_player(player_id)
	
	if not player or not player.inventory_data:
		var error_result = CommandResult.new(false, "Player or inventory not found")
		error_result.response_code = CommandResult.ResponseCode.PLAYER_NOT_FOUND
		return error_result
	
	var result = CommandResult.new()
	
	# Log charge_current for WieldableItemPD before picking up
	if slot_data.inventory_item is WieldableItemPD:
		var wieldable_item = slot_data.inventory_item as WieldableItemPD
		CogitoGlobals.debug_log(
			true,
			"PickupItemCommand",
			"[execute] Picking up WieldableItemPD with charge_current: %s / %s" % [
				wieldable_item.charge_current,
				wieldable_item.charge_max
			]
		)
	
	# Try to pick up the item (call existing method)
	var success = player.inventory_data.pick_up_slot_data(slot_data)
	
	# Log charge_current after picking up
	if success and slot_data.inventory_item is WieldableItemPD:
		var wieldable_item = slot_data.inventory_item as WieldableItemPD
		CogitoGlobals.debug_log(
			true,
			"PickupItemCommand",
			"[execute] After pick_up_slot_data, charge_current: %s / %s" % [
				wieldable_item.charge_current,
				wieldable_item.charge_max
			]
		)
	
	if success:
		# Create event
		var event = ItemPickedEvent.new(player_id, slot_data.inventory_item, slot_data)
		result.add_event(event)
		result.success = true
		result.data["slot_index"] = slot_data.origin_index
	else:
		result.success = false
		result.error_message = "Failed to pick up item (inventory full or other error)"
		result.response_code = CommandResult.ResponseCode.INVENTORY_FULL
	
	return result


## Validate the command before execution
func validate() -> bool:
	# Check if player exists
	if not PlayerManager:
		return false
	
	var player = PlayerManager.get_player(player_id)
	if not player:
		return false
	
	# Check if player has inventory
	if not player.inventory_data:
		return false
	
	# Check if item still exists in world (for multiplayer)
	# TODO: Implement proper item existence check
	# For now, we'll trust the client (can be improved later)
	
	return true


## Serialize command for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	# Serialize slot data
	var slot_data_dict = {}
	if slot_data:
		slot_data_dict = {
			"quantity": slot_data.quantity if "quantity" in slot_data else 1,
			"origin_index": slot_data.origin_index if "origin_index" in slot_data else -1
		}
		
		# Serialize item
		if slot_data.inventory_item:
			# Try to get resource_path - prefer .tres files over .gd scripts
			var resource_path = slot_data.inventory_item.resource_path
			
			# If resource_path is empty or points to a script (.gd), try to find the .tres file
			if resource_path.is_empty() or resource_path.ends_with(".gd"):
				var item_name = slot_data.inventory_item.name
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
			
			var item_dict = {
				"name": slot_data.inventory_item.name,
				"resource_path": resource_path,
				"item_type": slot_data.inventory_item.get_script().get_path().get_file().get_basename() if slot_data.inventory_item.get_script() else ""
			}
			
			# If this is a WieldableItemPD, serialize ammo state (charge_current and charge_max)
			if slot_data.inventory_item is WieldableItemPD:
				var wieldable_item = slot_data.inventory_item as WieldableItemPD
				item_dict["charge_current"] = wieldable_item.charge_current
				item_dict["charge_max"] = wieldable_item.charge_max
			
			slot_data_dict["item"] = item_dict
	
	base_data["slot_data"] = slot_data_dict
	base_data["item_position"] = {
		"x": item_position.x,
		"y": item_position.y,
		"z": item_position.z
	}
	base_data["item_network_id"] = item_network_id
	base_data["item_scene_path"] = item_scene_path
	
	return base_data


## Deserialize command from network data
static func deserialize(data: Dictionary) -> Command:
	var player_id = data.get("player_id", -1)
	var slot_data_dict = data.get("slot_data", {})
	var position_data = data.get("item_position", {})
	var network_id = data.get("item_network_id", -1)
	var scene_path = data.get("item_scene_path", "")
	
	# Reconstruct position
	var position = Vector3(
		position_data.get("x", 0.0),
		position_data.get("y", 0.0),
		position_data.get("z", 0.0)
	)
	
	# Try to load item from resource path
	var item: InventoryItemPD = null
	if slot_data_dict.has("item"):
		var item_data = slot_data_dict["item"]
		
		# Try resource_path first (skip if it's a .gd script)
		if item_data.has("resource_path") and not item_data["resource_path"].is_empty():
			var resource_path = item_data["resource_path"]
			# Skip .gd scripts - they're not loadable resources
			if not resource_path.ends_with(".gd"):
				item = load(resource_path) as InventoryItemPD
				if not item:
					push_warning("PickupItemCommand: Failed to load item from resource_path: %s, trying fallback" % resource_path)
			else:
				push_warning("PickupItemCommand: resource_path points to script (.gd), trying fallback: %s" % resource_path)
		
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
		
		if not item:
			var item_name = item_data.get("name", "unknown") if item_data.has("name") else "unknown"
			push_error("PickupItemCommand: Failed to deserialize slot_data - cannot load item '%s' (resource_path missing or invalid)" % item_name)
			return null
	else:
		# Item data missing
		push_error("PickupItemCommand: Failed to deserialize slot_data - item data missing")
		return null
	
	# Create slot data
	var slot_data: InventorySlotPD = null
	if item:
		# If this is a WieldableItemPD and we need to restore ammo state, duplicate the resource
		# to avoid modifying the shared resource
		var item_to_use = item
		if item is WieldableItemPD and slot_data_dict.has("item"):
			var item_data = slot_data_dict["item"]
			if item_data.has("charge_current"):
				# Duplicate the resource to avoid modifying the shared resource
				item_to_use = item.duplicate() as WieldableItemPD
				var wieldable_item = item_to_use as WieldableItemPD
				wieldable_item.charge_current = item_data.get("charge_current", 0.0)
				if item_data.has("charge_max"):
					wieldable_item.charge_max = item_data.get("charge_max", 0.0)
		
		slot_data = InventorySlotPD.new()
		slot_data.inventory_item = item_to_use
		slot_data.quantity = slot_data_dict.get("quantity", 1)
		slot_data.origin_index = slot_data_dict.get("origin_index", -1)
	else:
		# This should not happen due to checks above, but just in case
		push_error("PickupItemCommand: Failed to deserialize slot_data - item is null after loading")
		return null
	
	var command = PickupItemCommand.new(player_id, slot_data, position, network_id, scene_path)
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	return command
