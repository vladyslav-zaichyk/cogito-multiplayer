extends Command
class_name InteractWithSwitchCommand
## Command for interacting with a switch (toggle on/off).
## This command handles the switch interaction logic and emits SwitchInteractedEvent on success.

## Event class uses class_name for static typing, so we can call it directly

## Path to the switch object in the scene
var switch_path: String = ""
## Network ID of the switch (if available)
var switch_network_id: String = ""


func _init(player_id_value: int, switch_node: Node):
	super._init(player_id_value)
	if switch_node and switch_node.is_inside_tree():
		switch_path = str(switch_node.get_path())
		# Try to get network_id from NetworkInteractable component
		for child in switch_node.get_children():
			if child.has_method("get") and child.get("network_id") != null:
				switch_network_id = child.network_id
				break
	validation_type = ValidationType.HOST_VALIDATION  # Host validates switch interactions


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
	
	# Find the switch object
	var switch: CogitoSwitch = null
	if not switch_path.is_empty():
		var scene_tree = Engine.get_main_loop() as SceneTree
		if scene_tree and scene_tree.current_scene:
			var switch_node = scene_tree.current_scene.get_node_or_null(NodePath(switch_path))
			if switch_node and switch_node is CogitoSwitch:
				switch = switch_node
	
	if not switch:
		var error_result = CommandResult.new(false, "Switch not found")
		error_result.response_code = CommandResult.ResponseCode.ITEM_NOT_FOUND
		return error_result
	
	var result = CommandResult.new()
	
	# Execute switch interaction
	if switch.has_method("interact"):
		switch.interact(player_interaction_component)
	
	# Get current state for event
	var is_on = switch.is_on if "is_on" in switch else false
	
	# Create event
	var event = SwitchInteractedEvent.new(player_id, switch_path, switch_network_id, is_on)
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
	
	# Check if switch exists
	if switch_path.is_empty():
		return false
	
	var scene_tree = Engine.get_main_loop() as SceneTree
	if not scene_tree or not scene_tree.current_scene:
		return false
	
	var switch_node = scene_tree.current_scene.get_node_or_null(NodePath(switch_path))
	if not switch_node or not switch_node is CogitoSwitch:
		return false
	
	return true


## Serialize command for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	base_data["switch_path"] = switch_path
	base_data["switch_network_id"] = switch_network_id
	
	return base_data


## Deserialize command from network data
static func deserialize(data: Dictionary) -> Command:
	var player_id = data.get("player_id", -1)
	var path = data.get("switch_path", "")
	var network_id = data.get("switch_network_id", "")
	
	# Find switch node for initialization
	var switch_node: Node = null
	if not path.is_empty():
		var scene_tree = Engine.get_main_loop() as SceneTree
		if scene_tree and scene_tree.current_scene:
			switch_node = scene_tree.current_scene.get_node_or_null(NodePath(path))
	
	# Create command (use dummy node if switch not found)
	if not switch_node:
		switch_node = Node.new()
		switch_node.name = "DummySwitch"
	
	var command = InteractWithSwitchCommand.new(player_id, switch_node)
	command.switch_path = path
	command.switch_network_id = network_id
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	# Clean up dummy if created
	if switch_node.name == "DummySwitch":
		switch_node.queue_free()
	
	return command

