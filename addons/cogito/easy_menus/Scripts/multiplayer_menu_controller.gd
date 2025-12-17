extends Control
## Controller for the Multiplayer Menu
## Handles navigation to Host Game and Join Game menus

signal host_game_pressed
signal join_game_pressed
signal back_pressed

@export var first_focus_button: Button
@export var sound_hover: AudioStream
@export var sound_click: AudioStream

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


func _on_join_game_pressed() -> void:
	join_game_pressed.emit()


func _on_back_pressed() -> void:
	back_pressed.emit()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		accept_event()
		back_pressed.emit()

