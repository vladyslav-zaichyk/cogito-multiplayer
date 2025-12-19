extends RefCounted
class_name CommandResult
## Result of command execution.
## Contains success status, error message, and events that occurred.

## Whether the command executed successfully
var success: bool
## Error message if command failed
var error_message: String = ""
## List of events that occurred as a result of command execution
var events: Array[Event] = []
## Additional result data (can be used for returning values)
var data: Dictionary = {}


func _init(success_value: bool = true, error: String = ""):
	success = success_value
	error_message = error
	events = []
	data = {}


## Add an event to the result
func add_event(event: Event) -> void:
	events.append(event)


## Check if result has any events
func has_events() -> bool:
	return events.size() > 0


## Get all events of a specific type
func get_events_by_type(event_type: String) -> Array[Event]:
	var result: Array[Event] = []
	for event in events:
		if event.event_type == event_type:
			result.append(event)
	return result

