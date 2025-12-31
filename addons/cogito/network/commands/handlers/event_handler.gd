extends RefCounted
class_name EventHandler
## Base class for event handlers.
## Each handler is responsible for processing a specific event type for visual replication.
## 
## This class enables Single Responsibility Principle - each handler processes one event type.
## It also enables Open/Closed Principle - new handlers can be added without modifying CommandBus.

## Event type this handler processes (e.g., "turnwheel_interacted", "door_interacted")
var event_type: String = ""


## Process an event for visual replication on remote clients.
## This method should be overridden in subclasses to handle specific event types.
## 
## event: Event to process (must be of the correct type for this handler)
func handle(event: Event) -> void:
	push_error("EventHandler.handle() must be overridden in subclass: %s" % get_script().get_path())


## Check if this handler can process the given event type.
## 
## event_type: String identifier of the event type
## Returns: true if this handler processes the given type, false otherwise
func can_handle(event_type: String) -> bool:
	return self.event_type == event_type

