extends Node
## Scene Manager for handling scene transitions and loading.
## Provides abstraction over CogitoSceneManager for scene operations.
## Note: This is an autoload singleton, not a class_name

## Enable/disable logging
var enable_logging: bool = false


func _ready() -> void:
	CogitoGlobals.debug_log(
		true, "SceneManager", "Scene Manager initialized and ready."
	)


## Load the next scene with optional transition
func load_next_scene(
	scene_path: String,
	scene_name: String = "",
	slot: String = "",
	load_mode: CogitoSceneManager.CogitoSceneLoadMode = CogitoSceneManager.CogitoSceneLoadMode.TEMP
) -> void:
	if not CogitoSceneManager:
		push_error("SceneManager: CogitoSceneManager not found!")
		return
	
	CogitoSceneManager.load_next_scene(scene_path, scene_name, slot, load_mode)


## Load scene state for a specific scene
func load_scene_state(scene_name: String, slot: String) -> void:
	if not CogitoSceneManager:
		push_error("SceneManager: CogitoSceneManager not found!")
		return
	
	CogitoSceneManager.load_scene_state(scene_name, slot)


## Save scene state for the current scene
func save_scene_state(scene_name: String, slot: String) -> void:
	if not CogitoSceneManager:
		push_error("SceneManager: CogitoSceneManager not found!")
		return
	
	CogitoSceneManager.save_scene_state(scene_name, slot)


## Reset scene states
func reset_scene_states() -> void:
	if not CogitoSceneManager:
		push_error("SceneManager: CogitoSceneManager not found!")
		return
	
	CogitoSceneManager.reset_scene_states()


## Get current scene name
func get_current_scene_name() -> String:
	if not CogitoSceneManager:
		return ""
	return CogitoSceneManager._current_scene_name


## Get current scene path
func get_current_scene_path() -> String:
	if not CogitoSceneManager:
		return ""
	return CogitoSceneManager._current_scene_path


## Fade in (show scene)
func fade_in(fade_duration: float = -1.0) -> void:
	if not CogitoSceneManager:
		push_error("SceneManager: CogitoSceneManager not found!")
		return
	
	if fade_duration < 0:
		CogitoSceneManager.fade_in()
	else:
		CogitoSceneManager.fade_in(fade_duration)


## Fade out (hide scene)
func fade_out(fade_duration: float = -1.0) -> void:
	if not CogitoSceneManager:
		push_error("SceneManager: CogitoSceneManager not found!")
		return
	
	if fade_duration < 0:
		CogitoSceneManager.fade_out()
	else:
		CogitoSceneManager.fade_out(fade_duration)


## Check if currently loading
func is_loading() -> bool:
	if not CogitoSceneManager:
		return false
	return CogitoSceneManager.is_currently_loading

