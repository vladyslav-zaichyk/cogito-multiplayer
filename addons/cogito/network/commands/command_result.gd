extends RefCounted
class_name CommandResult
## Result of command execution.
## Contains success status, error message, and events that occurred.

## Response categories (like HTTP status code ranges)
enum ResponseCategory {
	SUCCESS,      # 2xx - Expected flows, everything OK
	CLIENT_ERROR, # 4xx - Client-side issues (validation, execution)
	SERVER_ERROR  # 5xx - Server/system issues (network, rollback)
}

## Response codes for different execution scenarios (HTTP-like codes)
enum ResponseCode {
	# 2xx - Success / Expected flows
	SUCCESS = 200,                    # Command executed successfully
	ALREADY_EXECUTED = 201,          # Command was already executed (expected in sync)
	SYNC_FROM_NETWORK = 202,         # Command received from network (expected sync)
	
	# 4xx - Client errors (execution/validation issues)
	VALIDATION_FAILED = 400,         # Command validation failed
	EXECUTION_FAILED = 401,          # Command execution failed
	PLAYER_NOT_FOUND = 404,          # Player not found
	INVENTORY_FULL = 409,            # Inventory full
	ITEM_NOT_FOUND = 410,            # Item not found
	INVALID_STATE = 412,             # Invalid game state (e.g., changing wieldables, carrying)
	
	# 5xx - Server/System errors
	ROLLBACK_REQUIRED = 500,         # Command needs rollback
	NETWORK_ERROR = 502,             # Network communication error
	DESERIALIZATION_ERROR = 503,     # Failed to deserialize command
	UNKNOWN_ERROR = 599              # Unknown error occurred
}

## Whether the command executed successfully
var success: bool
## Response code indicating the execution scenario
var response_code: ResponseCode = ResponseCode.SUCCESS
## Error message if command failed (only for unexpected errors)
var error_message: String = ""
## List of events that occurred as a result of command execution
var events: Array[Event] = []
## Additional result data (can be used for returning values)
var data: Dictionary = {}


func _init(success_value: bool = true, error: String = "", code: ResponseCode = ResponseCode.SUCCESS):
	success = success_value
	error_message = error
	response_code = code
	events = []
	data = {}


## Check if this is an expected/ok scenario (not an error)
func is_expected() -> bool:
	return get_category() == ResponseCategory.SUCCESS


## Get category for response code (static method)
static func get_category_for_code(code: ResponseCode) -> ResponseCategory:
	if code >= 200 and code < 300:
		return ResponseCategory.SUCCESS
	elif code >= 400 and code < 500:
		return ResponseCategory.CLIENT_ERROR
	else:
		return ResponseCategory.SERVER_ERROR


## Get category for this result's response code
func get_category() -> ResponseCategory:
	return get_category_for_code(response_code)


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
