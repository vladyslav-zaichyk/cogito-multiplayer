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
@onready var scene_selection_container: VBoxContainer = $ContentMain/SceneSelectionContainer
@onready var scene_option_button: OptionButton = $ContentMain/SceneSelectionContainer/SceneOptionButton
@onready var scene_description_label: Label = $ContentMain/SceneSelectionContainer/SceneDescriptionLabel

var playback: AudioStreamPlaybackPolyphonic
var player_labels: Dictionary = {}  # player_id -> Label node
var player_name_input: LineEdit = null  # Player name input field

## Selected scene path (for host)
var selected_scene_path: String = "res://addons/cogito/demo_scenes/cogito_1_legacy_demo.tscn"


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
	
	# Connect to WorldLoadingManager for scene loading completion
	if WorldLoadingManager:
		CogitoGlobals.debug_log(
			true,
			"LobbyMenu",
			"Connecting to WorldLoadingManager.all_peers_loaded signal"
		)
		WorldLoadingManager.all_peers_loaded.connect(_on_all_peers_loaded)
	else:
		CogitoGlobals.debug_log(
			true,
			"LobbyMenu",
			"WARNING: WorldLoadingManager not found!"
		)
	
	# Get player name input node
	player_name_input = get_node_or_null("ContentMain/PlayerNameContainer/PlayerNameInput")
	
	# Setup player name input
	_setup_player_name_input()
	
	# Update UI
	_update_server_info()
	_update_start_button_visibility()
	_refresh_players_list()
	_setup_scene_selection()
	
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
	
	# Also show connected peers (even if not spawned yet)
	# This helps show who's in the lobby before game starts
	var all_player_ids = PlayerManager.get_all_player_ids()
	var connected_peers = []
	if NetworkManager and NetworkManager.is_multiplayer():
		connected_peers = NetworkManager.get_connected_peers()
		if NetworkManager.is_host():
			connected_peers.append(1)  # Add host (peer ID 1)
		else:
			# Add local peer ID
			connected_peers.append(NetworkManager.get_local_peer_id())
	
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
		if not player_node or not is_instance_valid(player_node):
			continue
		
		# Check if we need to create a new label
		if not player_labels.has(player_id):
			var label = Label.new()
			label.add_theme_font_size_override("font_size", 18)
			players_list.add_child(label)
			player_labels[player_id] = label
		
		# Update label text
		var label = player_labels[player_id]
		if label:
			var player_name = PlayerManager.get_player_name(player_id)
			
			var is_local = PlayerManager.has_local_player() and PlayerManager.get_local_player_id() == player_id
			var prefix = "[YOU] " if is_local else ""
			label.text = prefix + player_name + " (ID: %d)" % player_id
	
	# Show connected peers count if no players spawned yet
	if all_player_ids.size() == 0 and connected_peers.size() > 0:
		# Show "Waiting for players..." or peer count
		var info_label = null
		if not player_labels.has(-1):  # Use -1 as special ID for info label
			info_label = Label.new()
			info_label.add_theme_font_size_override("font_size", 16)
			info_label.modulate = Color.GRAY
			players_list.add_child(info_label)
			player_labels[-1] = info_label
		else:
			info_label = player_labels[-1]
		
		if info_label:
			info_label.text = "Connected: %d peer(s) (players spawn after game starts)" % connected_peers.size()


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
	_setup_scene_selection()


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
	
	# In multiplayer, players are spawned after scene loads, not in lobby
	# So we don't need to check player count here - host can always start
	# Players will be registered when they spawn in the game scene
	
	# Load the game scene using WorldLoadingManager
	_set_status("Starting game...", false)
	
	# Use selected scene
	var demo_scene_path = selected_scene_path
	if demo_scene_path.is_empty():
		# Fallback to Legacy Demo
		demo_scene_path = "res://addons/cogito/demo_scenes/cogito_1_legacy_demo.tscn"
	
	if WorldLoadingManager:
		# Start loading scene and wait for all peers
		WorldLoadingManager.start_loading_scene(
			demo_scene_path,
			_on_all_peers_loaded
		)
	else:
		# Fallback: use old system
		if CogitoSceneManager:
			CogitoSceneManager.load_next_scene(
				demo_scene_path,
				"",
				"temp",
				CogitoSceneManager.CogitoSceneLoadMode.RESET
			)
	
	start_game_pressed.emit()


## Callback when all peers have loaded the scene
func _on_all_peers_loaded() -> void:
	var is_client = NetworkManager and NetworkManager.is_connected_client()
	var role = "[HOST]" if NetworkManager and NetworkManager.is_host() else "[CLIENT]"
	
	CogitoGlobals.debug_log(
		true,
		"LobbyMenu",
		"%s All peers loaded scene - ready to spawn players" % role
	)
	
	# Check if we're still in the tree
	if not is_inside_tree():
		CogitoGlobals.debug_log(
			true,
			"LobbyMenu",
			"%s Lobby menu not in tree (scene already changed)" % role
		)
		return
	
	# Check current scene
	var current_scene = get_tree().current_scene
	CogitoGlobals.debug_log(
		true,
		"LobbyMenu",
		"%s Current scene: %s" % [role, current_scene.get_name() if current_scene else "null"]
	)
	
	# Hide lobby menu
	CogitoGlobals.debug_log(
		true,
		"LobbyMenu",
		"%s Hiding lobby menu (visible=%s)" % [role, visible]
	)
	visible = false
	
	# Disable processing to prevent input handling
	set_process(false)
	set_process_input(false)
	
	CogitoGlobals.debug_log(
		true,
		"LobbyMenu",
		"%s Lobby menu hidden and processing disabled" % role
	)
	# Player spawning will be handled in Phase 1.1


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


## Setup scene selection UI (host only)
func _setup_scene_selection() -> void:
	if not scene_selection_container or not scene_option_button:
		return
	
	# Only show scene selection for host
	var is_host = NetworkManager and NetworkManager.is_multiplayer() and NetworkManager.is_host()
	scene_selection_container.visible = is_host
	
	if not is_host:
		return
	
	# Populate scene options
	scene_option_button.clear()
	var scene_config_script = load("res://addons/cogito/network/multiplayer_scene_config.gd")
	var scene_names = scene_config_script.get_scene_names()
	
	for scene_name in scene_names:
		scene_option_button.add_item(scene_name)
	
	# Set default selection (Legacy Demo)
	var default_index = 0
	for i in range(scene_names.size()):
		if scene_names[i] == "Legacy Demo":
			default_index = i
			break
	
	scene_option_button.selected = default_index
	selected_scene_path = scene_config_script.get_scene_path(scene_names[default_index])
	_update_scene_description()
	
	# Connect signal
	if not scene_option_button.item_selected.is_connected(_on_scene_selected):
		scene_option_button.item_selected.connect(_on_scene_selected)


## Update scene description label
func _update_scene_description() -> void:
	if not scene_description_label or not scene_option_button:
		return
	
	var scene_config_script = load("res://addons/cogito/network/multiplayer_scene_config.gd")
	var scene_names = scene_config_script.get_scene_names()
	var selected_index = scene_option_button.selected
	
	if selected_index >= 0 and selected_index < scene_names.size():
		var scene_name = scene_names[selected_index]
		var description = scene_config_script.get_scene_description(scene_name)
		scene_description_label.text = description
		
		# Update selected scene path
		selected_scene_path = scene_config_script.get_scene_path(scene_name)


## Callback when scene is selected
func _on_scene_selected(index: int) -> void:
	_update_scene_description()
	
	# Notify other players about scene change (optional, for future)
	# For now, just update locally


func _input(event: InputEvent) -> void:
	# Only process input if menu is visible
	if not visible:
		return
	
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		accept_event()
		_on_leave_lobby_pressed()


## Setup player name input field
func _setup_player_name_input() -> void:
	if not player_name_input:
		return
	
	# Set initial name from PlayerManager
	if PlayerManager and PlayerManager.has_local_player():
		var local_player_id = PlayerManager.get_local_player_id()
		var current_name = PlayerManager.get_player_name(local_player_id)
		if current_name == "You":
			# Set default name
			player_name_input.text = "Player"
			# Also set it in PlayerManager immediately
			_set_player_name("Player")
		else:
			player_name_input.text = current_name
	
	# Connect signal for name changes
	player_name_input.text_submitted.connect(_on_player_name_changed)
	# text_changed passes new_text as argument, but we ignore it in the handler
	player_name_input.text_changed.connect(_on_player_name_changed_deferred)


## Callback when player name is changed
func _on_player_name_changed(new_name: String) -> void:
	_set_player_name(new_name)


## Deferred callback for text_changed (to avoid too many updates)
## Note: text_changed signal passes new_text as argument, but we ignore it
func _on_player_name_changed_deferred(_new_text: String) -> void:
	# Use a timer to debounce rapid changes
	if not has_node("_name_change_timer"):
		var timer = Timer.new()
		timer.name = "_name_change_timer"
		timer.wait_time = 0.5  # Wait 0.5 seconds after last change
		timer.one_shot = true
		timer.timeout.connect(_on_name_change_timer_timeout)
		add_child(timer)
	
	var timer = get_node("_name_change_timer")
	timer.stop()
	timer.start()


func _on_name_change_timer_timeout() -> void:
	if player_name_input:
		_set_player_name(player_name_input.text)


## Set player name and sync via RPC
func _set_player_name(new_name: String) -> void:
	if new_name.is_empty():
		new_name = "Player"
	
	# Limit name length
	if new_name.length() > 20:
		new_name = new_name.substr(0, 20)
	
	if not PlayerManager or not PlayerManager.has_local_player():
		return
	
	var local_player_id = PlayerManager.get_local_player_id()
	if local_player_id == -1:
		return
	
	# Update in PlayerManager
	PlayerManager.set_player_name(local_player_id, new_name)
	
	# Sync via RPC if in multiplayer
	if NetworkManager and NetworkManager.is_multiplayer():
		var peer_id = NetworkManager.get_local_peer_id()
		NetworkManager.sync_player_name.rpc(peer_id, new_name)
	
	CogitoGlobals.debug_log(
		true,
		"LobbyMenu",
		"Player name set to: %s" % new_name
	)
