extends InteractionComponent

signal basic_signal

@onready var parent_node = get_parent()  #Grabbing reference to parent


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if parent_node.has_signal("object_state_updated"):
		parent_node.object_state_updated.connect(_on_object_state_change)


func interact(_player_interaction_component: PlayerInteractionComponent):
	# Check if parent is a turnwheel that's currently turning
	if parent_node is CogitoTurnwheel:
		var turnwheel = parent_node as CogitoTurnwheel
		if "is_currently_turning" in turnwheel and turnwheel.is_currently_turning:
			print("[TURNWHEEL DEBUG] BasicInteraction.interact() called but turnwheel is turning - ignoring quick press")
			return  # Don't call interact() on turnwheel if it's currently turning
	
	if !attribute_check != AttributeCheck.NONE:
		if parent_node.has_method("interact"):
			parent_node.interact(_player_interaction_component)

		was_interacted_with.emit(interaction_text, input_map_action)
		basic_signal.emit()

	else:
		if check_attribute(_player_interaction_component):
			if parent_node.has_method("interact"):
				parent_node.interact(_player_interaction_component)

			was_interacted_with.emit(interaction_text, input_map_action)


func _on_object_state_change(_interaction_text: String):
	interaction_text = _interaction_text
