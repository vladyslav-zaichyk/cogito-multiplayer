extends Node
## Manager for handling world state in the system.
## Centralizes world state management for multiplayer support.
## Note: This is an autoload singleton, not a class_name

## Dictionary storing world state: key -> value
var _world_state: Dictionary = {}

## Enable/disable logging
var enable_logging: bool = false


func _ready() -> void:
	CogitoGlobals.debug_log(
		true, "WorldStateManager", "World State Manager initialized and ready."
	)


## Get a world state value by key
func get_world_state(key: String, default_value: Variant = null) -> Variant:
	if _world_state.has(key):
		return _world_state[key]
	return default_value


## Set a world state value
func set_world_state(key: String, value: Variant) -> void:
	var old_value = _world_state.get(key)
	_world_state[key] = value
	
	CogitoGlobals.debug_log(
		enable_logging,
		"WorldStateManager",
		"World state changed: %s = %s (old: %s)" % [key, str(value), str(old_value)]
	)
	
	# Emit event through Event Bus
	if NetworkEventBus:
		NetworkEventBus.world_state_changed.emit(key, value, old_value)


## Check if a world state key exists
func has_world_state(key: String) -> bool:
	return _world_state.has(key)


## Remove a world state key
func remove_world_state(key: String) -> void:
	if _world_state.has(key):
		var old_value = _world_state[key]
		_world_state.erase(key)
		
		CogitoGlobals.debug_log(
			enable_logging,
			"WorldStateManager",
			"World state removed: %s (old: %s)" % [key, str(old_value)]
		)
		
		# Emit event through Event Bus
		if NetworkEventBus:
			NetworkEventBus.world_state_changed.emit(key, null, old_value)


## Get all world state keys
func get_all_keys() -> Array:
	return _world_state.keys()


## Get the entire world state dictionary
func get_world_state_dict() -> Dictionary:
	return _world_state.duplicate(true)


## Set the entire world state dictionary (useful for loading)
func set_world_state_dict(world_dict: Dictionary) -> void:
	_world_state = world_dict.duplicate(true)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"WorldStateManager",
		"World state dictionary set with %d entries" % _world_state.size()
	)
	
	# Emit events for all changed values (optional, can be disabled for bulk updates)
	# For now, we'll just log it


## Clear all world state
func clear_world_state() -> void:
	var keys = _world_state.keys().duplicate()
	_world_state.clear()
	
	CogitoGlobals.debug_log(
		enable_logging,
		"WorldStateManager",
		"World state cleared (%d entries removed)" % keys.size()
	)
	
	# Emit events for all removed keys
	if NetworkEventBus:
		for key in keys:
			NetworkEventBus.world_state_changed.emit(key, null, null)


## Merge world state dictionary (useful for loading from save)
func merge_world_state_dict(world_dict: Dictionary) -> void:
	for key in world_dict:
		var old_value = _world_state.get(key)
		_world_state[key] = world_dict[key]
		
		# Emit event only if value actually changed
		if NetworkEventBus and old_value != world_dict[key]:
			NetworkEventBus.world_state_changed.emit(key, world_dict[key], old_value)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"WorldStateManager",
		"Merged world state dictionary with %d entries" % world_dict.size()
	)


## Helper function for backward compatibility
## Returns the world state dictionary (for compatibility with old code)
func get_current_world_dict() -> Dictionary:
	return _world_state

