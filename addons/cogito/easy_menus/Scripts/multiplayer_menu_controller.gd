extends Control
## Controller for the Multiplayer Menu
## Handles navigation to Host Game and Join Game menus

signal host_game_pressed
signal join_game_pressed
signal back_pressed

@export var first_focus_button: Button
@export var sound_hover: AudioStream
@export var sound_click: AudioStream

## Paths to menu scenes
const HOST_GAME_MENU_PATH = "res://addons/cogito/easy_menus/Scenes/host_game_menu.tscn"
const JOIN_GAME_MENU_PATH = "res://addons/cogito/easy_menus/Scenes/join_game_menu.tscn"

var playback: AudioStreamPlaybackPolyphonic


func _ready() -> void:
	# Create an audio player
	var player = AudioStreamPlayer.new()
	add_child(player)
	
	# Create a polyphonic stream so we can play sounds directly from it
	var stream = AudioStreamPolyphonic.new()
	stream.polyphony = 32
	player.stream = stream
	player.play()
	# Get the polyphonic playback stream to play sounds
	playback = player.get_stream_playback()
	
	# Connect button signals for audio
	get_tree().node_added.connect(_on_node_added)
	
	# Set focus to first button
	if not first_focus_button:
		first_focus_button = $ContentMain/HostGameButton
	if first_focus_button:
		first_focus_button.grab_focus()


func _on_node_added(node: Node) -> void:
	if node is Button:
		# If the added node is a button we connect to its mouse_entered and pressed signals
		# and play a sound
		node.mouse_entered.connect(_play_hover)
		node.pressed.connect(_play_pressed)


func _play_hover() -> void:
	if sound_hover:
		playback.play_stream(sound_hover, 0, 0, 1)


func _play_pressed() -> void:
	if sound_click:
		playback.play_stream(sound_click, 0, 0, 1)


func _on_host_game_pressed() -> void:
	host_game_pressed.emit()
	# Load host game menu
	_load_menu_scene(HOST_GAME_MENU_PATH)


func _on_join_game_pressed() -> void:
	join_game_pressed.emit()
	# Load join game menu
	_load_menu_scene(JOIN_GAME_MENU_PATH)


func _on_back_pressed() -> void:
	back_pressed.emit()
	# Go back to main menu (or close if no parent menu)
	_go_back()


## Load a menu scene and replace current menu
func _load_menu_scene(scene_path: String) -> void:
	var scene = load(scene_path) as PackedScene
	if not scene:
		push_error("MultiplayerMenu: Failed to load scene: %s" % scene_path)
		return
	
	var instance = scene.instantiate()
	if not instance:
		push_error("MultiplayerMenu: Failed to instantiate scene: %s" % scene_path)
		return
	
	# Replace current scene
	var tree = get_tree()
	if tree:
		var parent = get_parent()
		if not parent:
			# If no parent, add to root
			parent = tree.root
		
		# Hide current menu
		visible = false
		
		# Add new menu to scene tree
		parent.add_child(instance)
		
		# Remove current menu after a frame
		call_deferred("queue_free")


## Go back to previous menu
func _go_back() -> void:
	# If we're in a menu hierarchy, go back
	# For now, just close this menu
	var tree = get_tree()
	if tree:
		# Try to find main menu or go to scene tree root
		var root = tree.root
		if root:
			# Look for main menu
			var main_menu = root.find_child("MainMenu", true, false)
			if main_menu:
				main_menu.visible = true
				queue_free()
			else:
				# Just remove this menu
				queue_free()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		accept_event()
		back_pressed.emit()

