@icon("res://addons/cogito/Assets/Graphics/Editor/Icon_CogitoObject.svg")
extends AnimatableBody3D
class_name CogitoTurnwheel

signal object_state_updated(interaction_text: String)
signal turnwheel_state_changed(has_been_turned: bool)
signal turnwheel_interaction_started()
signal turnwheel_interaction_stopped()

@onready var audio_stream_player_3d = $AudioStreamPlayer3D

## Name that will displayed when interacting. Leave blank to hide
@export var display_name: String

enum PromptPositionMode {
	ORIGIN,  ## at the objects origin point. Recommended for smaller objects.
	MARKER,  ## at the position of an assigned Marker3D node. Will throw an error if no marker is assigned. Recommended for big objects/doors.
	AABB_CENTER,  ## at the center of the calculated AABoundingBox. Works well but has a slight performance impact.
}
## This sets where interaction prompt gets displayed on the object.
@export var prompt_pos_mode: PromptPositionMode = PromptPositionMode.ORIGIN
@export var prompt_marker: Marker3D

## Define the axis the object will rotate.
@export var rotation_axis: Vector3 = Vector3(1, 0, 0)
## Rotation speed in radians per second.
@export var rotation_speed: float = 1
## Drag the nodes you want to get triggered in here from your scene hierarchy. Their interact func will be called when hold is complete.
@export var nodes_to_trigger: Array[Node]
## AudioStream to play while holding.
@export var hold_audio_stream: AudioStream

var has_been_turned: bool = false
var interaction_nodes: Array[Node]
var cogito_properties: CogitoProperties = null
var is_currently_turning: bool = false  # Track if interaction is in progress


func _ready():
	self.add_to_group("save_object_state")
	self.add_to_group("interactable")

	interaction_nodes = find_children("", "InteractionComponent", true)  #Grabs all attached interaction components
	audio_stream_player_3d.stream = hold_audio_stream
	
	# Enable physics process for continuous rotation (needed for visual replication)
	set_physics_process(true)

	for node in interaction_nodes:
		if node and node.has_signal("is_being_held"):
			node.is_being_held.connect(_is_being_turned)


## Start visual rotation (animation and audio)
## This is called for visual replication on all clients
func start_visual_rotation():
	if is_currently_turning:
		print("[TURNWHEEL DEBUG] start_visual_rotation: Already turning, skipping")
		return
	
	print("[TURNWHEEL DEBUG] start_visual_rotation: Starting visual rotation")
	is_currently_turning = true
	
	# Start audio
	if audio_stream_player_3d and not audio_stream_player_3d.playing:
		audio_stream_player_3d.play()
	
	# Emit signal for any listeners
	turnwheel_interaction_started.emit()


## Stop visual rotation (animation and audio)
## This is called when interaction is cancelled or completed
func stop_visual_rotation():
	if not is_currently_turning:
		print("[TURNWHEEL DEBUG] stop_visual_rotation: Not turning, skipping")
		return
	
	print("[TURNWHEEL DEBUG] stop_visual_rotation: Stopping visual rotation")
	is_currently_turning = false
	
	# Stop audio
	if audio_stream_player_3d:
		audio_stream_player_3d.stop()
	
	# Emit signal for any listeners
	turnwheel_interaction_stopped.emit()


func _is_being_turned(_time_remaining: float):
	# Start visual rotation on first call (for local player during hold)
	if not is_currently_turning:
		start_visual_rotation()
	
	# Rotate the turnwheel (this is called every frame during hold)
	# rotation_speed is in radians per second, so we need delta
	# But _is_being_turned is called from _process, not _physics_process
	# So we use get_process_delta_time() instead
	var delta = get_process_delta_time()
	if has_been_turned:
		self.rotate_object_local(rotation_axis * -1, rotation_speed * delta)
	else:
		self.rotate_object_local(rotation_axis, rotation_speed * delta)


func _physics_process(delta: float):
	# Continuous rotation for visual replication on all clients
	# This ensures rotation continues even when _is_being_turned() is not called
	# (e.g., on remote clients receiving the "start" event)
	if is_currently_turning:
		if has_been_turned:
			self.rotate_object_local(rotation_axis * -1, rotation_speed * delta)
		else:
			self.rotate_object_local(rotation_axis, rotation_speed * delta)


## Complete the turnwheel interaction (change state and trigger nodes)
## This should only be called on the executing client, not for visual replication
func complete_interaction():
	print("[TURNWHEEL DEBUG] complete_interaction: Completing turnwheel interaction")
	
	# Stop visual rotation
	stop_visual_rotation()
	
	# Change state
	has_been_turned = !has_been_turned
	CogitoGlobals.debug_log(
		true, "cogito_turnwheel.gd", "Turnwheel has been turned: " + str(has_been_turned)
	)
	print("[TURNWHEEL DEBUG] complete_interaction: has_been_turned=%s, nodes_to_trigger.count=%s" % [has_been_turned, nodes_to_trigger.size()])
	
	# Emit state change signal
	turnwheel_state_changed.emit(has_been_turned)
	
	# Trigger nodes (this is the actual game logic - bridges, doors, etc.)
	for node in nodes_to_trigger:
		print("[TURNWHEEL DEBUG] Triggering node: %s" % node.get_path())
		if node.has_method("interact"):
			node.interact(null)
		else:
			print("[TURNWHEEL DEBUG] WARNING: Node %s does not have interact() method" % node.get_path())


func interact(_player_interaction_component, force_complete: bool = false):
	print("[TURNWHEEL DEBUG] interact() called: is_currently_turning=%s, has_been_turned=%s, force_complete=%s" % [is_currently_turning, has_been_turned, force_complete])
	
	# If turnwheel is currently turning and this is NOT a forced complete (from command),
	# it means this is a quick press - just stop the rotation without changing state
	if is_currently_turning and not force_complete:
		print("[TURNWHEEL DEBUG] Turnwheel is turning but interact() called without force_complete - this is a quick press, stopping rotation only")
		stop_visual_rotation()
		return  # Don't change state or trigger nodes
	
	# Normal completion - turnwheel was held long enough (force_complete=true from command)
	# or turnwheel was not turning (direct call)
	complete_interaction()


func set_state():
	pass


func save():
	var state_dict = {
		"node_path": self.get_path(),
		"has_been_turned": has_been_turned,
		"pos_x": position.x,
		"pos_y": position.y,
		"pos_z": position.z,
		"rot_x": rotation.x,
		"rot_y": rotation.y,
		"rot_z": rotation.z,
	}
	return state_dict
