extends Command
class_name UnequipWieldableCommand
## Command for unequipping a wieldable item.
## This command handles the unequip logic and emits WieldableUnequippedEvent on success.

## Preload event class for static typing
const WieldableUnequippedEvent = preload("res://addons/cogito/network/commands/events/wieldable_unequipped_event.gd")

## Wieldable item to unequip (can be null if unequipping current wieldable)
var wieldable_item: WieldableItemPD


func _init(player_id_value: int, wieldable_value: WieldableItemPD = null):
	super._init(player_id_value)
	wieldable_item = wieldable_value
	validation_type = ValidationType.CLIENT_VALIDATION  # Client validates wieldable unequip


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
	
	# If wieldable_item is null, unequip current wieldable
	if not wieldable_item:
		wieldable_item = player_interaction_component.equipped_wieldable_item
	
	# Check if there's a wieldable to unequip
	if not wieldable_item:
		var error_result = CommandResult.new(false, "No wieldable to unequip")
		error_result.response_code = CommandResult.ResponseCode.ITEM_NOT_FOUND
		return error_result
	
	# Check if wieldable is actually being wielded
	if not wieldable_item.is_being_wielded:
		var error_result = CommandResult.new(false, "Wieldable is not being wielded")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	# Check if player is currently changing wieldables
	if player_interaction_component.is_changing_wieldables:
		var error_result = CommandResult.new(false, "Player is already changing wieldables")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	var result = CommandResult.new()
	
	# Execute unequip logic (similar to WieldableItemPD.put_away())
	wieldable_item.is_being_wielded = false
	wieldable_item.update_wieldable_data(player_interaction_component)
	player_interaction_component.change_wieldable_to(null)
	
	# Create event
	var event = WieldableUnequippedEvent.new(player_id, wieldable_item)
	result.add_event(event)
	result.success = true
	
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
	
	# If wieldable_item is null, check if there's a current wieldable
	if not wieldable_item:
		if not player_interaction_component.equipped_wieldable_item:
			return false
		wieldable_item = player_interaction_component.equipped_wieldable_item
	
	# Check if wieldable is actually being wielded
	if not wieldable_item.is_being_wielded:
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
			"item_type": wieldable_item.get_script().get_path().get_file().get_basename() if wieldable_item.get_script() else ""
		}
	
	base_data["wieldable_item"] = item_data
	return base_data


## Deserialize command from network data
static func deserialize(data: Dictionary) -> Command:
	var player_id = data.get("player_id", -1)
	var item_data = data.get("wieldable_item", {})
	
	# Try to load wieldable from resource path
	var wieldable: WieldableItemPD = null
	if item_data.has("resource_path") and not item_data.resource_path.is_empty():
		wieldable = load(item_data.resource_path) as WieldableItemPD
	
	var command = UnequipWieldableCommand.new(player_id, wieldable)
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	return command

