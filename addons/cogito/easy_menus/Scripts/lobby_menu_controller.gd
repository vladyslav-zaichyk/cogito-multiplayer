extends Control
## Controller for the Lobby Menu
## Displays connected players and allows host to start the game

signal start_game_pressed
signal leave_lobby_pressed

@export var sound_hover: AudioStream
@export var sound_click: AudioStream

@onready var server_info_label: Label = $ContentMain/ServerInfoLabel
@onready var players_list: VBoxContainer = $ContentMain/PlayersScrollContainer/PlayersList
@onready var start_game_button: Button = $ContentMain/ButtonContainer/StartGameButton
@onready var leave_lobby_button: Button = $ContentMain/ButtonContainer/LeaveLobbyButton
@onready var status_label: Label = $ContentMain/StatusLabel

var playback: AudioStreamPlaybackPolyphonic
var player_labels: Dictionary = {}  # player_id -> Label node


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
	
	# Set focus
	if leave_lobby_button:
		leave_lobby_button.grab_focus()
	
	# Connect to network events
	if NetworkEventBus:
		NetworkEventBus.player_registered.connect(_on_player_registered)
		NetworkEventBus.player_unregistered.connect(_on_player_unregistered)
		NetworkEventBus.network_connected.connect(_on_network_connected)
		NetworkEventBus.network_disconnected.connect(_on_network_disconnected)
	
	# Update UI
	_update_server_info()
	_update_start_button_visibility()
	_refresh_players_list()
	
	# Start update timer
	var timer = Timer.new()
	timer.wait_time = 0.5  # Update every 0.5 seconds
	timer.timeout.connect(_refresh_players_list)
	timer.autostart = true
	add_child(timer)


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


func _update_server_info() -> void:
	if not server_info_label:
		return
	
	if NetworkManager and NetworkManager.is_multiplayer():
		if NetworkManager.is_host():
			server_info_label.text = "Server: Host (You)"
		else:
			var local_peer_id = NetworkManager.get_local_peer_id()
			server_info_label.text = "Server: Client (Peer ID: %d)" % local_peer_id
	else:
		server_info_label.text = "Server: Not Connected"


func _update_start_button_visibility() -> void:
	if not start_game_button:
		return
	
	# Only show Start Game button for host
	if NetworkManager and NetworkManager.is_multiplayer() and NetworkManager.is_host():
		start_game_button.visible = true
	else:
		start_game_button.visible = false


func _refresh_players_list() -> void:
	if not players_list:
		return
	
	# Get all players from PlayerManager
	if not PlayerManager:
		return
	
	var all_player_ids = PlayerManager.get_all_player_ids()
	var current_label_ids = player_labels.keys()
	
	# Remove labels for players that no longer exist
	for player_id in current_label_ids:
		if player_id not in all_player_ids:
			var label = player_labels[player_id]
			if label:
				label.queue_free()
			player_labels.erase(player_id)
	
	# Add/update labels for existing players
	for player_id in all_player_ids:
		var player_node = PlayerManager.get_player(player_id)
		if not player_node:
			continue
		
		# Check if we need to create a new label
		if not player_labels.has(player_id):
			var label = Label.new()
			label.theme_override_font_sizes["font_size"] = 18
			players_list.add_child(label)
			player_labels[player_id] = label
		
		# Update label text
		var label = player_labels[player_id]
		if label:
			var player_name = "Player %d" % player_id
			if player_node.has_method("get") and player_node.get("player_name"):
				player_name = player_node.player_name
			
			var is_local = PlayerManager.has_local_player() and PlayerManager.get_local_player_id() == player_id
			var prefix = "[YOU] " if is_local else ""
			label.text = prefix + player_name + " (ID: %d)" % player_id


func _on_player_registered(player_id: int, player_node: Node) -> void:
	_refresh_players_list()
	_set_status("Player %d joined the lobby" % player_id, false)


func _on_player_unregistered(player_id: int) -> void:
	_refresh_players_list()
	_set_status("Player %d left the lobby" % player_id, false)


func _on_network_connected(peer_id: int) -> void:
	_update_server_info()
	_update_start_button_visibility()
	_refresh_players_list()


func _on_network_disconnected(peer_id: int) -> void:
	_update_server_info()
	_update_start_button_visibility()
	_refresh_players_list()
	_set_status("Disconnected from server", true)


func _on_start_game_pressed() -> void:
	# Only host can start the game
	if not NetworkManager or not NetworkManager.is_host():
		_set_status("Only the host can start the game!", true)
		return
	
	# Check if there are enough players
	if not PlayerManager:
		_set_status("PlayerManager not available!", true)
		return
	
	var player_count = PlayerManager.get_player_count()
	if player_count < 1:
		_set_status("Need at least 1 player to start!", true)
		return
	
	start_game_pressed.emit()


func _on_leave_lobby_pressed() -> void:
	# Disconnect from game
	if NetworkManager:
		NetworkManager.disconnect_from_game()
	
	leave_lobby_pressed.emit()


func _set_status(message: String, is_error: bool) -> void:
	if status_label:
		status_label.text = message
		if is_error:
			status_label.modulate = Color.RED
		else:
			status_label.modulate = Color.WHITE


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		accept_event()
		_on_leave_lobby_pressed()

