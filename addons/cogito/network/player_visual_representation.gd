extends Node3D
## Player Visual Representation Component
## Creates a simple visual representation for multiplayer players
## Attach this to a CharacterBody3D (like CogitoPlayer)

## Enable/disable logging
var enable_logging: bool = false

## Player name to display
var player_name: String = "Player"

## Player ID
var player_id: int = -1

## Peer ID (for multiplayer)
var peer_id: int = -1

## Reference to the parent CharacterBody3D
var parent_body: CharacterBody3D = null

## Reference to the name label
var name_label: Label3D = null

## Reference to the visual mesh
var visual_mesh: MeshInstance3D = null

## Colors for different players
var player_colors: Array[Color] = [
	Color(1.0, 0.2, 0.2),  # Red
	Color(0.2, 0.2, 1.0),  # Blue
	Color(0.2, 1.0, 0.2),  # Green
	Color(1.0, 1.0, 0.2),  # Yellow
	Color(1.0, 0.2, 1.0),  # Magenta
	Color(0.2, 1.0, 1.0),  # Cyan
	Color(1.0, 0.5, 0.2),  # Orange
	Color(0.5, 0.2, 1.0),  # Purple
]


func _ready() -> void:
	parent_body = get_parent() as CharacterBody3D
	if not parent_body:
		push_error("PlayerVisualRepresentation: Parent must be a CharacterBody3D")
		return
	
	# Wait a frame for player to be initialized
	await get_tree().process_frame
	
	# Get player ID and peer_id
	if parent_body.has_method("get") and parent_body.get("player_id"):
		player_id = parent_body.player_id
	else:
		# Try to get from PlayerManager
		if PlayerManager:
			player_id = PlayerManager.get_player_id(parent_body)
	
	# Get peer_id - try multiple methods
	peer_id = -1
	if PlayerManager and player_id != -1:
		peer_id = PlayerManager.get_player_peer_id(player_id)
		if peer_id == -1 and NetworkManager and NetworkManager.is_multiplayer():
			# Try to get from local player
			if PlayerManager.has_local_player() and PlayerManager.get_local_player_id() == player_id:
				peer_id = NetworkManager.get_local_peer_id()
			# Try to get from parent if it has peer_id
			elif parent_body.has_method("get") and parent_body.get("peer_id") != null:
				peer_id = parent_body.peer_id
			elif parent_body.has_method("get_meta") and parent_body.has_meta("peer_id"):
				peer_id = parent_body.get_meta("peer_id")
	
	# If peer_id is still -1, wait a bit and retry (peer_id might be set after registration)
	if peer_id == -1 and NetworkManager and NetworkManager.is_multiplayer():
		await get_tree().process_frame
		await get_tree().process_frame
		if PlayerManager and player_id != -1:
			peer_id = PlayerManager.get_player_peer_id(player_id)
			if peer_id == -1 and PlayerManager.has_local_player() and PlayerManager.get_local_player_id() == player_id:
				peer_id = NetworkManager.get_local_peer_id()
	
	# Enable logging for debugging
	enable_logging = true
	CogitoGlobals.debug_log(
		true,  # Always log this
		"PlayerVisualRepresentation",
		"Initializing: player_id=%d, peer_id=%d" % [player_id, peer_id]
	)
	
	# Wait a bit more for player to be fully registered and name to be set
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Get player name from PlayerManager (using PlayerData if available)
	if PlayerManager and player_id != -1:
		# First try to get from PlayerData by peer_id (most reliable)
		if peer_id != -1:
			var data_name = PlayerManager.get_player_name_by_peer_id(peer_id)
			if not data_name.is_empty() and not data_name.begins_with("Player "):
				player_name = data_name
				CogitoGlobals.debug_log(
					true,  # Always log this
					"PlayerVisualRepresentation",
					"Got name from PlayerData: %s (peer_id: %d)" % [player_name, peer_id]
				)
		
		# Fallback to get_player_name
		if player_name == "Player" or player_name.begins_with("Player "):
			player_name = PlayerManager.get_player_name(player_id)
			CogitoGlobals.debug_log(
				true,  # Always log this
				"PlayerVisualRepresentation",
				"Got name from get_player_name: %s (player_id: %d)" % [player_name, player_id]
			)
		
		# If name is still default, wait a bit more (name might be syncing via RPC)
		if player_name == "You" or player_name.begins_with("Player "):
			# Wait a bit more for name sync
			await get_tree().create_timer(0.5).timeout
			if peer_id != -1:
				var data_name = PlayerManager.get_player_name_by_peer_id(peer_id)
				if not data_name.is_empty() and not data_name.begins_with("Player "):
					player_name = data_name
					CogitoGlobals.debug_log(
						true,  # Always log this
						"PlayerVisualRepresentation",
						"Got name from PlayerData after wait: %s (peer_id: %d)" % [player_name, peer_id]
					)
			if player_name == "You" or player_name.begins_with("Player "):
				player_name = PlayerManager.get_player_name(player_id)
				CogitoGlobals.debug_log(
					true,  # Always log this
					"PlayerVisualRepresentation",
					"Got name from get_player_name after wait: %s (player_id: %d)" % [player_name, player_id]
				)
	
	# Create visual representation
	_create_visual_representation()
	
	# Subscribe to player_data_updated signal
	if NetworkEventBus and peer_id != -1:
		NetworkEventBus.player_data_updated.connect(_on_player_data_updated)
	
	# Also subscribe to name changes in PlayerManager (backward compatibility)
	if PlayerManager and player_id != -1:
		# Start a timer to periodically check for name updates
		var name_check_timer = Timer.new()
		name_check_timer.wait_time = 0.5  # Check every 0.5 seconds
		name_check_timer.timeout.connect(_check_name_update)
		name_check_timer.autostart = true
		add_child(name_check_timer)
		# Stop checking after 5 seconds (names should be synced by then)
		await get_tree().create_timer(5.0).timeout
		name_check_timer.stop()
		name_check_timer.queue_free()
	
	CogitoGlobals.debug_log(
		enable_logging,
		"PlayerVisualRepresentation",
		"Created visual representation for player %d (peer_id: %d): %s" % [player_id, peer_id, player_name]
	)


## Create visual representation
func _create_visual_representation() -> void:
	# Create capsule mesh for player body
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.radius = 0.3
	capsule_mesh.height = 1.6
	capsule_mesh.radial_segments = 16
	
	# Create mesh instance
	visual_mesh = MeshInstance3D.new()
	visual_mesh.mesh = capsule_mesh
	
	# Set color based on player ID
	var color_index = (player_id - 1) % player_colors.size()
	var player_color = player_colors[color_index]
	
	# Create material with color
	var material = StandardMaterial3D.new()
	material.albedo_color = player_color
	material.metallic = 0.0
	material.roughness = 0.8
	visual_mesh.material_override = material
	
	# Position mesh (centered on player)
	visual_mesh.position = Vector3(0, 0.8, 0)  # Half height offset
	
	add_child(visual_mesh)
	
	# Create name label above player
	_create_name_label()


## Create name label above player
func _create_name_label() -> void:
	name_label = Label3D.new()
	name_label.text = player_name
	name_label.font_size = 24
	name_label.pixel_size = 0.01
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	
	# Set outline for better visibility
	# Label3D has outline_size and outline_modulate properties directly
	name_label.outline_size = 6
	name_label.outline_modulate = Color(0, 0, 0, 1)
	
	# Position label above player head
	name_label.position = Vector3(0, 2.0, 0)  # Above the capsule
	
	# Set text color based on player
	var color_index = (player_id - 1) % player_colors.size()
	var player_color = player_colors[color_index]
	name_label.modulate = player_color
	
	add_child(name_label)


## Update player name
func update_player_name(new_name: String) -> void:
	if new_name.is_empty():
		return
	
	player_name = new_name
	if name_label:
		name_label.text = player_name
		CogitoGlobals.debug_log(
			true,  # Always log this for debugging
			"PlayerVisualRepresentation",
			"Name label updated for player %d (peer_id: %d): %s" % [player_id, PlayerManager.get_player_peer_id(player_id) if PlayerManager and player_id != -1 else -1, player_name]
		)
	else:
		CogitoGlobals.debug_log(
			true,  # Always log this for debugging
			"PlayerVisualRepresentation",
			"Name updated for player %d: %s (but name_label is null)" % [player_id, player_name]
		)


## Set player color
func set_player_color(color: Color) -> void:
	if visual_mesh and visual_mesh.material_override:
		visual_mesh.material_override.albedo_color = color
	if name_label:
		name_label.modulate = color


## Check for name updates (called periodically)
func _check_name_update() -> void:
	if not PlayerManager or player_id == -1:
		return
	
	var current_name = PlayerManager.get_player_name(player_id)
	if current_name != player_name:
		# Name changed, update it
		update_player_name(current_name)


## Callback when player data is updated (via NetworkEventBus)
func _on_player_data_updated(updated_peer_id: int, player_data: PlayerData) -> void:
	# Check if this is about our player
	if not PlayerManager or player_id == -1:
		return
	
	var our_peer_id = PlayerManager.get_player_peer_id(player_id)
	if our_peer_id == -1 and NetworkManager and NetworkManager.is_multiplayer():
		# Try to get from local player
		if PlayerManager.has_local_player() and PlayerManager.get_local_player_id() == player_id:
			our_peer_id = NetworkManager.get_local_peer_id()
	
	if our_peer_id == updated_peer_id and player_data.player_name != "":
		update_player_name(player_data.player_name)
