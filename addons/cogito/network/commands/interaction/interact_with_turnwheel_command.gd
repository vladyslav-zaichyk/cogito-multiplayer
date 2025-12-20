extends Command
class_name InteractWithTurnwheelCommand
## Command for interacting with a turnwheel (press-and-hold interaction).
## This command handles the turnwheel interaction logic and emits TurnwheelInteractedEvent on success.

var turnwheel_path: String = ""
var turnwheel_network_id: String = ""
var interaction_type: String = "complete"  # "start" or "complete"
var has_been_turned: bool = false


func _init(player_id_value: int, turnwheel_node: Node, interaction_type_value: String = "complete"):
	super._init(player_id_value)
	interaction_type = interaction_type_value
	if turnwheel_node and turnwheel_node.is_inside_tree():
		turnwheel_path = str(turnwheel_node.get_path())
		# Try to get network_id from NetworkInteractable component
		for child in turnwheel_node.get_children():
			if child.has_method("get") and child.get("network_id") != null:
				turnwheel_network_id = child.network_id
				break
	validation_type = ValidationType.HOST_VALIDATION


func execute() -> CommandResult:
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
	
	var turnwheel: CogitoTurnwheel = null
	if not turnwheel_path.is_empty():
		var scene_tree = Engine.get_main_loop() as SceneTree
		if scene_tree and scene_tree.current_scene:
			var turnwheel_node = scene_tree.current_scene.get_node_or_null(NodePath(turnwheel_path))
			if turnwheel_node and turnwheel_node is CogitoTurnwheel:
				turnwheel = turnwheel_node
	
	if not turnwheel:
		var error_result = CommandResult.new(false, "Turnwheel not found")
		error_result.response_code = CommandResult.ResponseCode.ITEM_NOT_FOUND
		return error_result
	
	var result = CommandResult.new()
	
	match interaction_type:
		"start":
			print("[TURNWHEEL DEBUG] Command execute: start - is_currently_turning=%s" % turnwheel.is_currently_turning)
			# Start visual rotation - this will be replicated on all clients via event
			if not turnwheel.is_currently_turning:
				if turnwheel.has_method("start_visual_rotation"):
					turnwheel.start_visual_rotation()
				else:
					# Fallback if method doesn't exist
					if turnwheel.has_signal("turnwheel_interaction_started"):
						turnwheel.turnwheel_interaction_started.emit()
					if turnwheel.audio_stream_player_3d and not turnwheel.audio_stream_player_3d.playing:
						turnwheel.audio_stream_player_3d.play()
					turnwheel.is_currently_turning = true
				print("[TURNWHEEL DEBUG] Command execute: start - visual rotation started")
			else:
				print("[TURNWHEEL DEBUG] Command execute: start - already turning, skipping")
		
		"stop":
			print("[TURNWHEEL DEBUG] Command execute: stop - is_currently_turning=%s" % turnwheel.is_currently_turning)
			# Stop visual rotation - this will be replicated on all clients via event
			# This is called when hold is cancelled early (before completion)
			if turnwheel.has_method("stop_visual_rotation"):
				turnwheel.stop_visual_rotation()
			else:
				# Fallback if method doesn't exist
				if turnwheel.audio_stream_player_3d:
					turnwheel.audio_stream_player_3d.stop()
				turnwheel.is_currently_turning = false
				if turnwheel.has_signal("turnwheel_interaction_stopped"):
					turnwheel.turnwheel_interaction_stopped.emit()
			print("[TURNWHEEL DEBUG] Command execute: stop - visual rotation stopped")
			# Don't change has_been_turned state - this is just visual cancellation
			has_been_turned = turnwheel.has_been_turned if "has_been_turned" in turnwheel else false
		
		"complete":
			print("[TURNWHEEL DEBUG] Command execute: complete - is_currently_turning=%s" % turnwheel.is_currently_turning)
			# Complete turning - execute logic only for the player who turned it
			# Visual replication will happen on remote clients via event
			if turnwheel.has_method("complete_interaction"):
				turnwheel.complete_interaction()
			elif turnwheel.has_method("interact"):
				# Fallback if method doesn't exist
				turnwheel.interact(player_interaction_component, true)
			
			# Get current state for event
			has_been_turned = turnwheel.has_been_turned if "has_been_turned" in turnwheel else false
			print("[TURNWHEEL DEBUG] Command execute: complete - has_been_turned=%s" % has_been_turned)
		
		_:
			var error_result = CommandResult.new(false, "Unknown interaction type: %s" % interaction_type)
			error_result.response_code = CommandResult.ResponseCode.EXECUTION_FAILED
			return error_result
	
	# Create event
	var event = TurnwheelInteractedEvent.new(player_id, turnwheel_path, turnwheel_network_id, interaction_type, has_been_turned)
	result.add_event(event)
	result.success = true
	
	return result


func validate() -> bool:
	if not PlayerManager:
		return false
	
	var player = PlayerManager.get_player(player_id)
	if not player:
		return false
	
	if turnwheel_path.is_empty():
		return false
	
	var scene_tree = Engine.get_main_loop() as SceneTree
	if not scene_tree or not scene_tree.current_scene:
		return false
	
	var turnwheel_node = scene_tree.current_scene.get_node_or_null(NodePath(turnwheel_path))
	if not turnwheel_node or not turnwheel_node is CogitoTurnwheel:
		return false
	
	if interaction_type not in ["start", "stop", "complete"]:
		return false
	
	return true


func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	base_data["turnwheel_path"] = turnwheel_path
	base_data["turnwheel_network_id"] = turnwheel_network_id
	base_data["interaction_type"] = interaction_type
	base_data["has_been_turned"] = has_been_turned
	
	return base_data


static func deserialize(data: Dictionary) -> Command:
	var player_id = data.get("player_id", -1)
	var path = data.get("turnwheel_path", "")
	var network_id = data.get("turnwheel_network_id", "")
	var interaction_type_value = data.get("interaction_type", "complete")
	
	var turnwheel_node: Node = null
	if not path.is_empty():
		var scene_tree = Engine.get_main_loop() as SceneTree
		if scene_tree and scene_tree.current_scene:
			turnwheel_node = scene_tree.current_scene.get_node_or_null(NodePath(path))
	
	if not turnwheel_node:
		turnwheel_node = Node.new()
		turnwheel_node.name = "DummyTurnwheel"
	
	var command = InteractWithTurnwheelCommand.new(player_id, turnwheel_node, interaction_type_value)
	command.turnwheel_path = path
	command.turnwheel_network_id = network_id
	command.has_been_turned = data.get("has_been_turned", false)
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	if turnwheel_node.name == "DummyTurnwheel":
		turnwheel_node.queue_free()
	
	return command
