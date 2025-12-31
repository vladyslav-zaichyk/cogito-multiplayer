extends EventHandler
class_name DoorEventHandler
## Handler for DoorInteractedEvent.
## Handles visual replication of door interactions on remote clients.
## 
## This handler processes "toggle", "lock", and "unlock" actions
## to synchronize door state and animations across all clients.

func _init():
	event_type = "door_interacted"


## Process DoorInteractedEvent for visual replication.
## 
## event: DoorInteractedEvent to process
func handle(event: Event) -> void:
	if not event is DoorInteractedEvent:
		push_error("DoorEventHandler: Expected DoorInteractedEvent, got %s" % event.get_class())
		return
	
	var door_event = event as DoorInteractedEvent
	_process_door_event(door_event)


## Process door event with strict typing.
## 
## event: DoorInteractedEvent with strict typing
func _process_door_event(event: DoorInteractedEvent) -> void:
	if event.door_path.is_empty():
		return
	
	var scene_tree = Engine.get_main_loop() as SceneTree
	if not scene_tree or not scene_tree.current_scene:
		return
	
	var door_node = scene_tree.current_scene.get_node_or_null(NodePath(event.door_path))
	if not door_node:
		return
	
	# Check if it's a door using strict typing
	# CogitoDoor has class_name, so we can use strict type checking
	if not door_node is CogitoDoor:
		return
	
	# Type assertion - safe because we checked with 'is' above
	# Using explicit type annotation for compile-time checking
	var door: CogitoDoor = door_node as CogitoDoor
	
	# Apply door state changes for visual replication on remote clients
	# Only apply if this is not the local player's action
	var local_player_id = PlayerManager.get_local_player_id() if PlayerManager else -1
	if event.player_id != local_player_id:
		_apply_door_state(door, event)


## Apply door state changes based on event action.
## 
## door: CogitoDoor node to apply state to
## event: DoorInteractedEvent containing the action and state
func _apply_door_state(door: CogitoDoor, event: DoorInteractedEvent) -> void:
	match event.action:
		"toggle":
			_handle_toggle(door, event.is_open)
		"unlock":
			_handle_unlock(door, event.is_locked)
		"lock":
			_handle_lock(door, event.is_locked)
		_:
			push_warning("DoorEventHandler: Unknown action: %s" % event.action)


## Handle "toggle" action - open or close door.
## 
## door: CogitoDoor node to toggle
## is_open: Target open state from event
func _handle_toggle(door: CogitoDoor, is_open: bool) -> void:
	if is_open and not door.is_open:
		# Door should be open but isn't - open it
		if door.has_method("open_door"):
			door.is_open = false  # Force animation
			door.open_door(null)
	elif not is_open and door.is_open:
		# Door should be closed but isn't - close it
		if door.has_method("close_door"):
			door.close_door(null)


## Handle "unlock" action - unlock door.
## 
## door: CogitoDoor node to unlock
## is_locked: Target locked state from event (should be false for unlock)
func _handle_unlock(door: CogitoDoor, is_locked: bool) -> void:
	if not is_locked and door.is_locked:
		if door.has_method("unlock_door"):
			door.unlock_door()


## Handle "lock" action - lock door.
## 
## door: CogitoDoor node to lock
## is_locked: Target locked state from event (should be true for lock)
func _handle_lock(door: CogitoDoor, is_locked: bool) -> void:
	if is_locked and not door.is_locked:
		if door.has_method("lock_door"):
			door.lock_door()

