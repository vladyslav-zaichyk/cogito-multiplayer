extends Area3D

### Level scene to transition to
@export var target_scene: PackedScene = null
## Level scene to transition to
@export_file("*.tscn") var target_scene_path: String
## Name of connector node the player should transition to in target scene. This node needs to exist in the target scene and has to be added to the connector array of the target scene cogito_scene script.
@export var target_connector: String

var current_scene_statename: String
var current_scene_filepath: String


func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D):
	if !body.is_in_group("Player"):
		return

	transition_to_next_scene()


func _on_body_exited(body: Node3D):
	if !body.is_in_group("Player"):
		return


func transition_to_next_scene():
	current_scene_statename = get_tree().get_current_scene().get_name()
	CogitoSceneManager.save_scene_state(current_scene_statename, "temp")
	# Get player from PlayerManager (new system) or fallback to old system
	var player = PlayerManager.get_current_player() if PlayerManager else null
	if not player and CogitoSceneManager and CogitoSceneManager.has_method("get") and CogitoSceneManager.get("_current_player_node"):
		player = CogitoSceneManager._current_player_node
	CogitoSceneManager.save_player_state(player, "temp")

	CogitoSceneManager.is_currently_loading = true

	CogitoSceneManager.fade_out()
	await CogitoSceneManager.fade_finished

	# CogitoSceneManager.load_next_scene(path_to_new_scene, target_connector, "temp", CogitoSceneManager.CogitoSceneLoadMode.TEMP)
	CogitoSceneManager.load_next_scene(
		target_scene_path, target_connector, "temp", CogitoSceneManager.CogitoSceneLoadMode.TEMP
	)
