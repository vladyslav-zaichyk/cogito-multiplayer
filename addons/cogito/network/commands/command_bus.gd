extends Node
## Command Bus for routing commands and events in the Command/Event Sourcing architecture.
## This is an autoload singleton that handles command execution and event distribution.
## 
## Note: Cannot use class_name because this is an autoload singleton.
## Registered in cogito_plugin.gd as "CommandBus" autoload.
## Accessible directly as global variable at runtime (e.g., CommandBus.execute_command()).
## 
## Commands and Events use class_name for static typing, so we can call them directly.

## Commands and Events use class_name for static typing, so we can call them directly.
## No need for preload - class_name provides compile-time type checking.

## Enable/disable logging
var enable_logging: bool = false
## Note: ResponseHandler is an autoload singleton (registered in cogito_plugin.gd)
## Accessible directly as global variable at runtime (e.g., ResponseHandler.handle_result())

## Registry of command handlers (command_type -> handlers array)
var _command_handlers: Dictionary = {}
## Registry of event handlers (event_type -> handlers array)
var _event_handlers: Dictionary = {}
## Pending commands waiting for validation (command_id -> command)
var _pending_commands: Dictionary = {}


func _ready() -> void:
	# CommandBus initialized - ResponseHandler is autoload singleton
	# It will be available as global variable at runtime
	pass


## Register a command handler
## command_type: Type of command (e.g., "pickup_item_command")
## handler: Callable that takes a Command and returns CommandResult
func register_command_handler(command_type: String, handler: Callable) -> void:
	if not _command_handlers.has(command_type):
		_command_handlers[command_type] = []
	_command_handlers[command_type].append(handler)


## Register an event handler
## event_type: Type of event (e.g., "item_picked")
## handler: Callable that takes an Event
func register_event_handler(event_type: String, handler: Callable) -> void:
	if not _event_handlers.has(event_type):
		_event_handlers[event_type] = []
	_event_handlers[event_type].append(handler)


## Execute a command (local execution)
## Returns CommandResult with success status and events
func execute_command(command: Command, skip_validation: bool = false) -> CommandResult:
	if not command:
		var error_result = CommandResult.new(false, "Null command")
		error_result.response_code = CommandResult.ResponseCode.UNKNOWN_ERROR
		if ResponseHandler:
			ResponseHandler.handle_result(error_result, null, {"context": "null_command_check"})
		return error_result
	
	if command.executed:
		# Already executed - this is expected when syncing from network
		var sync_result = CommandResult.new(true, "")
		sync_result.response_code = CommandResult.ResponseCode.ALREADY_EXECUTED
		return sync_result
	
	# Validate BEFORE execution (for optimistic execution, we validate first)
	# This ensures validation checks the state before it's changed by execution
	if NetworkManager and NetworkManager.is_multiplayer() and not skip_validation:
		# Pre-validate command before execution
		if not command.validate():
			var error_result = CommandResult.new(false, "Command validation failed before execution")
			error_result.response_code = CommandResult.ResponseCode.VALIDATION_FAILED
			if ResponseHandler:
				ResponseHandler.handle_result(error_result, command, {"context": "pre_validation"})
			return error_result
	
	# Mark as executed
	command.executed = true
	
	# Execute command locally (optimistic execution)
	var result = command.execute()
	
	# Handle response centrally through ResponseHandler
	if ResponseHandler:
		ResponseHandler.handle_result(result, command, {
			"skip_validation": skip_validation,
			"is_multiplayer": NetworkManager and NetworkManager.is_multiplayer() if NetworkManager else false
		})
	
	# If multiplayer and not skipping validation, send command for validation
	# Include events in the serialized command so other clients can sync state
	# Note: Validation already passed, so we just broadcast
	if NetworkManager and NetworkManager.is_multiplayer() and not skip_validation:
		_send_command_for_validation(command, result.events)
	
	# Emit events
	for event in result.events:
		_emit_event(event)
	
	return result


## Send command for validation (host or client)
## events: List of events that occurred during local execution
func _send_command_for_validation(command: Command, events: Array[Event] = []) -> void:
	if command.validation_type == Command.ValidationType.HOST_VALIDATION:
		if NetworkManager.is_host():
			# Host validates locally
			_validate_and_broadcast(command, events)
		else:
			# Client sends to host for validation
			var command_data = command.serialize()
			# Include events in serialized data
			var events_data = []
			for event in events:
				events_data.append(event.serialize())
			command_data["events"] = events_data
			NetworkManager.validate_command.rpc(command_data)
			# Store command as pending
			_pending_commands[command.command_id] = command
	else:
		# CLIENT_VALIDATION - client validates locally
		_validate_and_broadcast(command, events)


## Validate and broadcast command to all clients
## events: List of events that occurred during local execution
func _validate_and_broadcast(command: Command, events: Array[Event] = []) -> void:
	# For optimistic execution, validation already happened BEFORE execution in execute_command()
	# So we can skip validation here and just broadcast
	# This prevents validation failures due to state changes from optimistic execution
	# Broadcast command to all clients
	var command_data = command.serialize()
	# Include events in serialized data
	var events_data = []
	for event in events:
		events_data.append(event.serialize())
	command_data["events"] = events_data
	NetworkManager.broadcast_command.rpc(command_data)


## Validate and broadcast command from network (called by NetworkManager RPC)
## This is used when host receives validation request from client
func _validate_and_broadcast_from_network(command_data: Dictionary, sender_peer_id: int) -> void:
	# Deserialize command
	var command = _deserialize_command(command_data)
	if not command:
		var error_result = CommandResult.new(false, "Failed to deserialize command from network for validation")
		error_result.response_code = CommandResult.ResponseCode.DESERIALIZATION_ERROR
		if ResponseHandler:
			ResponseHandler.handle_result(error_result, null, {"context": "validate_from_network", "sender_peer_id": sender_peer_id})
		return
	
	# Validate command
	if command.validate():
		# Broadcast to all clients (including sender) with events included
		# Events are already in command_data from the sender
		NetworkManager.broadcast_command.rpc(command_data)
	else:
		var error_result = CommandResult.new(false, "Command validation failed from peer")
		error_result.response_code = CommandResult.ResponseCode.VALIDATION_FAILED
		if ResponseHandler:
			ResponseHandler.handle_result(error_result, command, {"context": "host_validation", "sender_peer_id": sender_peer_id})
		# TODO: Send rejection to sender


## Rollback command (undo local changes)
## TODO: Implement proper rollback mechanism
func _rollback_command(command: Command) -> void:
	var error_result = CommandResult.new(false, "Rollback required - rollback not yet implemented")
	error_result.response_code = CommandResult.ResponseCode.ROLLBACK_REQUIRED
	if ResponseHandler:
		ResponseHandler.handle_result(error_result, command, {"context": "rollback"})
	# For now, just log - proper rollback will be implemented later
	# This is a placeholder for future implementation


## Emit an event to all registered handlers
func _emit_event(event: Event) -> void:
	if not event:
		return
	
	# Call all registered handlers for this event type
	if _event_handlers.has(event.event_type):
		for handler in _event_handlers[event.event_type]:
			if handler.is_valid():
				handler.call(event)
			else:
				var error_result = CommandResult.new(false, "Invalid event handler")
				error_result.response_code = CommandResult.ResponseCode.UNKNOWN_ERROR
				if ResponseHandler:
					ResponseHandler.handle_result(error_result, null, {"context": "event_handler", "event_type": event.event_type})


## Receive validated command from network (called by NetworkManager RPC)
## This is for syncing state from other clients - no validation needed
func receive_validated_command(command_data: Dictionary) -> void:
	# Deserialize command
	var command = _deserialize_command(command_data)
	if not command:
		var error_result = CommandResult.new(false, "Failed to deserialize command from network")
		error_result.response_code = CommandResult.ResponseCode.DESERIALIZATION_ERROR
		if ResponseHandler:
			ResponseHandler.handle_result(error_result, null, {"context": "receive_validated_command"})
		return
	
	# If this is our own command, remove from pending (it was already executed locally)
	if _pending_commands.has(command.command_id):
		_pending_commands.erase(command.command_id)
		# Our own command - already executed locally, just sync events
		for event_data in command_data.get("events", []):
			var event = _deserialize_event(event_data)
			if event:
				_emit_event(event)
		return
	
	# This is a command from another player - DO NOT execute it again!
	# The command was already executed on the sender's client.
	# We only need to sync state through events, not re-execute the command.
	# Re-executing would cause duplicate actions (e.g., picking up item twice).
	
	# Deserialize and emit events from the command data
	# Events contain all the information needed to sync state
	var events_data = command_data.get("events", [])
	for event_data in events_data:
		var event = _deserialize_event(event_data)
		if event:
			# Special handling for specific events - trigger visual replication
			# Check event type by string (since class_name might not be available at compile time)
			# Events are RefCounted objects, access properties directly
			var event_type = event.event_type if "event_type" in event else ""
			print("[COMMAND BUS DEBUG] receive_validated_command: Processing event type=%s" % event_type)
			if event_type == "turnwheel_interacted":
				print("[COMMAND BUS DEBUG] Calling _handle_turnwheel_event")
				_handle_turnwheel_event(event)
			elif event_type == "door_interacted":
				_handle_door_event(event)
			_emit_event(event)
	
	# Mark as synced (not executed, since we didn't execute it)
	var sync_result = CommandResult.new(true, "")
	sync_result.response_code = CommandResult.ResponseCode.SYNC_FROM_NETWORK


## Deserialize command from data (factory method)
func _deserialize_command(data: Dictionary) -> Command:
	var command_type = data.get("command_type", "")
	
	# Map command types to their classes (using class_name for static typing)
	# Commands have class_name, so we can call them directly
	# This will be expanded as we add more commands
	match command_type:
		"pickup_item_command":
			return PickupItemCommand.deserialize(data)
		"drop_item_command":
			return DropItemCommand.deserialize(data)
		"use_item_command":
			return UseItemCommand.deserialize(data)
		"equip_wieldable_command":
			return EquipWieldableCommand.deserialize(data)
		"unequip_wieldable_command":
			return UnequipWieldableCommand.deserialize(data)
		"wieldable_action_command":
			return WieldableActionCommand.deserialize(data)
		"reload_wieldable_command":
			return ReloadWieldableCommand.deserialize(data)
		"start_carrying_command":
			return StartCarryingCommand.deserialize(data)
		"stop_carrying_command":
			return StopCarryingCommand.deserialize(data)
		"interact_with_door_command":
			return InteractWithDoorCommand.deserialize(data)
		"interact_with_switch_command":
			return InteractWithSwitchCommand.deserialize(data)
		"interact_with_container_command":
			return InteractWithContainerCommand.deserialize(data)
		"interact_with_turnwheel_command":
			return InteractWithTurnwheelCommand.deserialize(data)
		_:
			var error_result = CommandResult.new(false, "Unknown command type: %s" % command_type)
			error_result.response_code = CommandResult.ResponseCode.DESERIALIZATION_ERROR
			if ResponseHandler:
				ResponseHandler.handle_result(error_result, null, {"context": "deserialize_command", "command_type": command_type})
	
	return null


## Handle Turnwheel event for visual replication on remote clients
func _handle_turnwheel_event(event) -> void:
	if not event:
		return
	
	# TurnwheelInteractedEvent is a RefCounted object, access properties directly
	var turnwheel_path = event.turnwheel_path if "turnwheel_path" in event else ""
	if turnwheel_path.is_empty():
		return
	
	var interaction_type = event.interaction_type if "interaction_type" in event else ""
	
	var scene_tree = Engine.get_main_loop() as SceneTree
	if not scene_tree or not scene_tree.current_scene:
		return
	
	var turnwheel_node = scene_tree.current_scene.get_node_or_null(NodePath(turnwheel_path))
	if not turnwheel_node:
		return
	
	# Check if it's a turnwheel (try class_name first, then script path)
	var is_turnwheel = false
	if turnwheel_node is CogitoTurnwheel:
		is_turnwheel = true
	elif turnwheel_node.get_script() and turnwheel_node.get_script().resource_path.ends_with("cogito_turnwheel.gd"):
		is_turnwheel = true
	
	if not is_turnwheel:
		return
	
	print("[COMMAND BUS DEBUG] _handle_turnwheel_event: type=%s, path=%s" % [interaction_type, turnwheel_path])
	
	match interaction_type:
		"start":
			# Start visual rotation on remote clients
			print("[COMMAND BUS DEBUG] Starting turnwheel rotation on remote client")
			if turnwheel_node.has_method("start_visual_rotation"):
				turnwheel_node.start_visual_rotation()
			else:
				# Fallback if method doesn't exist
				if turnwheel_node.has_signal("turnwheel_interaction_started"):
					turnwheel_node.turnwheel_interaction_started.emit()
				if turnwheel_node.audio_stream_player_3d:
					if not turnwheel_node.audio_stream_player_3d.playing:
						turnwheel_node.audio_stream_player_3d.play()
				turnwheel_node.is_currently_turning = true
		
		"stop":
			# Stop visual rotation on remote clients (hold was cancelled early)
			print("[COMMAND BUS DEBUG] Stopping turnwheel rotation on remote client (hold cancelled)")
			if turnwheel_node.has_method("stop_visual_rotation"):
				turnwheel_node.stop_visual_rotation()
			else:
				# Fallback if method doesn't exist
				if turnwheel_node.audio_stream_player_3d:
					turnwheel_node.audio_stream_player_3d.stop()
				turnwheel_node.is_currently_turning = false
				if turnwheel_node.has_signal("turnwheel_interaction_stopped"):
					turnwheel_node.turnwheel_interaction_stopped.emit()
		
		"complete":
			# Complete visual rotation on remote clients
			# IMPORTANT: We need to sync state and trigger nodes for visual replication
			# The event contains the correct state from the executing player
			print("[COMMAND BUS DEBUG] Completing turnwheel on remote client - syncing state and triggering nodes")
			
			# Stop visual rotation
			if turnwheel_node.has_method("stop_visual_rotation"):
				turnwheel_node.stop_visual_rotation()
			else:
				# Fallback if method doesn't exist
				if turnwheel_node.audio_stream_player_3d:
					turnwheel_node.audio_stream_player_3d.stop()
				turnwheel_node.is_currently_turning = false
				if turnwheel_node.has_signal("turnwheel_interaction_stopped"):
					turnwheel_node.turnwheel_interaction_stopped.emit()
			
			# Sync state from event (don't toggle, use the state from the event)
			var event_has_been_turned = event.has_been_turned if "has_been_turned" in event else false
			var state_changed = turnwheel_node.has_been_turned != event_has_been_turned
			if state_changed:
				turnwheel_node.has_been_turned = event_has_been_turned
				print("[COMMAND BUS DEBUG] Synced has_been_turned=%s from event (was %s)" % [event_has_been_turned, not event_has_been_turned])
				turnwheel_node.turnwheel_state_changed.emit(event_has_been_turned)
			
			# Trigger nodes for visual replication on remote clients
			# This ensures that bridges, doors, etc. are visually synced
			if state_changed and "nodes_to_trigger" in turnwheel_node:
				print("[COMMAND BUS DEBUG] Triggering %s nodes for visual replication" % turnwheel_node.nodes_to_trigger.size())
				for node in turnwheel_node.nodes_to_trigger:
					if node and node.has_method("interact"):
						print("[COMMAND BUS DEBUG] Triggering node on remote client: %s" % node.get_path())
						node.interact(null)


func _handle_door_event(event) -> void:
	if not event:
		return
	
	# DoorInteractedEvent is a RefCounted object, access properties directly
	var door_path = event.door_path
	if door_path.is_empty():
		return
	
	var action = event.action
	var is_open = event.is_open
	var is_locked = event.is_locked
	
	var scene_tree = Engine.get_main_loop() as SceneTree
	if not scene_tree or not scene_tree.current_scene:
		return
	
	var door_node = scene_tree.current_scene.get_node_or_null(NodePath(door_path))
	if not door_node:
		return
	
	# Apply door state changes for visual replication on remote clients
	# Only apply if this is not the local player's action
	var local_player_id = PlayerManager.get_local_player_id() if PlayerManager else -1
	if event.player_id != local_player_id:
		match action:
			"toggle":
				# Toggle door state
				if is_open and not door_node.is_open:
					# Door should be open but isn't - open it
					if door_node.has_method("open_door"):
						door_node.is_open = false  # Force animation
						door_node.open_door(null)
				elif not is_open and door_node.is_open:
					# Door should be closed but isn't - close it
					if door_node.has_method("close_door"):
						door_node.close_door(null)
			"unlock":
				# Unlock door
				if not is_locked and door_node.is_locked:
					if door_node.has_method("unlock_door"):
						door_node.unlock_door()
			"lock":
				# Lock door
				if is_locked and not door_node.is_locked:
					if door_node.has_method("lock_door"):
						door_node.lock_door()


## Deserialize event from data (factory method)
func _deserialize_event(data: Dictionary) -> Event:
	var event_type = data.get("event_type", "")
	
	# Map event types to their classes (using class_name for static typing)
	# Events have class_name, so we can call them directly
	# This will be expanded as we add more events
	match event_type:
		"item_picked":
			return ItemPickedEvent.deserialize(data)
		"item_dropped":
			return ItemDroppedEvent.deserialize(data)
		"item_used":
			return ItemUsedEvent.deserialize(data)
		"wieldable_equipped":
			return WieldableEquippedEvent.deserialize(data)
		"wieldable_unequipped":
			return WieldableUnequippedEvent.deserialize(data)
		"wieldable_action":
			return WieldableActionEvent.deserialize(data)
		"wieldable_reloaded":
			return WieldableReloadedEvent.deserialize(data)
		"carrying_started":
			return CarryingStartedEvent.deserialize(data)
		"carrying_stopped":
			return CarryingStoppedEvent.deserialize(data)
		"door_interacted":
			return DoorInteractedEvent.deserialize(data)
		"switch_interacted":
			return SwitchInteractedEvent.deserialize(data)
		"container_interacted":
			return ContainerInteractedEvent.deserialize(data)
		"turnwheel_interacted":
			return TurnwheelInteractedEvent.deserialize(data)
		_:
			var error_result = CommandResult.new(false, "Unknown event type: %s" % event_type)
			error_result.response_code = CommandResult.ResponseCode.DESERIALIZATION_ERROR
			if ResponseHandler:
				ResponseHandler.handle_result(error_result, null, {"context": "deserialize_event", "event_type": event_type})
	
	return null
