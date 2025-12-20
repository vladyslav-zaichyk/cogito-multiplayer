extends Node
## Centralized handler for command response codes.
## Processes all command results and handles logging, metrics, etc.
## This is an autoload singleton registered in cogito_plugin.gd.
## Note: Cannot use class_name because this is an autoload singleton.
## Accessible directly as global variable at runtime (e.g., ResponseHandler.handle_result()).

## Enable/disable logging
var enable_logging: bool = false
## Log to file
var log_to_file: bool = false
var log_file_path: String = "user://command_responses.log"

## Response code to log level mapping
var _log_levels: Dictionary = {
	CommandResult.ResponseCode.SUCCESS: "INFO",
	CommandResult.ResponseCode.ALREADY_EXECUTED: "DEBUG",
	CommandResult.ResponseCode.SYNC_FROM_NETWORK: "DEBUG",
	CommandResult.ResponseCode.VALIDATION_FAILED: "WARNING",
	CommandResult.ResponseCode.EXECUTION_FAILED: "ERROR",
	CommandResult.ResponseCode.PLAYER_NOT_FOUND: "ERROR",
	CommandResult.ResponseCode.INVENTORY_FULL: "WARNING",
	CommandResult.ResponseCode.ITEM_NOT_FOUND: "WARNING",
	CommandResult.ResponseCode.INVALID_STATE: "WARNING",
	CommandResult.ResponseCode.ROLLBACK_REQUIRED: "ERROR",
	CommandResult.ResponseCode.NETWORK_ERROR: "ERROR",
	CommandResult.ResponseCode.DESERIALIZATION_ERROR: "ERROR",
	CommandResult.ResponseCode.UNKNOWN_ERROR: "ERROR"
}

## Response code to human-readable message mapping
var _code_messages: Dictionary = {
	CommandResult.ResponseCode.SUCCESS: "Command executed successfully",
	CommandResult.ResponseCode.ALREADY_EXECUTED: "Command already executed (expected in sync)",
	CommandResult.ResponseCode.SYNC_FROM_NETWORK: "Command synced from network (expected)",
	CommandResult.ResponseCode.VALIDATION_FAILED: "Command validation failed",
	CommandResult.ResponseCode.EXECUTION_FAILED: "Command execution failed",
	CommandResult.ResponseCode.PLAYER_NOT_FOUND: "Player not found",
	CommandResult.ResponseCode.INVENTORY_FULL: "Inventory is full",
	CommandResult.ResponseCode.ITEM_NOT_FOUND: "Item not found",
	CommandResult.ResponseCode.INVALID_STATE: "Invalid game state",
	CommandResult.ResponseCode.ROLLBACK_REQUIRED: "Command rollback required",
	CommandResult.ResponseCode.NETWORK_ERROR: "Network communication error",
	CommandResult.ResponseCode.DESERIALIZATION_ERROR: "Failed to deserialize command",
	CommandResult.ResponseCode.UNKNOWN_ERROR: "Unknown error occurred"
}


## Process a command result
## result: CommandResult to process
## command: Command that was executed
## context: Additional context (optional)
func handle_result(result: CommandResult, command: Command, context: Dictionary = {}) -> void:
	if not result:
		return
	
	var category = result.get_category() if result else CommandResult.ResponseCategory.SERVER_ERROR
	var log_level = _log_levels.get(result.response_code, "INFO")
	
	# Only log unexpected errors (not expected flows)
	if category != CommandResult.ResponseCategory.SUCCESS:
		_log_response(result, command, context, log_level)
	
	# Handle specific response codes
	match result.response_code:
		CommandResult.ResponseCode.VALIDATION_FAILED:
			_handle_validation_failed(result, command, context)
		CommandResult.ResponseCode.ROLLBACK_REQUIRED:
			_handle_rollback_required(result, command, context)
		CommandResult.ResponseCode.NETWORK_ERROR:
			_handle_network_error(result, command, context)


## Log response
func _log_response(result: CommandResult, command: Command, context: Dictionary, level: String) -> void:
	var command_type = command.get_command_type() if command else "unknown"
	var code_message = _code_messages.get(result.response_code, "Unknown code")
	var error_msg = result.error_message if result.error_message else code_message
	
	var message = "[%s] Command: %s | Code: %d (%s) | Message: %s" % [
		level,
		command_type,
		result.response_code,
		code_message,
		error_msg
	]
	
	# Add context if available
	if context.size() > 0:
		message += " | Context: %s" % str(context)
	
	# Console logging
	match level:
		"ERROR":
			push_error("ResponseHandler: " + message)
		"WARNING":
			push_warning("ResponseHandler: " + message)
		_:
			if enable_logging:
				print("ResponseHandler: " + message)
	
	# File logging
	if log_to_file:
		_log_to_file(message)


## Handle validation failed
func _handle_validation_failed(result: CommandResult, command: Command, context: Dictionary) -> void:
	# Could trigger rollback, notify player, etc.
	# For now, just log - rollback is handled by CommandBus
	pass


## Handle rollback required
func _handle_rollback_required(result: CommandResult, command: Command, context: Dictionary) -> void:
	# Trigger rollback mechanism
	# For now, rollback is handled by CommandBus
	pass


## Handle network error
func _handle_network_error(result: CommandResult, command: Command, context: Dictionary) -> void:
	# Handle network issues, retry logic, etc.
	# Could implement retry mechanism here
	pass


## Log to file
func _log_to_file(message: String) -> void:
	var file = FileAccess.open(log_file_path, FileAccess.WRITE_READ)
	if file:
		file.seek_end()
		var timestamp = Time.get_datetime_string_from_system()
		file.store_string("[%s] %s\n" % [timestamp, message])
		file.close()
