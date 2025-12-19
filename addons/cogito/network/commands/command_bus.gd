extends Node
## Command Bus for routing commands and events in the Command/Event Sourcing architecture.
## This is an autoload singleton that handles command execution and event distribution.
## 
## Note: Cannot use class_name because this is an autoload singleton.
## Registered in cogito_plugin.gd as "CommandBus" autoload.
## Accessible directly as global variable at runtime (e.g., CommandBus.execute_command()).
## 
## Commands and Events use class_name for static typing, so we can call them directly.

## Enable/disable logging
var enable_logging: bool = false

## Registry of command handlers (command_type -> handlers array)
var _command_handlers: Dictionary = {}
## Registry of event handlers (event_type -> handlers array)
var _event_handlers: Dictionary = {}
## Pending commands waiting for validation (command_id -> command)
var _pending_commands: Dictionary = {}


func _ready() -> void:
	# CommandBus initialized - no logging needed unless debugging
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


## Execute a command
## Returns CommandResult with success status and events
func execute_command(command: Command) -> CommandResult:
	if not command:
		push_error("CommandBus: Cannot execute null command")
		return CommandResult.new(false, "Null command")
	
	if command.executed:
		push_warning("CommandBus: Command %s already executed, skipping" % command.command_id)
		return CommandResult.new(false, "Command already executed")
	
	# Mark as executed
	command.executed = true
	
	# Execute command locally (optimistic execution)
	var result = command.execute()
	
	# If multiplayer, send command for validation
	if NetworkManager and NetworkManager.is_multiplayer():
		_send_command_for_validation(command)
	
	# Emit events
	for event in result.events:
		_emit_event(event)
	
	return result


## Send command for validation (host or client)
func _send_command_for_validation(command: Command) -> void:
	if command.validation_type == Command.ValidationType.HOST_VALIDATION:
		if NetworkManager.is_host():
			# Host validates locally
			_validate_and_broadcast(command)
		else:
			# Client sends to host for validation
			NetworkManager.validate_command.rpc(command.serialize())
			# Store command as pending
			_pending_commands[command.command_id] = command
	else:
		# CLIENT_VALIDATION - client validates locally
		_validate_and_broadcast(command)


## Validate and broadcast command to all clients
func _validate_and_broadcast(command: Command) -> void:
	if command.validate():
		# Broadcast command to all clients
		NetworkManager.broadcast_command.rpc(command.serialize())
	else:
		push_warning("CommandBus: Command validation failed: %s (type: %s), rolling back" % [
			command.command_id,
			command.get_command_type()
		])
		# Validation failed - rollback local changes
		_rollback_command(command)


## Validate and broadcast command from network (called by NetworkManager RPC)
## This is used when host receives validation request from client
func _validate_and_broadcast_from_network(command_data: Dictionary, sender_peer_id: int) -> void:
	# Deserialize command
	var command = _deserialize_command(command_data)
	if not command:
		push_error("CommandBus: Failed to deserialize command from network for validation")
		return
	
	# Validate command
	if command.validate():
		# Broadcast to all clients (including sender)
		NetworkManager.broadcast_command.rpc(command.serialize())
	else:
		push_warning("CommandBus: [HOST] Command validation failed from peer %d: %s (type: %s)" % [
			sender_peer_id,
			command.command_id,
			command.get_command_type()
		])
		# TODO: Send rejection to sender


## Rollback command (undo local changes)
## TODO: Implement proper rollback mechanism
func _rollback_command(command: Command) -> void:
	push_warning("CommandBus: Rolling back command: %s (type: %s) - rollback not yet implemented" % [
		command.command_id,
		command.get_command_type()
	])
	# For now, just warn - proper rollback will be implemented later
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
				push_warning("CommandBus: Invalid event handler for type: %s" % event.event_type)


## Receive validated command from network (called by NetworkManager RPC)
func receive_validated_command(command_data: Dictionary) -> void:
	# Deserialize command
	var command = _deserialize_command(command_data)
	if not command:
		push_error("CommandBus: Failed to deserialize command from network")
		return
	
	# If this is our own command, remove from pending
	if _pending_commands.has(command.command_id):
		_pending_commands.erase(command.command_id)
	
	# Execute command (it was already executed locally, but we need to sync state)
	# For now, we'll just emit events - actual state sync will be handled by event handlers
	for event_data in command_data.get("events", []):
		var event = _deserialize_event(event_data)
		if event:
			_emit_event(event)


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
		_:
			push_error("CommandBus: Unknown command type: %s" % command_type)
	
	return null


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
		_:
			push_error("CommandBus: Unknown event type: %s" % event_type)
	
	return null

