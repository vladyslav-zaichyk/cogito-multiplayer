extends Node
## Extension for Pause Menu to add multiplayer functionality
## This script can be added to PauseMenu to add "Leave Game" button
## without modifying the original pause_menu_controller.gd

signal leave_game_pressed

@onready var pause_menu: Control = get_parent() if get_parent() is Control else null
var leave_game_button: Button = null


func _ready() -> void:
	# Wait for pause menu to be ready
	if pause_menu:
		await pause_menu.ready
	
	# Only add multiplayer features if in multiplayer mode
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	_add_leave_game_button()


func _add_leave_game_button() -> void:
	if not pause_menu:
		return
	
	# Find the game menu container
	var game_menu = pause_menu.get_node_or_null("Content/GameMenu/VBoxContainer")
	if not game_menu:
		return
	
	# Check if button already exists
	if game_menu.has_node("LeaveGameButton"):
		leave_game_button = game_menu.get_node("LeaveGameButton")
		return
	
	# Create separator
	var separator = HSeparator.new()
	game_menu.add_child(separator)
	
	# Create Leave Game button
	leave_game_button = Button.new()
	leave_game_button.name = "LeaveGameButton"
	leave_game_button.text = "Leave Game"
	leave_game_button.theme_override_font_sizes["font_size"] = 30
	leave_game_button.pressed.connect(_on_leave_game_pressed)
	
	# Add script for UI button behavior if available
	if ResourceLoader.exists("res://addons/cogito/Theme/cogito_ui_button.gd"):
		var script = load("res://addons/cogito/Theme/cogito_ui_button.gd")
		leave_game_button.set_script(script)
	
	game_menu.add_child(leave_game_button)
	
	# Connect to pause menu audio if available
	if pause_menu.has_method("_on_node_added"):
		pause_menu._on_node_added(leave_game_button)


func _on_leave_game_pressed() -> void:
	# Disconnect from game
	if NetworkManager:
		NetworkManager.disconnect_from_game()
	
	# Close pause menu
	if pause_menu and pause_menu.has_method("close_pause_menu"):
		pause_menu.close_pause_menu()
	
	# Emit signal
	leave_game_pressed.emit()

