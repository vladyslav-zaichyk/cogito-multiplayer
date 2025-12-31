extends RefCounted
## Configuration for multiplayer scenes
## Stores available scenes and their metadata
## Note: This is a static utility class, not a Resource

## Available demo scenes for multiplayer
const AVAILABLE_SCENES: Array[Dictionary] = [
	{
		"name": "Legacy Demo",
		"path": "res://addons/cogito/demo_scenes/cogito_1_legacy_demo.tscn",
		"description": "Original demo scene with basic interactions"
	},
	{
		"name": "Lobby",
		"path": "res://addons/cogito/demo_scenes/cogito_3_lobby.tscn",
		"description": "Lobby scene for testing"
	},
	{
		"name": "Laboratory",
		"path": "res://addons/cogito/demo_scenes/cogito_4_laboratory.tscn",
		"description": "Laboratory scene"
	}
]

## Get scene path by name
static func get_scene_path(scene_name: String) -> String:
	for scene in AVAILABLE_SCENES:
		if scene.name == scene_name:
			return scene.path
	return ""

## Get all available scene names
static func get_scene_names() -> Array[String]:
	var names: Array[String] = []
	for scene in AVAILABLE_SCENES:
		names.append(scene.name)
	return names

## Get scene description
static func get_scene_description(scene_name: String) -> String:
	for scene in AVAILABLE_SCENES:
		if scene.name == scene_name:
			return scene.get("description", "")
	return ""

