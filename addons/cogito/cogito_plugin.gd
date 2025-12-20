@tool
extends EditorPlugin
const cogito_plugin_icon: Texture2D = preload("./Cogito.svg")
const cogito_default_settings = preload("./CogitoSettings.tres")

var cog_settings: CogitoSettings

var parser_plugin: EditorTranslationParserPlugin


func _enter_tree():
	add_autoload_singleton("CogitoGlobals", "/cogito_globals.gd")
	add_autoload_singleton("CogitoSceneManager", "/scene_management/cogito_scene_manager.gd")
	add_autoload_singleton("CogitoQuestManager", "/quest_system/cogito_quest_manager.gd")
	add_autoload_singleton("MenuTemplateManager", "/easy_menus/Nodes/menu_template_manager.tscn")
	add_autoload_singleton("NetworkEventBus", "/network/event_bus.gd")
	add_autoload_singleton("PlayerManager", "/network/player_manager.gd")
	add_autoload_singleton("InventoryManager", "/network/inventory_manager.gd")
	add_autoload_singleton("WorldStateManager", "/network/world_state_manager.gd")
	add_autoload_singleton("NetworkManager", "/network/network_manager.gd")
	add_autoload_singleton("SceneManager", "/scene_management/scene_manager.gd")
	add_autoload_singleton("SaveManager", "/scene_management/save_manager.gd")
	add_autoload_singleton("PlayerStateManager", "/scene_management/player_state_manager.gd")
	add_autoload_singleton("WorldLoadingManager", "/network/world_loading_manager.gd")
	add_autoload_singleton("PlayerSpawner", "/network/player_spawner.gd")
	add_autoload_singleton("CommandBus", "/network/commands/command_bus.gd")
	add_autoload_singleton("ResponseHandler", "/network/commands/response_handler.gd")

	# Initialization of the plugin goes here.
	parser_plugin = load("res://addons/cogito/Localization/scripts/loc_resource_parser.gd").new()
	add_translation_parser_plugin(parser_plugin)

	cog_settings = cogito_default_settings


func _exit_tree():
	remove_autoload_singleton("CogitoQuestManager")
	remove_autoload_singleton("MenuTemplateManager")
	remove_autoload_singleton("CogitoSceneManager")
	remove_autoload_singleton("CogitoGlobals")
	remove_autoload_singleton("NetworkEventBus")
	remove_autoload_singleton("PlayerManager")
	remove_autoload_singleton("InventoryManager")
	remove_autoload_singleton("WorldStateManager")
	remove_autoload_singleton("NetworkManager")
	remove_autoload_singleton("SceneManager")
	remove_autoload_singleton("SaveManager")
	remove_autoload_singleton("PlayerStateManager")
	remove_autoload_singleton("WorldLoadingManager")
	remove_autoload_singleton("PlayerSpawner")
	remove_autoload_singleton("CommandBus")
	remove_autoload_singleton("ResponseHandler")

	remove_translation_parser_plugin(parser_plugin)


func _get_plugin_name():
	return "Cogito"


func _get_plugin_icon():
	return cogito_plugin_icon
