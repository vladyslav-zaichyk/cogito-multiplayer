extends RefCounted
class_name EventRegistry
## Registry for event deserialization.
## Allows registering event types without modifying CommandBus.
## 
## This class implements the Factory pattern for event deserialization,
## enabling Open/Closed Principle - new events can be registered without
## modifying CommandBus code.

## Registry of event type -> deserialize function
## Key: String identifier (e.g., "item_picked")
## Value: Callable (static function that takes Dictionary and returns Event)
var _deserializers: Dictionary = {}


## Register an event type for deserialization.
## 
## event_type: String identifier (e.g., "item_picked")
## deserializer: Static function that takes Dictionary and returns Event
## 
## Example:
##   registry.register_event_type("item_picked", ItemPickedEvent.deserialize)
func register_event_type(event_type: String, deserializer: Callable) -> void:
	if event_type.is_empty():
		push_error("EventRegistry: Cannot register event with empty type")
		return
	
	if not deserializer.is_valid():
		push_error("EventRegistry: Invalid deserializer for event type: %s" % event_type)
		return
	
	_deserializers[event_type] = deserializer


## Deserialize event from network data.
## 
## data: Dictionary containing serialized event data
## Returns: Event instance or null if deserialization failed
func deserialize(data: Dictionary) -> Event:
	if data.is_empty():
		push_error("EventRegistry: Cannot deserialize empty data")
		return null
	
	var event_type = data.get("event_type", "")
	if event_type.is_empty():
		push_error("EventRegistry: Event data missing 'event_type' field")
		return null
	
	if not _deserializers.has(event_type):
		push_error("EventRegistry: Unknown event type: %s" % event_type)
		return null
	
	var deserializer: Callable = _deserializers[event_type]
	if not deserializer.is_valid():
		push_error("EventRegistry: Invalid deserializer for event type: %s" % event_type)
		return null
	
	var event = deserializer.call(data)
	if not event is Event:
		push_error("EventRegistry: Deserializer returned non-Event object for type: %s" % event_type)
		return null
	
	return event as Event


## Check if an event type is registered.
## 
## event_type: String identifier to check
## Returns: true if registered, false otherwise
func is_registered(event_type: String) -> bool:
	return _deserializers.has(event_type)


## Get all registered event types.
## Returns: Array of registered event type strings
func get_registered_types() -> Array[String]:
	var types: Array[String] = []
	for type in _deserializers.keys():
		types.append(type)
	return types

