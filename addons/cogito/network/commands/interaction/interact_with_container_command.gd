extends Command
class_name InteractWithContainerCommand
## Command for interacting with a container (open/close inventory).
## This command handles the container interaction logic and emits ContainerInteractedEvent on success.

## Event class uses class_name for static typing, so we can call it directly

## Path to the container object in the scene
var container_path: String = ""
## Network ID of the container (if available)
var container_network_id: String = ""


func _init(player_id_value: int, container_node: Node):
	super._init(player_id_value)
	if container_node and container_node.is_inside_tree():
		container_path = str(container_node.get_path())
		# Try to get network_id from NetworkInteractable component
		for child in container_node.get_children():
			if child.has_method("get") and child.get("network_id") != null:
				container_network_id = child.network_id
				break
	validation_type = ValidationType.HOST_VALIDATION  # Host validates container interactions


## Execute the command
func execute() -> CommandResult:
	# Get player with strict typing
	var player: CogitoPlayer = null
	if PlayerManager:
		player = PlayerManager.get_player(player_id) as CogitoPlayer
	
	if not player:
		var error_result = CommandResult.new(false, "Player not found")
		error_result.response_code = CommandResult.ResponseCode.PLAYER_NOT_FOUND
		return error_result
	
	# Use strict typing - CogitoPlayer has player_interaction_component property
	var player_interaction_component: PlayerInteractionComponent = player.player_interaction_component
	if not player_interaction_component:
		var error_result = CommandResult.new(false, "Player interaction component not found")
		error_result.response_code = CommandResult.ResponseCode.PLAYER_NOT_FOUND
		return error_result
	
	# Find the container object
	var container: CogitoContainer = null
	if not container_path.is_empty():
		var scene_tree = Engine.get_main_loop() as SceneTree
		if scene_tree and scene_tree.current_scene:
			var container_node = scene_tree.current_scene.get_node_or_null(NodePath(container_path))
			if container_node and container_node is CogitoContainer:
				container = container_node
	
	if not container:
		var error_result = CommandResult.new(false, "Container not found")
		error_result.response_code = CommandResult.ResponseCode.ITEM_NOT_FOUND
		return error_result
	
	var result = CommandResult.new()
	
	# Execute container interaction
	if container.has_method("interact"):
		container.interact(player_interaction_component)
	
	# Get current state for event (check if inventory is open by checking interaction text)
	# CogitoContainer has interaction_text and text_when_open properties - use strict typing
	var is_open = false
	if container.interaction_text == tr(container.text_when_open):
		is_open = true
	
	# Create event
	var event = ContainerInteractedEvent.new(player_id, container_path, container_network_id, is_open)
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
	
	# Check if container exists
	if container_path.is_empty():
		return false
	
	var scene_tree = Engine.get_main_loop() as SceneTree
	if not scene_tree or not scene_tree.current_scene:
		return false
	
	var container_node = scene_tree.current_scene.get_node_or_null(NodePath(container_path))
	if not container_node or not container_node is CogitoContainer:
		return false
	
	return true


## Serialize command for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	base_data["container_path"] = container_path
	base_data["container_network_id"] = container_network_id
	
	return base_data


## Deserialize command from network data
static func deserialize(data: Dictionary) -> Command:
	var player_id = data.get("player_id", -1)
	var path = data.get("container_path", "")
	var network_id = data.get("container_network_id", "")
	
	# Find container node for initialization
	var container_node: Node = null
	if not path.is_empty():
		var scene_tree = Engine.get_main_loop() as SceneTree
		if scene_tree and scene_tree.current_scene:
			container_node = scene_tree.current_scene.get_node_or_null(NodePath(path))
	
	# Create command (use dummy node if container not found)
	if not container_node:
		container_node = Node.new()
		container_node.name = "DummyContainer"
	
	var command = InteractWithContainerCommand.new(player_id, container_node)
	command.container_path = path
	command.container_network_id = network_id
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	# Clean up dummy if created
	if container_node.name == "DummyContainer":
		container_node.queue_free()
	
	return command
