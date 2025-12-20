class_name UiHoldComponent
extends Control

## Buffer time until the hold is first registered, prevents showing Hold UI for presses
@export var buffer_time: float = 0.1
@export var prompt_area: VBoxContainer

@onready var progress_wheel: CogitoProgressWheel = $ProgressWheel
@onready var hold_timer: Timer = $HoldTimer

var hold_interaction: HoldInteraction
var is_holding: bool = false
var player_interaction_component


func _ready() -> void:
	hide()
	progress_wheel.current_value = 0.0
	hold_timer.timeout.connect(_on_hold_complete)
	await get_tree().process_frame
	# Get player from PlayerManager (new system) or fallback to old system
	var player = PlayerManager.get_current_player() if PlayerManager else null
	if not player and CogitoSceneManager and CogitoSceneManager.has_method("get") and CogitoSceneManager.get("_current_player_node"):
		player = CogitoSceneManager._current_player_node
	
	if player and player is CogitoPlayer:
		player_interaction_component = player.player_interaction_component
	else:
		push_warning("UiHoldComponent: Could not find player node to get interaction component")


func _process(_delta: float) -> void:
	if is_holding and hold_interaction:
		if hold_timer.time_left < hold_timer.wait_time - buffer_time:
			show()
		hold_interaction.is_being_held.emit(hold_timer.time_left)
		progress_wheel.current_value = 1 - (hold_timer.time_left / hold_interaction.hold_time)

		var interaction_distance = (
			(
				hold_interaction.parent_node.global_position
				- player_interaction_component.global_position
			)
			. length()
		)
		if (
			interaction_distance
			>= player_interaction_component.interaction_raycast.target_position.length()
		):
			# Player moved too far - stop holding and stop turnwheel if it's a turnwheel
			_stop_turnwheel_if_needed()
			stop_holding()
	elif hold_interaction:
		# Hold was cancelled (is_holding became false)
		_stop_turnwheel_if_needed()
		stop_holding()


## Stop turnwheel visual rotation if hold was cancelled
func _stop_turnwheel_if_needed():
	if not hold_interaction:
		return
	
	# Check if this is a turnwheel
	var is_turnwheel = false
	var turnwheel_node = null
	if hold_interaction.parent_node:
		if hold_interaction.parent_node is CogitoTurnwheel:
			is_turnwheel = true
			turnwheel_node = hold_interaction.parent_node
		elif hold_interaction.parent_node.get_script() and hold_interaction.parent_node.get_script().resource_path.ends_with("cogito_turnwheel.gd"):
			is_turnwheel = true
			turnwheel_node = hold_interaction.parent_node
	
	if is_turnwheel and turnwheel_node:
		print("[HOLD UI DEBUG] Hold cancelled for turnwheel - stopping visual rotation")
		
		# Stop locally
		if turnwheel_node.has_method("stop_visual_rotation"):
			turnwheel_node.stop_visual_rotation()
		elif "is_currently_turning" in turnwheel_node and turnwheel_node.is_currently_turning:
			# Fallback if method doesn't exist
			if "audio_stream_player_3d" in turnwheel_node and turnwheel_node.audio_stream_player_3d:
				turnwheel_node.audio_stream_player_3d.stop()
			turnwheel_node.is_currently_turning = false
			if turnwheel_node.has_signal("turnwheel_interaction_stopped"):
				turnwheel_node.turnwheel_interaction_stopped.emit()
		
		# Send command to stop on all clients
		var player_id = -1
		if PlayerManager and player_interaction_component and player_interaction_component.player:
			player_id = PlayerManager.get_player_id(player_interaction_component.player)
		
		if player_id != -1:
			var command = InteractWithTurnwheelCommand.new(player_id, turnwheel_node, "stop")
			var result = CommandBus.execute_command(command)
			if result.success:
				print("[HOLD UI DEBUG] Turnwheel stop command executed successfully")
			else:
				print("[HOLD UI DEBUG] Turnwheel stop command failed: %s" % result.error_message)


func _input(event):
	if is_holding and event.is_action_released(hold_interaction.input_map_action):
		# Stop turnwheel if hold was cancelled early
		_stop_turnwheel_if_needed()
		
		if hold_interaction is DualInteraction:
			hold_interaction.on_quick_press.emit(player_interaction_component)
		if hold_interaction is ExtendedPickupInteraction:
			# Pick up the item on early release, using the PickupComponent
			hold_interaction.pickup.is_disabled = false
			hold_interaction.pickup.interact(player_interaction_component)
			if hold_interaction != null:  # The pickup failed if it's components still exist
				hold_interaction.pickup.is_disabled = true

		stop_holding()


func _on_hold_complete():
	print("[HOLD UI DEBUG] _on_hold_complete() called: hold_interaction=%s, type=%s" % [hold_interaction, hold_interaction.get_class() if hold_interaction else "null"])
	
	# Special handling for turnwheel - check if parent_node is CogitoTurnwheel
	var is_turnwheel = false
	if hold_interaction and hold_interaction.parent_node:
		if hold_interaction.parent_node is CogitoTurnwheel:
			is_turnwheel = true
		elif hold_interaction.parent_node.get_script() and hold_interaction.parent_node.get_script().resource_path.ends_with("cogito_turnwheel.gd"):
			is_turnwheel = true
	
	# Important for HoldInteraction to be a base HoldInteraction, not a subclass, to work
	if (
		hold_interaction is not DualInteraction
		and hold_interaction is not ExtendedPickupInteraction
	):
		# Special case: if this is a turnwheel, we need to use command system
		if is_turnwheel:
			print("[HOLD UI DEBUG] Turnwheel with base HoldInteraction - using command system")
			var player_id = -1
			if PlayerManager and player_interaction_component and player_interaction_component.player:
				player_id = PlayerManager.get_player_id(player_interaction_component.player)
			
			if player_id != -1:
				var command = InteractWithTurnwheelCommand.new(player_id, hold_interaction.parent_node, "complete")
				var result = CommandBus.execute_command(command)
				if result.success:
					print("[HOLD UI DEBUG] Turnwheel complete command executed successfully")
				else:
					print("[HOLD UI DEBUG] Turnwheel complete command failed: %s, using fallback" % result.error_message)
					hold_interaction.parent_node.interact(player_interaction_component)
			else:
				print("[HOLD UI DEBUG] Player ID not found, using fallback")
				hold_interaction.parent_node.interact(player_interaction_component)
		else:
			print("[HOLD UI DEBUG] Base HoldInteraction - calling parent_node.interact()")
			hold_interaction.parent_node.interact(player_interaction_component)
	elif hold_interaction is DualInteraction:
		print("[HOLD UI DEBUG] DualInteraction - emitting on_hold_complete signal for: %s" % hold_interaction.get_path())
		hold_interaction.on_hold_complete.emit(player_interaction_component)
	elif hold_interaction is ExtendedPickupInteraction:
		print("[HOLD UI DEBUG] ExtendedPickupInteraction - calling use()")
		hold_interaction.use()
	stop_holding()


func start_holding(_hold_interaction: HoldInteraction) -> void:
	if !is_holding:
		# Aligns the progress wheel with the prompt, for feedback on which prompt is being interacted with
		var pixel_y_offset: float = 0
		for node in prompt_area.get_children(false):
			if (
				node is UiPromptComponent
				and (
					(node as UiPromptComponent).interaction_text.text
					== _hold_interaction.interaction_text
				)
			):
				var x_offset: float = progress_wheel.radius * -2.0
				var y_offset: float = (node.size.y * 0.5) + pixel_y_offset
				position = Vector2(x_offset, y_offset)
				break
			else:
				pixel_y_offset += node.size.y

		is_holding = true
		hold_interaction = _hold_interaction
		hold_timer.wait_time = hold_interaction.hold_time
		progress_wheel.current_value = 1 - (hold_timer.time_left / hold_interaction.hold_time)
		hold_timer.start()
		hold_interaction = _hold_interaction
		player_interaction_component.player.is_movement_paused = true
		
		# Special handling for turnwheel - send "start" command for visual replication
		var is_turnwheel = false
		if hold_interaction and hold_interaction.parent_node:
			if hold_interaction.parent_node is CogitoTurnwheel:
				is_turnwheel = true
			elif hold_interaction.parent_node.get_script() and hold_interaction.parent_node.get_script().resource_path.ends_with("cogito_turnwheel.gd"):
				is_turnwheel = true
		
		if is_turnwheel and not (hold_interaction is DualInteraction):
			# Turnwheel with base HoldInteraction - send start command
			print("[HOLD UI DEBUG] Turnwheel hold started - sending start command")
			var player_id = -1
			if PlayerManager and player_interaction_component and player_interaction_component.player:
				player_id = PlayerManager.get_player_id(player_interaction_component.player)
			
			if player_id != -1:
				var command = InteractWithTurnwheelCommand.new(player_id, hold_interaction.parent_node, "start")
				var result = CommandBus.execute_command(command)
				if result.success:
					print("[HOLD UI DEBUG] Turnwheel start command executed successfully")
				else:
					print("[HOLD UI DEBUG] Turnwheel start command failed: %s" % result.error_message)


func stop_holding() -> void:
	print("[TURNWHEEL DEBUG] stop_holding() called: is_holding=%s, hold_interaction=%s" % [is_holding, hold_interaction])
	hold_timer.stop()
	hide()
	is_holding = false
	hold_interaction = null
	progress_wheel.current_value = 0.0
	player_interaction_component.player.is_movement_paused = false
