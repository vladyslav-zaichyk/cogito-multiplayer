extends Control
## Controller for the Join Game Menu
## Handles connection to a multiplayer server

signal connect_pressed(address: String, port: int)
signal cancel_pressed

@export var sound_hover: AudioStream
@export var sound_click: AudioStream

@onready var ip_address_edit: LineEdit = $ContentMain/IPAddressContainer/IPAddressLineEdit
@onready var port_edit: LineEdit = $ContentMain/PortContainer/PortLineEdit
@onready var status_label: Label = $ContentMain/StatusLabel
@onready var connect_button: Button = $ContentMain/ButtonContainer/ConnectButton
@onready var cancel_button: Button = $ContentMain/ButtonContainer/CancelButton

var playback: AudioStreamPlaybackPolyphonic
var is_connecting: bool = false


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
	if ip_address_edit:
		ip_address_edit.text = "127.0.0.1"
	if port_edit:
		port_edit.text = "7777"
	
	# Set focus
	if connect_button:
		connect_button.grab_focus()
	
	# Connect to network events
	if NetworkEventBus:
		NetworkEventBus.network_connected.connect(_on_network_connected)
		NetworkEventBus.network_error.connect(_on_network_error)
		NetworkEventBus.network_disconnected.connect(_on_network_disconnected)


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


func _on_connect_pressed() -> void:
	if is_connecting:
		return
	
	# Validate inputs
	var ip_address = ip_address_edit.text.strip_edges()
	var port_text = port_edit.text.strip_edges()
	
	# Validate IP address
	if ip_address.is_empty():
		_set_status("IP address cannot be empty!", true)
		return
	
	# Basic IP validation (can be improved)
	if not _is_valid_ip(ip_address) and not _is_valid_hostname(ip_address):
		_set_status("Invalid IP address or hostname!", true)
		return
	
	# Validate port
	if port_text.is_empty():
		_set_status("Port cannot be empty!", true)
		return
	
	var port = port_text.to_int()
	if port <= 0 or port > 65535:
		_set_status("Port must be between 1 and 65535!", true)
		return
	
	# Try to connect
	is_connecting = true
	_set_status("Connecting to %s:%d..." % [ip_address, port], false)
	connect_button.disabled = true
	
	if NetworkManager and NetworkManager.join_game(ip_address, port):
		# Connection attempt started
		_set_status("Connecting...", false)
	else:
		# Connection failed immediately
		_set_status("Failed to start connection. Check console for details.", true)
		is_connecting = false
		connect_button.disabled = false


func _on_cancel_pressed() -> void:
	# Disconnect if connecting
	if is_connecting and NetworkManager:
		NetworkManager.disconnect_from_game()
		is_connecting = false
		connect_button.disabled = false
	
	cancel_pressed.emit()


func _on_network_connected(peer_id: int) -> void:
	is_connecting = false
	connect_button.disabled = false
	_set_status("Connected! Peer ID: %d" % peer_id, false)
	# Emit signal for parent to handle navigation
	connect_pressed.emit(ip_address_edit.text.strip_edges(), port_edit.text.strip_edges().to_int())


func _on_network_error(error: String) -> void:
	is_connecting = false
	connect_button.disabled = false
	_set_status("Connection error: %s" % error, true)


func _on_network_disconnected(peer_id: int) -> void:
	if is_connecting:
		is_connecting = false
		connect_button.disabled = false
		_set_status("Disconnected from server.", true)


func _set_status(message: String, is_error: bool) -> void:
	if status_label:
		status_label.text = message
		if is_error:
			status_label.modulate = Color.RED
		else:
			status_label.modulate = Color.WHITE


func _is_valid_ip(ip: String) -> bool:
	# Basic IPv4 validation
	var parts = ip.split(".")
	if parts.size() != 4:
		return false
	
	for part in parts:
		var num = part.to_int()
		if num < 0 or num > 255:
			return false
	
	return true


func _is_valid_hostname(hostname: String) -> bool:
	# Basic hostname validation (allows localhost, domain names, etc.)
	if hostname.is_empty():
		return false
	
	# Allow localhost
	if hostname == "localhost":
		return true
	
	# Basic check: contains only valid characters
	var valid_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"
	for char in hostname:
		if not valid_chars.contains(char):
			return false
	
	return true


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		accept_event()
		_on_cancel_pressed()

