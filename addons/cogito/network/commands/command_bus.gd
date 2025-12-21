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

## Registry for command deserialization (replaces match block)
var command_registry: CommandRegistry = CommandRegistry.new()
## Registry for event deserialization (replaces match block)
var event_registry: EventRegistry = EventRegistry.new()
## Registry of event handlers for visual replication (event_type -> EventHandler)
var _event_handlers_registry: Dictionary = {}  # event_type -> EventHandler


func _ready() -> void:
	# CommandBus initialized - ResponseHandler is autoload singleton
	# It will be available as global variable at runtime
	# Register all commands and events for deserialization
	_register_all_commands()
	_register_all_events()
	# Register all event handlers for visual replication
	_register_all_event_handlers()


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
			# Process event for visual replication using registered handlers
			_process_event_for_replication(event)
			# Emit event to registered event handlers
			_emit_event(event)
	
	# Mark as synced (not executed, since we didn't execute it)
	var sync_result = CommandResult.new(true, "")
	sync_result.response_code = CommandResult.ResponseCode.SYNC_FROM_NETWORK


## Register all command types for deserialization.
## This method registers all commands so they can be deserialized from network data.
## New commands should be added here when created.
func _register_all_commands() -> void:
	# Inventory commands
	command_registry.register_command_type("pickup_item_command", PickupItemCommand.deserialize)
	command_registry.register_command_type("drop_item_command", DropItemCommand.deserialize)
	command_registry.register_command_type("use_item_command", UseItemCommand.deserialize)
	
	# Wieldable commands
	command_registry.register_command_type("equip_wieldable_command", EquipWieldableCommand.deserialize)
	command_registry.register_command_type("unequip_wieldable_command", UnequipWieldableCommand.deserialize)
	command_registry.register_command_type("wieldable_action_command", WieldableActionCommand.deserialize)
	command_registry.register_command_type("reload_wieldable_command", ReloadWieldableCommand.deserialize)
	
	# Carry commands
	command_registry.register_command_type("start_carrying_command", StartCarryingCommand.deserialize)
	command_registry.register_command_type("stop_carrying_command", StopCarryingCommand.deserialize)
	
	# Interaction commands
	command_registry.register_command_type("interact_with_door_command", InteractWithDoorCommand.deserialize)
	command_registry.register_command_type("interact_with_switch_command", InteractWithSwitchCommand.deserialize)
	command_registry.register_command_type("interact_with_container_command", InteractWithContainerCommand.deserialize)
	command_registry.register_command_type("interact_with_turnwheel_command", InteractWithTurnwheelCommand.deserialize)


## Deserialize command from data using registry.
## This replaces the large match block with a registry-based approach,
## enabling Open/Closed Principle - new commands can be registered without modifying this method.
func _deserialize_command(data: Dictionary) -> Command:
	var command = command_registry.deserialize(data)
	if not command:
		# Registry already logged the error, but we can add context here if needed
		var command_type = data.get("command_type", "unknown")
		var error_result = CommandResult.new(false, "Failed to deserialize command: %s" % command_type)
		error_result.response_code = CommandResult.ResponseCode.DESERIALIZATION_ERROR
		if ResponseHandler:
			ResponseHandler.handle_result(error_result, null, {"context": "deserialize_command", "command_type": command_type})
	return command


## Register an EventHandler for visual replication.
## This is different from register_event_handler() which registers Callable handlers.
## 
## handler: EventHandler instance to register
func register_event_handler_instance(handler: EventHandler) -> void:
	if not handler:
		push_error("CommandBus: Cannot register null event handler")
		return
	
	if handler.event_type.is_empty():
		push_error("CommandBus: Cannot register event handler with empty event_type")
		return
	
	_event_handlers_registry[handler.event_type] = handler


## Register all event handlers for visual replication.
## This method registers all handlers so they can process events for remote clients.
## New handlers should be added here when created.
func _register_all_event_handlers() -> void:
	register_event_handler_instance(TurnwheelEventHandler.new())
	register_event_handler_instance(DoorEventHandler.new())


## Process event for visual replication on remote clients.
## This method uses registered handlers to process events, enabling Open/Closed Principle.
## 
## event: Event to process for visual replication
func _process_event_for_replication(event: Event) -> void:
	if not event:
		return
	
	var handler = _event_handlers_registry.get(event.event_type)
	if handler:
		handler.handle(event)
	else:
		# No handler registered for this event type - this is OK for events that don't need visual replication
		# Only log if it's an event type that we expect to have a handler
		if event.event_type in ["turnwheel_interacted", "door_interacted"]:
			push_warning("CommandBus: No handler registered for event type: %s" % event.event_type)


## Register all event types for deserialization.
## This method registers all events so they can be deserialized from network data.
## New events should be added here when created.
func _register_all_events() -> void:
	# Inventory events
	event_registry.register_event_type("item_picked", ItemPickedEvent.deserialize)
	event_registry.register_event_type("item_dropped", ItemDroppedEvent.deserialize)
	event_registry.register_event_type("item_used", ItemUsedEvent.deserialize)
	
	# Wieldable events
	event_registry.register_event_type("wieldable_equipped", WieldableEquippedEvent.deserialize)
	event_registry.register_event_type("wieldable_unequipped", WieldableUnequippedEvent.deserialize)
	event_registry.register_event_type("wieldable_action", WieldableActionEvent.deserialize)
	event_registry.register_event_type("wieldable_reloaded", WieldableReloadedEvent.deserialize)
	
	# Carry events
	event_registry.register_event_type("carrying_started", CarryingStartedEvent.deserialize)
	event_registry.register_event_type("carrying_stopped", CarryingStoppedEvent.deserialize)
	
	# Interaction events
	event_registry.register_event_type("door_interacted", DoorInteractedEvent.deserialize)
	event_registry.register_event_type("switch_interacted", SwitchInteractedEvent.deserialize)
	event_registry.register_event_type("container_interacted", ContainerInteractedEvent.deserialize)
	event_registry.register_event_type("turnwheel_interacted", TurnwheelInteractedEvent.deserialize)


## Deserialize event from data using registry.
## This replaces the large match block with a registry-based approach,
## enabling Open/Closed Principle - new events can be registered without modifying this method.
func _deserialize_event(data: Dictionary) -> Event:
	var event = event_registry.deserialize(data)
	if not event:
		# Registry already logged the error, but we can add context here if needed
		var event_type = data.get("event_type", "unknown")
		var error_result = CommandResult.new(false, "Failed to deserialize event: %s" % event_type)
		error_result.response_code = CommandResult.ResponseCode.DESERIALIZATION_ERROR
		if ResponseHandler:
			ResponseHandler.handle_result(error_result, null, {"context": "deserialize_event", "event_type": event_type})
	return event
