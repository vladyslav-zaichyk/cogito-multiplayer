extends Command
class_name StopCarryingCommand
## Command for stopping to carry an object.
## This command handles the stop carry logic and emits CarryingStoppedEvent on success.

## Preload event class for static typing
const CarryingStoppedEvent = preload("res://addons/cogito/network/commands/events/carrying_stopped_event.gd")

## Reference to the carryable component (for identification)
## Note: We serialize the parent object's path and network ID instead of the component itself
var carryable_parent_path: String = ""
var carryable_network_id: int = -1
var drop_force: float = 0.0  # Force applied when dropping (for throw vs drop)


func _init(player_id_value: int, carryable_component: CogitoCarryableComponent = null, drop_force_value: float = 0.0):
	super._init(player_id_value)
	drop_force = drop_force_value
	if carryable_component:
		var parent_obj = carryable_component.get_parent()
		if parent_obj and parent_obj.is_inside_tree():
			carryable_parent_path = str(parent_obj.get_path())
			
			# Try to get network_id from NetworkPickupID component
			for child in parent_obj.get_children():
				if child.has_method("get_network_id"):
					carryable_network_id = child.get_network_id()
					break
	validation_type = ValidationType.CLIENT_VALIDATION  # Client validates stopping carry


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
		error_result.response_code = CommandResult.ResponseCode.PLAYER_NOT_FOUND
		return error_result
	
	# Check if player is carrying something
	if not player_interaction_component.is_carrying:
		var error_result = CommandResult.new(false, "Player is not carrying an object")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	# Get the carried object
	var carried_object = player_interaction_component.carried_object
	if not carried_object or not is_instance_valid(carried_object):
		var error_result = CommandResult.new(false, "Carried object is invalid")
		error_result.response_code = CommandResult.ResponseCode.ITEM_NOT_FOUND
		return error_result
	
	# Get parent object for path and network ID
	var parent_obj = carried_object.get_parent()
	if parent_obj and parent_obj.is_inside_tree():
		carryable_parent_path = str(parent_obj.get_path())
		
		# Try to get network_id from NetworkPickupID component
		for child in parent_obj.get_children():
			if child.has_method("get_network_id"):
				carryable_network_id = child.get_network_id()
				break
	
	var result = CommandResult.new()
	
	# Execute stop carry logic (call leave() which calls stop_carrying)
	# If drop_force > 0, it's a throw, otherwise it's a drop
	if drop_force > 0.0:
		# Throw the object
		carried_object.throw(drop_force)
	else:
		# Just drop (leave)
		carried_object.leave()
	
	# Create event
	var event = CarryingStoppedEvent.new(player_id, carryable_parent_path, carryable_network_id, drop_force)
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
	
	# Check if player is carrying something
	if not player_interaction_component.is_carrying:
		return false
	
	# Check if carried object is valid
	var carried_object = player_interaction_component.carried_object
	if not carried_object or not is_instance_valid(carried_object):
		return false
	
	return true


## Serialize command for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	base_data["carryable_parent_path"] = carryable_parent_path
	base_data["carryable_network_id"] = carryable_network_id
	base_data["drop_force"] = drop_force
	
	return base_data


## Deserialize command from network data
static func deserialize(data: Dictionary) -> Command:
	var player_id = data.get("player_id", -1)
	var parent_path = data.get("carryable_parent_path", "")
	var network_id = data.get("carryable_network_id", -1)
	var drop_force_value = data.get("drop_force", 0.0)
	
	# Create a dummy carryable component for deserialization
	# We'll find the actual component in execute()
	var dummy_component = CogitoCarryableComponent.new()
	var command = StopCarryingCommand.new(player_id, dummy_component, drop_force_value)
	command.carryable_parent_path = parent_path
	command.carryable_network_id = network_id
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	# Clean up dummy
	dummy_component.queue_free()
	
	return command

