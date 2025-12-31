extends Node
## Save Manager for handling save/load operations.
## Provides abstraction over CogitoSceneManager for save operations.
## Note: This is an autoload singleton, not a class_name

## Enable/disable logging
var enable_logging: bool = false


func _ready() -> void:
	CogitoGlobals.debug_log(
		true, "SaveManager", "Save Manager initialized and ready."
	)


## Save player state for a specific player
## If player_id is -1, uses the active slot (single-player mode)
## If player_id is provided, saves to player-specific slot
func save_player_state(player: Node, slot: String, player_id: int = -1) -> void:
	if not CogitoSceneManager:
		push_error("SaveManager: CogitoSceneManager not found!")
		return
	
	CogitoSceneManager.save_player_state(player, slot, player_id)


## Load player state for a specific player
## If player_id is -1, uses the active slot (single-player mode)
## If player_id is provided, loads player-specific state
func load_player_state(player: Node, slot: String, player_id: int = -1) -> void:
	if not CogitoSceneManager:
		push_error("SaveManager: CogitoSceneManager not found!")
		return
	
	CogitoSceneManager.load_player_state(player, slot, player_id)


## Save scene state for the current scene
func save_scene_state(scene_name: String, slot: String) -> void:
	if not CogitoSceneManager:
		push_error("SaveManager: CogitoSceneManager not found!")
		return
	
	CogitoSceneManager.save_scene_state(scene_name, slot)


## Load scene state for a specific scene
func load_scene_state(scene_name: String, slot: String) -> void:
	if not CogitoSceneManager:
		push_error("SaveManager: CogitoSceneManager not found!")
		return
	
	CogitoSceneManager.load_scene_state(scene_name, slot)


## Load a saved game from a slot
func load_saved_game(slot: String, current_scene_name: String = "") -> void:
	if not CogitoSceneManager:
		push_error("SaveManager: CogitoSceneManager not found!")
		return
	
	CogitoSceneManager.loading_saved_game(slot, current_scene_name)


## Delete a save slot
func delete_save(slot: String) -> void:
	if not CogitoSceneManager:
		push_error("SaveManager: CogitoSceneManager not found!")
		return
	
	CogitoSceneManager.delete_save(slot)


## Copy slot saves to temp
func copy_slot_saves_to_temp(slot: String) -> bool:
	if not CogitoSceneManager:
		push_error("SaveManager: CogitoSceneManager not found!")
		return false
	
	return CogitoSceneManager.copy_slot_saves_to_temp(slot)


## Copy temp saves to slot
func copy_temp_saves_to_slot(slot: String) -> bool:
	if not CogitoSceneManager:
		push_error("SaveManager: CogitoSceneManager not found!")
		return false
	
	return CogitoSceneManager.copy_temp_saves_to_slot(slot)


## Delete temp saves
func delete_temp_saves() -> void:
	if not CogitoSceneManager:
		push_error("SaveManager: CogitoSceneManager not found!")
		return
	
	CogitoSceneManager.delete_temp_saves()


## Get existing player state for a slot
func get_existing_player_state(slot: String) -> CogitoPlayerState:
	if not CogitoSceneManager:
		push_error("SaveManager: CogitoSceneManager not found!")
		return null
	
	return CogitoSceneManager.get_existing_player_state(slot)


## Get existing scene state for a slot
func get_existing_scene_state(slot: String) -> CogitoSceneState:
	if not CogitoSceneManager:
		push_error("SaveManager: CogitoSceneManager not found!")
		return null
	
	return CogitoSceneManager.get_existing_scene_state(slot)


## Get active slot
func get_active_slot() -> String:
	if not CogitoSceneManager:
		return "A"
	return CogitoSceneManager._active_slot


## Switch active slot
func switch_active_slot(slot_name: String) -> void:
	if not CogitoSceneManager:
		push_error("SaveManager: CogitoSceneManager not found!")
		return
	
	CogitoSceneManager.switch_active_slot_to(slot_name)


## Get screenshot path for active slot
func get_active_slot_screenshot_path() -> String:
	if not CogitoSceneManager:
		return ""
	return CogitoSceneManager.get_active_slot_player_state_screenshot_path()

