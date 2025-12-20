extends Command
class_name DropItemCommand
## Command for dropping an item from inventory to the world.
## This command handles the drop logic and emits ItemDroppedEvent on success.

## Slot data of the item to drop
var slot_data: InventorySlotPD
## Inventory slot index from which item is dropped
var slot_index: int = -1
## Position where item should be dropped (calculated by UI)
var drop_position: Vector3


func _init(player_id_value: int, slot_data_value: InventorySlotPD, slot_index_value: int, position_value: Vector3):
	super._init(player_id_value)
	slot_data = slot_data_value
	slot_index = slot_index_value
	drop_position = position_value
	validation_type = ValidationType.HOST_VALIDATION  # Host validates item drops


## Execute the command
func execute() -> CommandResult:
	var result = CommandResult.new()
	
	# Get player
	var player = null
	if PlayerManager:
		player = PlayerManager.get_player(player_id)
	
	if not player or not player.inventory_data:
		var error_result = CommandResult.new(false, "Player or inventory not found")
		error_result.response_code = CommandResult.ResponseCode.PLAYER_NOT_FOUND
		return error_result
	
	# Check if item is droppable
	if not slot_data or not slot_data.inventory_item:
		var error_result = CommandResult.new(false, "Invalid slot data")
		error_result.response_code = CommandResult.ResponseCode.ITEM_NOT_FOUND
		return error_result
	
	if not slot_data.inventory_item.is_droppable:
		var error_result = CommandResult.new(false, "Item is not droppable")
		error_result.response_code = CommandResult.ResponseCode.EXECUTION_FAILED
		return error_result
	
	# Check if item is being wielded
	if slot_data.inventory_item.has_method("update_wieldable_data") and slot_data.inventory_item.is_being_wielded:
		var error_result = CommandResult.new(false, "Cannot drop item while wielding it")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	# Note: The actual drop logic (spawning in world) is handled by inventory_interface._drop_item()
	# This command handles event emission for network synchronization
	# When dropping from UI, the item is already in grabbed_slot_data (not in inventory)
	# The UI handles quantity reduction and removal from grabbed_slot_data
	
	# Create event
	var event = ItemDroppedEvent.new(player_id, slot_data.inventory_item, slot_data, drop_position)
	result.add_event(event)
	result.success = true
	result.data["slot_index"] = slot_index
	
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
	
	# Check if slot data is valid
	if not slot_data or not slot_data.inventory_item:
		return false
	
	# Check if item is droppable
	if not slot_data.inventory_item.is_droppable:
		return false
	
	# Check if item is being wielded
	if slot_data.inventory_item.has_method("update_wieldable_data") and slot_data.inventory_item.is_being_wielded:
		return false
	
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
	base_data["slot_index"] = slot_index
	base_data["drop_position"] = {
		"x": drop_position.x,
		"y": drop_position.y,
		"z": drop_position.z
	}
	
	return base_data


## Deserialize command from network data
static func deserialize(data: Dictionary) -> Command:
	var player_id = data.get("player_id", -1)
	var slot_data_dict = data.get("slot_data", {})
	var slot_index = data.get("slot_index", -1)
	var position_data = data.get("drop_position", {})
	
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
		push_error("DropItemCommand: Failed to deserialize slot_data")
		return null
	
	var command = DropItemCommand.new(player_id, slot_data, slot_index, position)
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	return command
