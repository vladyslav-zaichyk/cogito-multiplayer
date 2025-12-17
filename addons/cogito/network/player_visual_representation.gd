extends Node3D
## Player Visual Representation Component
## Creates a simple visual representation for multiplayer players
## Attach this to a CharacterBody3D (like CogitoPlayer)

## Enable/disable logging
var enable_logging: bool = false

## Player name to display
var player_name: String = "Player"

## Player ID
var player_id: int = -1

## Reference to the parent CharacterBody3D
var parent_body: CharacterBody3D = null

## Reference to the name label
var name_label: Label3D = null

## Reference to the visual mesh
var visual_mesh: MeshInstance3D = null

## Colors for different players
var player_colors: Array[Color] = [
	Color(1.0, 0.2, 0.2),  # Red
	Color(0.2, 0.2, 1.0),  # Blue
	Color(0.2, 1.0, 0.2),  # Green
	Color(1.0, 1.0, 0.2),  # Yellow
	Color(1.0, 0.2, 1.0),  # Magenta
	Color(0.2, 1.0, 1.0),  # Cyan
	Color(1.0, 0.5, 0.2),  # Orange
	Color(0.5, 0.2, 1.0),  # Purple
]


func _ready() -> void:
	parent_body = get_parent() as CharacterBody3D
	if not parent_body:
		push_error("PlayerVisualRepresentation: Parent must be a CharacterBody3D")
		return
	
	# Wait a frame for player to be initialized
	await get_tree().process_frame
	
	# Get player ID and name
	if parent_body.has_method("get") and parent_body.get("player_id"):
		player_id = parent_body.player_id
	
	# Get player name from PlayerManager or use default
	if PlayerManager:
		var player_node = PlayerManager.get_player(player_id)
		if player_node:
			# Try to get name from player node
			if player_node.has_method("get") and player_node.get("player_name"):
				player_name = player_node.player_name
			else:
				# Check if it's local player
				if PlayerManager.has_local_player() and PlayerManager.get_local_player_id() == player_id:
					player_name = "You"
				else:
					player_name = "Player %d" % player_id
	
	# Create visual representation
	_create_visual_representation()
	
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerVisualRepresentation",
		"Created visual representation for player %d: %s" % [player_id, player_name]
	)


## Create visual representation
func _create_visual_representation() -> void:
	# Create capsule mesh for player body
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.radius = 0.3
	capsule_mesh.height = 1.6
	capsule_mesh.radial_segments = 16
	
	# Create mesh instance
	visual_mesh = MeshInstance3D.new()
	visual_mesh.mesh = capsule_mesh
	
	# Set color based on player ID
	var color_index = (player_id - 1) % player_colors.size()
	var player_color = player_colors[color_index]
	
	# Create material with color
	var material = StandardMaterial3D.new()
	material.albedo_color = player_color
	material.metallic = 0.0
	material.roughness = 0.8
	visual_mesh.material_override = material
	
	# Position mesh (centered on player)
	visual_mesh.position = Vector3(0, 0.8, 0)  # Half height offset
	
	add_child(visual_mesh)
	
	# Create name label above player
	_create_name_label()


## Create name label above player
func _create_name_label() -> void:
	name_label = Label3D.new()
	name_label.text = player_name
	name_label.font_size = 24
	name_label.pixel_size = 0.01
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	
	# Set outline for better visibility
	# Label3D has outline_size and outline_modulate properties directly
	name_label.outline_size = 6
	name_label.outline_modulate = Color(0, 0, 0, 1)
	
	# Position label above player head
	name_label.position = Vector3(0, 2.0, 0)  # Above the capsule
	
	# Set text color based on player
	var color_index = (player_id - 1) % player_colors.size()
	var player_color = player_colors[color_index]
	name_label.modulate = player_color
	
	add_child(name_label)


## Update player name
func update_player_name(new_name: String) -> void:
	player_name = new_name
	if name_label:
		name_label.text = player_name


## Set player color
func set_player_color(color: Color) -> void:
	if visual_mesh and visual_mesh.material_override:
		visual_mesh.material_override.albedo_color = color
	if name_label:
		name_label.modulate = color
