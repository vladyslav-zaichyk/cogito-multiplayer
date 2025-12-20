extends Command
class_name StartCarryingCommand
## Command for starting to carry an object.
## This command handles the carry logic and emits CarryingStartedEvent on success.

## Event class uses class_name for static typing, so we can call it directly

## Reference to the carryable component (for identification)
## Note: We serialize the parent object's path and network ID instead of the component itself
var carryable_parent_path: String = ""
var carryable_network_id: int = -1
var carryable_position: Vector3 = Vector3.ZERO


func _init(player_id_value: int, carryable_component: CogitoCarryableComponent):
	super._init(player_id_value)
	if carryable_component:
		var parent_obj = carryable_component.get_parent()
		if parent_obj and parent_obj.is_inside_tree():
			carryable_parent_path = str(parent_obj.get_path())
			carryable_position = parent_obj.global_position if parent_obj is Node3D else Vector3.ZERO
			
			# Try to get network_id from NetworkPickupID component
			for child in parent_obj.get_children():
				if child.has_method("get_network_id"):
					carryable_network_id = child.get_network_id()
					break
	validation_type = ValidationType.CLIENT_VALIDATION  # Client validates carrying (can be changed to HOST_VALIDATION if needed)


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
	
	# Check if player is already carrying something
	if player_interaction_component.is_carrying:
		var error_result = CommandResult.new(false, "Player is already carrying an object")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	# Check if player is wielding (and if carryable allows carrying while wielding)
	# Note: This check is done in carryable_component.carry(), but we validate here too
	if player_interaction_component.is_wielding:
		# We'll let the carryable component handle the check
		pass
	
	# Find the carryable component
	# Note: Commands don't have direct access to scene tree, so we use Engine to get it
	var carryable_component: CogitoCarryableComponent = null
	if not carryable_parent_path.is_empty():
		var scene_tree = Engine.get_main_loop() as SceneTree
		if scene_tree and scene_tree.current_scene:
			var scene_root = scene_tree.current_scene
			var parent_node = scene_root.get_node_or_null(NodePath(carryable_parent_path))
			if parent_node:
				# Find CogitoCarryableComponent in children
				for child in parent_node.get_children():
					if child is CogitoCarryableComponent:
						carryable_component = child
						break
	
	if not carryable_component:
		var error_result = CommandResult.new(false, "Carryable component not found")
		error_result.response_code = CommandResult.ResponseCode.ITEM_NOT_FOUND
		return error_result
	
	# Check if already being carried
	if carryable_component.is_being_carried:
		var error_result = CommandResult.new(false, "Object is already being carried")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	var result = CommandResult.new()
	
	# Execute carry logic (call hold() which calls start_carrying)
	carryable_component.hold()
	
	# Create event (using class_name for static typing)
	var event = CarryingStartedEvent.new(player_id, carryable_parent_path, carryable_network_id, carryable_position)
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
	
	# Check if player is already carrying something
	if player_interaction_component.is_carrying:
		return false
	
	# Check if carryable component exists
	if carryable_parent_path.is_empty():
		return false
	
	var scene_tree = Engine.get_main_loop() as SceneTree
	if not scene_tree or not scene_tree.current_scene:
		return false
	
	var scene_root = scene_tree.current_scene
	var parent_node = scene_root.get_node_or_null(NodePath(carryable_parent_path))
	if not parent_node:
		return false
	
	# Check if carryable component exists
	var carryable_component: CogitoCarryableComponent = null
	for child in parent_node.get_children():
		if child is CogitoCarryableComponent:
			carryable_component = child
			break
	
	if not carryable_component:
		return false
	
	# Check if already being carried
	if carryable_component.is_being_carried:
		return false
	
	return true


## Serialize command for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	base_data["carryable_parent_path"] = carryable_parent_path
	base_data["carryable_network_id"] = carryable_network_id
	base_data["carryable_position"] = {
		"x": carryable_position.x,
		"y": carryable_position.y,
		"z": carryable_position.z
	}
	
	return base_data


## Deserialize command from network data
static func deserialize(data: Dictionary) -> Command:
	var player_id = data.get("player_id", -1)
	var parent_path = data.get("carryable_parent_path", "")
	var network_id = data.get("carryable_network_id", -1)
	var position_data = data.get("carryable_position", {})
	
	# Reconstruct position
	var position = Vector3(
		position_data.get("x", 0.0),
		position_data.get("y", 0.0),
		position_data.get("z", 0.0)
	)
	
	# Create a dummy carryable component for deserialization
	# We'll find the actual component in execute()
	var dummy_component = CogitoCarryableComponent.new()
	var command = StartCarryingCommand.new(player_id, dummy_component)
	command.carryable_parent_path = parent_path
	command.carryable_network_id = network_id
	command.carryable_position = position
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	# Clean up dummy
	dummy_component.queue_free()
	
	return command

