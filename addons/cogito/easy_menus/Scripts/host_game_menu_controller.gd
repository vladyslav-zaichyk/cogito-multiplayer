extends Control
## Controller for the Host Game Menu
## Handles server hosting configuration and startup

signal start_server_pressed(server_name: String, port: int, max_players: int)
signal cancel_pressed

@export var sound_hover: AudioStream
@export var sound_click: AudioStream

const LOBBY_MENU_PATH = "res://addons/cogito/easy_menus/Scenes/lobby_menu.tscn"

@onready var server_name_edit: LineEdit = $ContentMain/ServerNameContainer/ServerNameLineEdit
@onready var port_edit: LineEdit = $ContentMain/PortContainer/PortLineEdit
@onready var max_players_spin: SpinBox = $ContentMain/MaxPlayersContainer/MaxPlayersSpinBox
@onready var status_label: Label = $ContentMain/StatusLabel
@onready var start_button: Button = $ContentMain/ButtonContainer/StartServerButton
@onready var cancel_button: Button = $ContentMain/ButtonContainer/CancelButton

var playback: AudioStreamPlaybackPolyphonic


func _ready() -> void:
	# Create an audio player
	var player = AudioStreamPlayer.new()
	add_child(player)
	
	# Create a polyphonic stream
	var stream = AudioStreamPolyphonic.new()
	stream.polyphony = 32
	player.stream = stream
	player.play()
	playback = player.get_stream_playback()
	
	# Connect button signals for audio
	get_tree().node_added.connect(_on_node_added)
	
	# Set default values
	if server_name_edit:
		server_name_edit.text = "My Server"
	if port_edit:
		port_edit.text = "7777"
	if max_players_spin:
		max_players_spin.value = 4
	
	# Set focus
	if start_button:
		start_button.grab_focus()
	
	# Connect to network events through NetworkEventBus
	if NetworkEventBus:
		NetworkEventBus.network_connected.connect(_on_network_connected)
		NetworkEventBus.network_error.connect(_on_network_error)


func _on_node_added(node: Node) -> void:
	if node is Button:
		node.mouse_entered.connect(_play_hover)
		node.pressed.connect(_play_pressed)


func _play_hover() -> void:
	if sound_hover:
		playback.play_stream(sound_hover, 0, 0, 1)


func _play_pressed() -> void:
	if sound_click:
		playback.play_stream(sound_click, 0, 0, 1)


func _on_start_server_pressed() -> void:
	# Validate inputs
	var server_name = server_name_edit.text.strip_edges()
	var port_text = port_edit.text.strip_edges()
	var max_players = int(max_players_spin.value)
	
	# Validate server name
	if server_name.is_empty():
		_set_status("Server name cannot be empty!", true)
		return
	
	# Validate port
	if port_text.is_empty():
		_set_status("Port cannot be empty!", true)
		return
	
	var port = port_text.to_int()
	if port <= 0 or port > 65535:
		_set_status("Port must be between 1 and 65535!", true)
		return
	
	# Validate max players
	if max_players < 2:
		_set_status("Max players must be at least 2!", true)
		return
	
	# Try to start hosting
	_set_status("Starting server...", false)
	
	if NetworkManager and NetworkManager.start_hosting(port, max_players):
		# Success - emit signal for parent to handle navigation
		start_server_pressed.emit(server_name, port, max_players)
		_set_status("Server started successfully!", false)
	else:
		_set_status("Failed to start server. Check console for details.", true)


func _on_cancel_pressed() -> void:
	cancel_pressed.emit()


func _on_network_connected(peer_id: int) -> void:
	_set_status("Connected! Peer ID: %d" % peer_id, false)
	# Load lobby menu after successful connection
	_load_lobby_menu()


func _on_network_error(error: String) -> void:
	_set_status("Network error: %s" % error, true)


func _set_status(message: String, is_error: bool) -> void:
	if status_label:
		status_label.text = message
		if is_error:
			status_label.modulate = Color.RED
		else:
			status_label.modulate = Color.WHITE


func _load_lobby_menu() -> void:
	var scene = load(LOBBY_MENU_PATH) as PackedScene
	if not scene:
		push_error("HostGameMenu: Failed to load lobby menu")
		return
	
	var instance = scene.instantiate()
	if not instance:
		push_error("HostGameMenu: Failed to instantiate lobby menu")
		return
	
	# Replace current menu
	var tree = get_tree()
	if tree:
		visible = false
		get_parent().add_child(instance)
		call_deferred("queue_free")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		accept_event()
		cancel_pressed.emit()

