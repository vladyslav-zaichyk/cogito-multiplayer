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
	var result = CommandResult.new()
	
	# Get player's inventory
	var player = null
	if PlayerManager:
		player = PlayerManager.get_player(player_id)
	
	if not player or not player.inventory_data:
		return CommandResult.new(false, "Player or inventory not found")
	
	# Try to pick up the item (call existing method)
	var success = player.inventory_data.pick_up_slot_data(slot_data)
	
	if success:
		# Create event
		var event = ItemPickedEvent.new(player_id, slot_data.inventory_item, slot_data)
		result.add_event(event)
		result.success = true
		result.data["slot_index"] = slot_data.origin_index
	else:
		result.success = false
		result.error_message = "Failed to pick up item (inventory full or other error)"
	
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
			slot_data_dict["item"] = {
				"name": slot_data.inventory_item.name,
				"resource_path": slot_data.inventory_item.resource_path if slot_data.inventory_item.resource_path else "",
				"item_type": slot_data.inventory_item.get_script().get_path().get_file().get_basename() if slot_data.inventory_item.get_script() else ""
			}
	
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
		if item_data.has("resource_path") and not item_data.resource_path.is_empty():
			item = load(item_data.resource_path) as InventoryItemPD
	
	# Create slot data
	var slot_data: InventorySlotPD = null
	if item:
		slot_data = InventorySlotPD.new()
		slot_data.inventory_item = item
		slot_data.quantity = slot_data_dict.get("quantity", 1)
		slot_data.origin_index = slot_data_dict.get("origin_index", -1)
	
	if not slot_data:
		push_error("PickupItemCommand: Failed to deserialize slot_data")
		return null
	
	var command = PickupItemCommand.new(player_id, slot_data, position, network_id, scene_path)
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	return command

