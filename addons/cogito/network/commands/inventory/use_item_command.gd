extends Command
class_name UseItemCommand
## Command for using an item from inventory.
## This command handles the use logic and emits ItemUsedEvent on success.

## Preload event class for static typing
const ItemUsedEvent = preload("res://addons/cogito/network/commands/events/item_used_event.gd")

## Inventory slot index of the item to use
var slot_index: int = -1


func _init(player_id_value: int, slot_index_value: int):
	super._init(player_id_value)
	slot_index = slot_index_value
	validation_type = ValidationType.CLIENT_VALIDATION  # Client validates item usage (can be changed to HOST_VALIDATION if needed)


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
	
	# Check if slot index is valid
	if slot_index < 0 or slot_index >= player.inventory_data.inventory_slots.size():
		var error_result = CommandResult.new(false, "Invalid slot index")
		error_result.response_code = CommandResult.ResponseCode.EXECUTION_FAILED
		return error_result
	
	var slot_data = player.inventory_data.inventory_slots[slot_index]
	if not slot_data or not slot_data.inventory_item:
		var error_result = CommandResult.new(false, "Slot is empty")
		error_result.response_code = CommandResult.ResponseCode.ITEM_NOT_FOUND
		return error_result
	
	# Use the item directly (don't call use_slot_data to avoid recursion)
	var use_successful: bool = slot_data.inventory_item.use(player.inventory_data.owner)
	
	if not use_successful:
		var error_result = CommandResult.new(false, "Failed to use item")
		error_result.response_code = CommandResult.ResponseCode.EXECUTION_FAILED
		return error_result
	
	# Handle consumable logic
	if slot_data.inventory_item.has_method("is_consumable") and slot_data.inventory_item.is_consumable():
		slot_data.quantity -= 1
		if slot_data.quantity < 1:
			player.inventory_data.null_out_slots(slot_data)
	player.inventory_data._emit_inventory_updated()
	
	# Create event
	var event = ItemUsedEvent.new(player_id, slot_data.inventory_item, slot_index)
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
	
	# Check if slot index is valid
	if slot_index < 0 or slot_index >= player.inventory_data.inventory_slots.size():
		return false
	
	var slot_data = player.inventory_data.inventory_slots[slot_index]
	if not slot_data or not slot_data.inventory_item:
		return false
	
	# Check if item can be used
	if not slot_data.inventory_item.has_method("use"):
		return false
	
	return true


## Serialize command for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	base_data["slot_index"] = slot_index
	return base_data


## Deserialize command from network data
static func deserialize(data: Dictionary) -> Command:
	var player_id = data.get("player_id", -1)
	var slot_index = data.get("slot_index", -1)
	
	var command = UseItemCommand.new(player_id, slot_index)
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	return command

