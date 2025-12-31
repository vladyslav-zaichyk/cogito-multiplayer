extends Command
class_name InteractWithDoorCommand
## Command for interacting with a door (open/close/lock/unlock).
## This command handles the door interaction logic and emits DoorInteractedEvent on success.

## Event class uses class_name for static typing, so we can call it directly

## Path to the door object in the scene
var door_path: String = ""
## Network ID of the door (if available)
var door_network_id: String = ""
## Action to perform: "toggle" (open/close), "lock", "unlock"
var action: String = "toggle"
## Target state (for toggle: true = open, false = close)
var target_state: bool = false


func _init(player_id_value: int, door_node: Node, action_value: String = "toggle", target_state_value: bool = false):
	super._init(player_id_value)
	action = action_value
	target_state = target_state_value
	if door_node and door_node.is_inside_tree():
		door_path = str(door_node.get_path())
		# Try to get network_id from NetworkInteractable component
		for child in door_node.get_children():
			if child.has_method("get") and child.get("network_id") != null:
				door_network_id = child.network_id
				break
	validation_type = ValidationType.HOST_VALIDATION  # Host validates door interactions


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
	
	# Find the door object
	var door: CogitoDoor = null
	if not door_path.is_empty():
		var scene_tree = Engine.get_main_loop() as SceneTree
		if scene_tree and scene_tree.current_scene:
			var door_node = scene_tree.current_scene.get_node_or_null(NodePath(door_path))
			if door_node and door_node is CogitoDoor:
				door = door_node
	
	if not door:
		var error_result = CommandResult.new(false, "Door not found")
		error_result.response_code = CommandResult.ResponseCode.ITEM_NOT_FOUND
		return error_result
	
	var result = CommandResult.new()
	
	# Execute door interaction based on action
	match action:
		"toggle":
			# Toggle door (open/close)
			# If door is locked, check for key first (like lock_interaction does)
			if door.is_locked:
				# Check if player has the key
				var has_key = false
				var has_lockpick = false
				
				if door.key:
					# Use strict typing - CogitoPlayer has inventory_data property
					var inventory: CogitoInventory = player.inventory_data
					if inventory:
						for slot_data in inventory.inventory_slots:
							if slot_data != null and slot_data.inventory_item == door.key:
								has_key = true
								# Remove key if discard_after_use is set
								if slot_data.inventory_item.has_method("discard_after_use"):
									if slot_data.inventory_item.discard_after_use:
										inventory.remove_item_from_stack(slot_data)
								break
				
				if door.lockpick:
					# Use strict typing - CogitoPlayer has inventory_data property
					var inventory: CogitoInventory = player.inventory_data
					if inventory:
						for slot_data in inventory.inventory_slots:
							if slot_data != null and slot_data.inventory_item == door.lockpick:
								has_lockpick = true
								# Remove lockpick if discard_after_use is set
								if slot_data.inventory_item.has_method("discard_after_use"):
									if slot_data.inventory_item.discard_after_use:
										inventory.remove_item_from_stack(slot_data)
								break
				
				# If player has key or lockpick, open door first, then unlock after animation
				if has_key or has_lockpick:
					# Restore old behavior: open door first (with animation), then unlock after animation completes
					# This ensures the unlock sound/state change happens after the opening animation
					if door.has_method("open_then_unlock"):
						door.open_then_unlock(player_interaction_component)
					else:
						# Fallback: open door, then unlock immediately (no animation wait)
						if not door.is_open and door.has_method("open_door"):
							door.open_door(player_interaction_component)
						# Unlock after opening (old behavior was to wait for animation, but fallback does it immediately)
						if door.has_method("unlock_door"):
							door.unlock_door()
				else:
					# No key - show hint (like door_rattle does)
					if door.has_method("door_rattle"):
						door.door_rattle(player_interaction_component)
					else:
						# Fallback: show key hint
						if door.key_hint:
							player_interaction_component.send_hint(null, door.key_hint)
						else:
							player_interaction_component.send_hint(null, tr("DOOR_locked_hint"))
			else:
				# Door is not locked, use normal interact
				if door.has_method("interact"):
					door.interact(player_interaction_component)
				else:
					# Fallback: directly set state
					if "is_open" in door:
						door.is_open = target_state
		"lock":
			if door.has_method("lock_door"):
				door.lock_door()
		"unlock":
			if door.has_method("unlock_door"):
				door.unlock_door()
		_:
			var error_result = CommandResult.new(false, "Unknown door action: %s" % action)
			error_result.response_code = CommandResult.ResponseCode.EXECUTION_FAILED
			return error_result
	
	# Get current state for event
	var is_open = door.is_open if "is_open" in door else false
	var is_locked = door.is_locked if "is_locked" in door else false
	
	# Create event
	var event = DoorInteractedEvent.new(player_id, door_path, door_network_id, action, is_open, is_locked)
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
	
	# Check if door exists
	if door_path.is_empty():
		return false
	
	var scene_tree = Engine.get_main_loop() as SceneTree
	if not scene_tree or not scene_tree.current_scene:
		return false
	
	var door_node = scene_tree.current_scene.get_node_or_null(NodePath(door_path))
	if not door_node or not door_node is CogitoDoor:
		return false
	
	# Validate action
	if action not in ["toggle", "lock", "unlock"]:
		return false
	
	return true


## Serialize command for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	base_data["door_path"] = door_path
	base_data["door_network_id"] = door_network_id
	base_data["action"] = action
	base_data["target_state"] = target_state
	
	return base_data


## Deserialize command from network data
static func deserialize(data: Dictionary) -> Command:
	var player_id = data.get("player_id", -1)
	var path = data.get("door_path", "")
	var network_id = data.get("door_network_id", "")
	var action_value = data.get("action", "toggle")
	var target_state_value = data.get("target_state", false)
	
	# Find door node for initialization
	var door_node: Node = null
	if not path.is_empty():
		var scene_tree = Engine.get_main_loop() as SceneTree
		if scene_tree and scene_tree.current_scene:
			door_node = scene_tree.current_scene.get_node_or_null(NodePath(path))
	
	# Create command (use dummy node if door not found)
	if not door_node:
		door_node = Node.new()
		door_node.name = "DummyDoor"
	
	var command = InteractWithDoorCommand.new(player_id, door_node, action_value, target_state_value)
	command.door_path = path
	command.door_network_id = network_id
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	# Clean up dummy if created
	if door_node.name == "DummyDoor":
		door_node.queue_free()
	
	return command

