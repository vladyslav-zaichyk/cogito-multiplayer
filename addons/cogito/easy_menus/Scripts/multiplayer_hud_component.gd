extends Control
## Multiplayer HUD Component
## Displays multiplayer information (player count, ping, connection status)
## Can be added to any HUD scene

@onready var players_label: Label = $VBoxContainer/PlayersLabel
@onready var ping_label: Label = $VBoxContainer/PingLabel
@onready var connection_status_label: Label = $VBoxContainer/ConnectionStatusLabel

var ping_update_timer: Timer
var last_ping_time: float = 0.0


func _ready() -> void:
	# Hide if not in multiplayer
	if not NetworkManager or not NetworkManager.is_multiplayer():
		hide()
		return
	
	show()
	
	# Connect to network events
	if NetworkEventBus:
		NetworkEventBus.player_registered.connect(_on_player_registered)
		NetworkEventBus.player_unregistered.connect(_on_player_unregistered)
		NetworkEventBus.network_connected.connect(_on_network_connected)
		NetworkEventBus.network_disconnected.connect(_on_network_disconnected)
	
	# Create ping update timer
	ping_update_timer = Timer.new()
	ping_update_timer.wait_time = 1.0  # Update ping every second
	ping_update_timer.timeout.connect(_update_ping)
	ping_update_timer.autostart = true
	add_child(ping_update_timer)
	
	# Initial update
	_update_players_count()
	_update_connection_status()


func _process(_delta: float) -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# Update ping display
	_update_ping_display()


func _update_players_count() -> void:
	if not players_label:
		return
	
	if not PlayerManager:
		players_label.text = "Players: --"
		return
	
	var player_count = PlayerManager.get_player_count()
	var max_players = 4  # Default, can be improved
	
	if NetworkManager:
		max_players = NetworkManager.max_players
	
	players_label.text = "Players: %d/%d" % [player_count, max_players]


func _update_ping() -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# Calculate ping (simplified - in real implementation, you'd measure RTT)
	# For now, we'll use a placeholder
	last_ping_time = Time.get_ticks_msec()


func _update_ping_display() -> void:
	if not ping_label:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		ping_label.text = "Ping: -- ms"
		return
	
	# Get ping from multiplayer peer if available
	var ping_ms = 0
	if NetworkManager.multiplayer_peer:
		# ENet provides RTT, but we need to calculate it properly
		# For now, use a placeholder
		ping_ms = 0  # Will be implemented properly later
	
	if ping_ms > 0:
		ping_label.text = "Ping: %d ms" % ping_ms
		
		# Color code based on ping
		if ping_ms < 50:
			ping_label.modulate = Color.GREEN
		elif ping_ms < 100:
			ping_label.modulate = Color.YELLOW
		else:
			ping_label.modulate = Color.RED
	else:
		ping_label.text = "Ping: -- ms"
		ping_label.modulate = Color.WHITE


func _update_connection_status() -> void:
	if not connection_status_label:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		connection_status_label.text = "Disconnected"
		connection_status_label.modulate = Color.RED
		return
	
	if NetworkManager.is_host():
		connection_status_label.text = "Host"
		connection_status_label.modulate = Color.CYAN
	elif NetworkManager.is_connected_client():
		connection_status_label.text = "Connected"
		connection_status_label.modulate = Color.GREEN
	else:
		connection_status_label.text = "Connecting..."
		connection_status_label.modulate = Color.YELLOW


func _on_player_registered(player_id: int, player_node: Node) -> void:
	_update_players_count()


func _on_player_unregistered(player_id: int) -> void:
	_update_players_count()


func _on_network_connected(peer_id: int) -> void:
	_update_connection_status()
	_update_players_count()


func _on_network_disconnected(peer_id: int) -> void:
	_update_connection_status()
	_update_players_count()

