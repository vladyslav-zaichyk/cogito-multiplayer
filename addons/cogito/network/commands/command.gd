extends RefCounted
class_name Command
## Base class for all commands in the Command/Event Sourcing architecture.
## All player actions (pick up, drop, use, equip, etc.) should be implemented as commands.

## Unique command ID (UUID or timestamp-based)
var command_id: String
## ID of the player who executed the command
var player_id: int
## Timestamp when command was created
var timestamp: float
## Whether the command has been executed
var executed: bool = false
## Type of validation: HOST_VALIDATION (host validates) or CLIENT_VALIDATION (client validates)
enum ValidationType { HOST_VALIDATION, CLIENT_VALIDATION }
var validation_type: ValidationType = ValidationType.HOST_VALIDATION


func _init(player_id_value: int = -1):
	command_id = _generate_id()
	player_id = player_id_value
	timestamp = Time.get_ticks_msec() / 1000.0
	executed = false


## Generate unique ID for command
func _generate_id() -> String:
	# Use centralized ID generator for better uniqueness
	return IDGenerator.generate_id()


## Execute the command (must be overridden in subclasses)
func execute() -> CommandResult:
	push_error("Command.execute() must be overridden in subclass: %s" % get_script().get_path())
	return CommandResult.new(false, "Not implemented")


## Validate the command before execution (can be overridden in subclasses)
## Returns true if command is valid, false otherwise
func validate() -> bool:
	return true  # Default: validation passes


## Serialize command for network transmission
func serialize() -> Dictionary:
	var script_path = get_script().get_path() if get_script() else ""
	var command_type = script_path.get_file().get_basename() if not script_path.is_empty() else "unknown"
	
	return {
		"command_id": command_id,
		"player_id": player_id,
		"timestamp": timestamp,
		"command_type": command_type,
		"validation_type": validation_type
	}


## Deserialize command from network data (must be overridden in subclasses)
static func deserialize(data: Dictionary) -> Command:
	push_error("Command.deserialize() must be overridden in subclass")
	return null


## Get command type name (for logging/debugging)
func get_command_type() -> String:
	var script_path = get_script().get_path() if get_script() else ""
	return script_path.get_file().get_basename() if not script_path.is_empty() else "unknown"

