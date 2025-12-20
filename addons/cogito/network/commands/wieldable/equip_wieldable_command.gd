extends Command
class_name EquipWieldableCommand
## Command for equipping a wieldable item.
## This command handles the equip logic and emits WieldableEquippedEvent on success.

## Preload event class for static typing
const WieldableEquippedEvent = preload("res://addons/cogito/network/commands/events/wieldable_equipped_event.gd")

## Wieldable item to equip
var wieldable_item: WieldableItemPD
## Inventory slot index where the wieldable is located
var slot_index: int = -1


func _init(player_id_value: int, wieldable_value: WieldableItemPD, slot_index_value: int = -1):
	super._init(player_id_value)
	wieldable_item = wieldable_value
	slot_index = slot_index_value
	validation_type = ValidationType.CLIENT_VALIDATION  # Client validates wieldable equip (can be changed to HOST_VALIDATION if needed)


## Execute the command
func execute() -> CommandResult:
	# Get player
	var player = null
	if PlayerManager:
		player = PlayerManager.get_player(player_id)
	
	if not player:
		var error_result = CommandResult.new(false, "Player not found")
		error_result.response_code = CommandResult.ResponseCode.PLAYER_NOT_FOUND
		return error_result
	
	var player_interaction_component = player.player_interaction_component if "player_interaction_component" in player else null
	if not player_interaction_component:
		var error_result = CommandResult.new(false, "Player interaction component not found")
		error_result.response_code = CommandResult.ResponseCode.EXECUTION_FAILED
		return error_result
	
	# Check if player is carrying something (can't equip while carrying)
	if player_interaction_component.carried_object != null:
		var error_result = CommandResult.new(false, "Can't equip item while carrying")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	# Check if wieldable is already being wielded
	if wieldable_item.is_being_wielded:
		var error_result = CommandResult.new(false, "Wieldable is already being wielded")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	# Check if player is currently changing wieldables
	if player_interaction_component.is_changing_wieldables:
		var error_result = CommandResult.new(false, "Player is already changing wieldables")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	var result = CommandResult.new()
	
	# Execute equip logic (similar to WieldableItemPD.take_out())
	wieldable_item.is_being_wielded = true
	wieldable_item.update_wieldable_data(player_interaction_component)
	player_interaction_component.change_wieldable_to(wieldable_item)
	
	# Create event
	var event = WieldableEquippedEvent.new(player_id, wieldable_item, slot_index)
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
	
	var player_interaction_component = player.player_interaction_component if "player_interaction_component" in player else null
	if not player_interaction_component:
		return false
	
	# Check if player is carrying something
	if player_interaction_component.carried_object != null:
		return false
	
	# Check if wieldable is already being wielded
	if wieldable_item.is_being_wielded:
		return false
	
	# Check if player is currently changing wieldables
	if player_interaction_component.is_changing_wieldables:
		return false
	
	return true


## Serialize command for network transmission
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


## Deserialize command from network data
static func deserialize(data: Dictionary) -> Command:
	var player_id = data.get("player_id", -1)
	var item_data = data.get("wieldable_item", {})
	var slot_index = data.get("slot_index", -1)
	
	# Try to load wieldable from resource path
	var wieldable: WieldableItemPD = null
	if item_data.has("resource_path") and not item_data.resource_path.is_empty():
		wieldable = load(item_data.resource_path) as WieldableItemPD
		if wieldable:
			# Restore charge state
			wieldable.charge_current = item_data.get("charge_current", 0.0)
			wieldable.charge_max = item_data.get("charge_max", 0.0)
	
	if not wieldable:
		push_error("EquipWieldableCommand: Failed to deserialize wieldable_item")
		return null
	
	var command = EquipWieldableCommand.new(player_id, wieldable, slot_index)
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	return command
