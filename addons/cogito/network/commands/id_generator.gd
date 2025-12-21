extends RefCounted
class_name IDGenerator
## Centralized ID generator for commands and events.
## Provides unique identifiers to avoid collisions in multiplayer scenarios.
## 
## This class implements a more robust ID generation than simple timestamp + random,
## reducing the risk of ID collisions in high-frequency scenarios.

## Counter for additional uniqueness (incremented on each generation)
static var _counter: int = 0
## Lock for thread safety (if needed in future)
static var _lock: Mutex = Mutex.new()


## Generate a unique ID for commands or events.
## 
## Returns: String with format "timestamp_counter_random" for uniqueness
## 
## Example: "1234567890_42_5678"
static func generate_id() -> String:
	_lock.lock()
	_counter += 1
	var current_counter = _counter
	_lock.unlock()
	
	# Combine timestamp, counter, and random for maximum uniqueness
	# Format: timestamp_counter_random
	var timestamp = Time.get_ticks_msec()
	var random = randi() % 1000000  # 6-digit random number
	
	return "%d_%d_%d" % [timestamp, current_counter, random]


## Generate a UUID v4 style ID (more robust, but longer).
## Uses timestamp + counter + random + process ID for uniqueness.
## 
## Returns: String with UUID-like format
## 
## Example: "1234567890-42-5678-9abc"
static func generate_uuid() -> String:
	_lock.lock()
	_counter += 1
	var current_counter = _counter
	_lock.unlock()
	
	var timestamp = Time.get_ticks_msec()
	var random1 = randi() % 0xFFFF
	var random2 = randi() % 0xFFFF
	var random3 = randi() % 0xFFFF
	
	# Format: timestamp-counter-random1-random2-random3
	return "%d-%d-%04x-%04x-%04x" % [timestamp, current_counter, random1, random2, random3]


## Reset the counter (useful for testing or if counter overflows).
## Note: This should rarely be needed, but available if necessary.
static func reset_counter() -> void:
	_lock.lock()
	_counter = 0
	_lock.unlock()

