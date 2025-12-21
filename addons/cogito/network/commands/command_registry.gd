extends RefCounted
class_name CommandRegistry
## Registry for command deserialization.
## Allows registering command types without modifying CommandBus.
## 
## This class implements the Factory pattern for command deserialization,
## enabling Open/Closed Principle - new commands can be registered without
## modifying CommandBus code.

## Registry of command type -> deserialize function
## Key: String identifier (e.g., "pickup_item_command")
## Value: Callable (static function that takes Dictionary and returns Command)
var _deserializers: Dictionary = {}


## Register a command type for deserialization.
## 
## command_type: String identifier (e.g., "pickup_item_command")
## deserializer: Static function that takes Dictionary and returns Command
## 
## Example:
##   registry.register_command_type("pickup_item_command", PickupItemCommand.deserialize)
func register_command_type(command_type: String, deserializer: Callable) -> void:
	if command_type.is_empty():
		push_error("CommandRegistry: Cannot register command with empty type")
		return
	
	if not deserializer.is_valid():
		push_error("CommandRegistry: Invalid deserializer for command type: %s" % command_type)
		return
	
	_deserializers[command_type] = deserializer


## Deserialize command from network data.
## 
## data: Dictionary containing serialized command data
## Returns: Command instance or null if deserialization failed
func deserialize(data: Dictionary) -> Command:
	if data.is_empty():
		push_error("CommandRegistry: Cannot deserialize empty data")
		return null
	
	var command_type = data.get("command_type", "")
	if command_type.is_empty():
		push_error("CommandRegistry: Command data missing 'command_type' field")
		return null
	
	if not _deserializers.has(command_type):
		push_error("CommandRegistry: Unknown command type: %s" % command_type)
		return null
	
	var deserializer: Callable = _deserializers[command_type]
	if not deserializer.is_valid():
		push_error("CommandRegistry: Invalid deserializer for command type: %s" % command_type)
		return null
	
	var command = deserializer.call(data)
	
	# Check if deserialization failed (null is valid - means deserialization failed gracefully)
	if command == null:
		# Deserializer already logged the error, just return null
		return null
	
	# Check if deserializer returned wrong type (should be Command)
	if not command is Command:
		push_error("CommandRegistry: Deserializer returned non-Command object for type: %s (got: %s)" % [command_type, command.get_class()])
		return null
	
	return command as Command


## Check if a command type is registered.
## 
## command_type: String identifier to check
## Returns: true if registered, false otherwise
func is_registered(command_type: String) -> bool:
	return _deserializers.has(command_type)


## Get all registered command types.
## Returns: Array of registered command type strings
func get_registered_types() -> Array[String]:
	var types: Array[String] = []
	for type in _deserializers.keys():
		types.append(type)
	return types
