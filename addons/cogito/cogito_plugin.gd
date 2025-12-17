@tool
extends EditorPlugin
const COGITO_PLUGIN_ICON : Texture2D = preload("./Cogito.svg")
const COGITO_DEFAULT_SETTINGS = preload("./CogitoSettings.tres")

var cog_settings : CogitoSettings

var parser_plugin: EditorTranslationParserPlugin

func _enter_tree():
	add_autoload_singleton("CogitoGlobals", "/cogito_globals.gd")
	add_autoload_singleton("CogitoSceneManager", "/SceneManagement/cogito_scene_manager.gd")
	add_autoload_singleton("CogitoQuestManager", "/QuestSystem/cogito_quest_manager.gd")
	add_autoload_singleton("MenuTemplateManager", "/EasyMenus/Nodes/menu_template_manager.tscn")
	
	# Initialization of the plugin goes here.
	parser_plugin = load("res://addons/cogito/Localization/scripts/loc_resource_parser.gd").new()
	add_translation_parser_plugin(parser_plugin)
	
	cog_settings = COGITO_DEFAULT_SETTINGS
	

func _exit_tree():
	remove_autoload_singleton("CogitoQuestManager")
	remove_autoload_singleton("MenuTemplateManager")
	remove_autoload_singleton("CogitoSceneManager")
	remove_autoload_singleton("CogitoGlobals")
	
	remove_translation_parser_plugin(parser_plugin)



func _get_plugin_name():
	return "Cogito"


func _get_plugin_icon():
	return COGITO_PLUGIN_ICON
