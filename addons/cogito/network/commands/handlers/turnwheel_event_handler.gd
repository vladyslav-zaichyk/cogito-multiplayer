extends EventHandler
class_name TurnwheelEventHandler
## Handler for TurnwheelInteractedEvent.
## Handles visual replication of turnwheel interactions on remote clients.
## 
## This handler processes "start", "stop", and "complete" interaction types
## to synchronize turnwheel state and animations across all clients.

func _init():
	event_type = "turnwheel_interacted"


## Process TurnwheelInteractedEvent for visual replication.
## 
## event: TurnwheelInteractedEvent to process
func handle(event: Event) -> void:
	if not event is TurnwheelInteractedEvent:
		push_error("TurnwheelEventHandler: Expected TurnwheelInteractedEvent, got %s" % event.get_class())
		return
	
	var turnwheel_event = event as TurnwheelInteractedEvent
	_process_turnwheel_event(turnwheel_event)


## Process turnwheel event with strict typing.
## 
## event: TurnwheelInteractedEvent with strict typing
func _process_turnwheel_event(event: TurnwheelInteractedEvent) -> void:
	if event.turnwheel_path.is_empty():
		return
	
	var scene_tree = Engine.get_main_loop() as SceneTree
	if not scene_tree or not scene_tree.current_scene:
		return
	
	var turnwheel_node = scene_tree.current_scene.get_node_or_null(NodePath(event.turnwheel_path))
	if not turnwheel_node:
		return
	
	# Check if it's a turnwheel using strict typing
	# CogitoTurnwheel has class_name, so we can use strict type checking
	if not turnwheel_node is CogitoTurnwheel:
		# Fallback: check script path (for backwards compatibility)
		# This should not be needed if all turnwheels use class_name CogitoTurnwheel
		if not (turnwheel_node.get_script() and turnwheel_node.get_script().resource_path.ends_with("cogito_turnwheel.gd")):
			return
	
	# Type assertion - safe because we checked with 'is' above
	# Using explicit type annotation for compile-time checking
	var turnwheel: CogitoTurnwheel = turnwheel_node as CogitoTurnwheel
	
	print("[TURNWHEEL HANDLER] Processing event: type=%s, path=%s" % [event.interaction_type, event.turnwheel_path])
	
	match event.interaction_type:
		"start":
			_handle_start(turnwheel)
		"stop":
			_handle_stop(turnwheel)
		"complete":
			_handle_complete(turnwheel, event.has_been_turned)
		_:
			push_warning("TurnwheelEventHandler: Unknown interaction type: %s" % event.interaction_type)


## Handle "start" interaction - start visual rotation on remote clients.
## 
## turnwheel: CogitoTurnwheel node to start rotation on
func _handle_start(turnwheel: CogitoTurnwheel) -> void:
	print("[TURNWHEEL HANDLER] Starting turnwheel rotation on remote client")
	if turnwheel.has_method("start_visual_rotation"):
		turnwheel.start_visual_rotation()
	else:
		# Fallback if method doesn't exist
		if turnwheel.has_signal("turnwheel_interaction_started"):
			turnwheel.turnwheel_interaction_started.emit()
		if turnwheel.audio_stream_player_3d and not turnwheel.audio_stream_player_3d.playing:
			turnwheel.audio_stream_player_3d.play()
		turnwheel.is_currently_turning = true


## Handle "stop" interaction - stop visual rotation on remote clients.
## 
## turnwheel: CogitoTurnwheel node to stop rotation on
func _handle_stop(turnwheel: CogitoTurnwheel) -> void:
	print("[TURNWHEEL HANDLER] Stopping turnwheel rotation on remote client (hold cancelled)")
	if turnwheel.has_method("stop_visual_rotation"):
		turnwheel.stop_visual_rotation()
	else:
		# Fallback if method doesn't exist
		if turnwheel.audio_stream_player_3d:
			turnwheel.audio_stream_player_3d.stop()
		turnwheel.is_currently_turning = false
		if turnwheel.has_signal("turnwheel_interaction_stopped"):
			turnwheel.turnwheel_interaction_stopped.emit()


## Handle "complete" interaction - complete visual rotation and sync state.
## 
## turnwheel: CogitoTurnwheel node to complete rotation on
## has_been_turned: Boolean state from the event (from executing player)
func _handle_complete(turnwheel: CogitoTurnwheel, has_been_turned: bool) -> void:
	print("[TURNWHEEL HANDLER] Completing turnwheel on remote client - syncing state and triggering nodes")
	
	# Stop visual rotation
	if turnwheel.has_method("stop_visual_rotation"):
		turnwheel.stop_visual_rotation()
	else:
		# Fallback if method doesn't exist
		if turnwheel.audio_stream_player_3d:
			turnwheel.audio_stream_player_3d.stop()
		turnwheel.is_currently_turning = false
		if turnwheel.has_signal("turnwheel_interaction_stopped"):
			turnwheel.turnwheel_interaction_stopped.emit()
	
	# Sync state from event (don't toggle, use the state from the event)
	# This ensures all clients have the same state as the executing player
	var state_changed = turnwheel.has_been_turned != has_been_turned
	if state_changed:
		turnwheel.has_been_turned = has_been_turned
		print("[TURNWHEEL HANDLER] Synced has_been_turned=%s from event (was %s)" % [has_been_turned, not has_been_turned])
		turnwheel.turnwheel_state_changed.emit(has_been_turned)
	
	# Trigger nodes for visual replication on remote clients
	# This ensures that bridges, doors, etc. are visually synced
	if state_changed and turnwheel.nodes_to_trigger.size() > 0:
		print("[TURNWHEEL HANDLER] Triggering %s nodes for visual replication" % turnwheel.nodes_to_trigger.size())
		for node in turnwheel.nodes_to_trigger:
			if node and node.has_method("interact"):
				print("[TURNWHEEL HANDLER] Triggering node on remote client: %s" % node.get_path())
				node.interact(null)

