extends Command
class_name WieldableActionCommand
## Command for performing a wieldable action (primary or secondary).
## This command handles the action logic and emits WieldableActionEvent on success.

## Event class uses class_name for static typing, so we can call it directly

enum ActionType { PRIMARY, SECONDARY }
var action_type: ActionType
var is_released: bool


func _init(player_id_value: int, action_type_value: ActionType, is_released_value: bool = false):
	super._init(player_id_value)
	action_type = action_type_value
	is_released = is_released_value
	validation_type = ValidationType.CLIENT_VALIDATION  # Client validates actions (can be changed to HOST_VALIDATION for combat)


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
	
	# Use strict typing - CogitoPlayer has player_interaction_component property
	var player_interaction_component: PlayerInteractionComponent = player.player_interaction_component
	if not player_interaction_component:
		var error_result = CommandResult.new(false, "Player interaction component not found")
		error_result.response_code = CommandResult.ResponseCode.EXECUTION_FAILED
		return error_result
	
	# Check if player is changing wieldables
	if player_interaction_component.is_changing_wieldables:
		var error_result = CommandResult.new(false, "Player is changing wieldables")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	# Check if player has a wieldable equipped
	if not player_interaction_component.equipped_wieldable_node:
		var error_result = CommandResult.new(false, "No wieldable equipped")
		error_result.response_code = CommandResult.ResponseCode.ITEM_NOT_FOUND
		return error_result
	
	if not player_interaction_component.equipped_wieldable_item:
		var error_result = CommandResult.new(false, "No wieldable item reference")
		error_result.response_code = CommandResult.ResponseCode.ITEM_NOT_FOUND
		return error_result
	
	var result = CommandResult.new()
	
	# Execute action based on type
	if action_type == ActionType.PRIMARY:
		player_interaction_component.equipped_wieldable_node.action_primary(
			player_interaction_component.equipped_wieldable_item,
			is_released
		)
	else:  # SECONDARY
		player_interaction_component.equipped_wieldable_node.action_secondary(is_released)
	
	# Create event (convert ActionType enum)
	var event_action_type = WieldableActionEvent.ActionType.PRIMARY if action_type == ActionType.PRIMARY else WieldableActionEvent.ActionType.SECONDARY
	var event = WieldableActionEvent.new(
		player_id,
		event_action_type,
		is_released,
		player_interaction_component.equipped_wieldable_item
	)
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
	
	# Use strict typing - CogitoPlayer has player_interaction_component property
	var player_interaction_component: PlayerInteractionComponent = player.player_interaction_component
	if not player_interaction_component:
		return false
	
	# Check if player is changing wieldables
	if player_interaction_component.is_changing_wieldables:
		return false
	
	# Check if player has a wieldable equipped
	if not player_interaction_component.equipped_wieldable_node:
		return false
	
	if not player_interaction_component.equipped_wieldable_item:
		return false
	
	return true


## Serialize command for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	base_data["action_type"] = ActionType.keys()[action_type]
	base_data["is_released"] = is_released
	return base_data


## Deserialize command from network data
static func deserialize(data: Dictionary) -> Command:
	var player_id = data.get("player_id", -1)
	var action_type_str = data.get("action_type", "PRIMARY")
	var is_released = data.get("is_released", false)
	
	var action_type = ActionType.PRIMARY
	if action_type_str == "SECONDARY":
		action_type = ActionType.SECONDARY
	
	var command = WieldableActionCommand.new(player_id, action_type, is_released)
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	return command

