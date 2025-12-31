extends RefCounted
class_name Event
## Base class for all events in the Event Sourcing architecture.
## Events represent things that happened as a result of command execution.

## Unique event ID
var event_id: String
## ID of the player who triggered the event
var player_id: int
## Timestamp when event occurred
var timestamp: float
## Type of event (for routing to handlers)
var event_type: String


func _init(player_id_value: int = -1, event_type_value: String = ""):
	event_id = _generate_id()
	player_id = player_id_value
	timestamp = Time.get_ticks_msec() / 1000.0
	event_type = event_type_value


## Generate unique ID for event
func _generate_id() -> String:
	# Use centralized ID generator for better uniqueness
	return IDGenerator.generate_id()


## Serialize event for network transmission
func serialize() -> Dictionary:
	return {
		"event_id": event_id,
		"player_id": player_id,
		"timestamp": timestamp,
		"event_type": event_type
	}


## Deserialize event from network data (must be overridden in subclasses)
static func deserialize(data: Dictionary) -> Event:
	push_error("Event.deserialize() must be overridden in subclass")
	return null

