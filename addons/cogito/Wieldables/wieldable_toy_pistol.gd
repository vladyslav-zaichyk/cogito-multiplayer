extends CogitoWieldable

@export_group("Pistol Settings")
## Path to the projectile prefab scene
@export var projectile_prefab: PackedScene
## Speed the projectile spawns with
@export var projectile_velocity: float
## Node the projectile spawns at
@onready var bullet_point = %Bullet_Point

## The Field Of View change when aiming down sight. In degrees.
@export var ads_fov = 65
@export var default_position: Vector3

@export_group("Audio")
@export var sound_primary_use: AudioStream
@export var sound_secondary_use: AudioStream
@export var sound_reload: AudioStream

const POOL_SIZE := 50
var projectile_pool := []
var _last_index := -1

var inventory_item_reference: WieldableItemPD


func _ready() -> void:
	# Here, we pre-instantiate `POOL_SIZE` bullets and store them in the `bullets` array.
	for i in POOL_SIZE:
		projectile_pool.append(projectile_prefab.instantiate())


func get_projectile() -> Node3D:
	# Cycle the index between `0` (included) and `POOL_SIZE` (excluded).
	_last_index = wrapi(_last_index + 1, 0, POOL_SIZE)
	return projectile_pool[_last_index]


# This gets called by player interaction compoment when the wieldable is equipped and primary action is pressed
func action_primary(_passed_item_reference: InventoryItemPD, _is_released: bool):
	inventory_item_reference = _passed_item_reference

	if _is_released:
		return

	# Not firing if animation player is playing. This enforces fire rate.
	if animation_player.is_playing():
		return

	if inventory_item_reference.charge_current <= 0:  # Can't fire if empty + send hint.
		inventory_item_reference.send_empty_hint()
		return

	# Sound and animation
	animation_player.play(anim_action_primary)
	audio_stream_player_3d.stream = sound_primary_use
	audio_stream_player_3d.play()

	_passed_item_reference.subtract(1)  #Reducing ammo count

	# Gettting camera_collision pos from player interaction component:
	var _camera_collision = player_interaction_component.Get_Camera_Collision()
	var Direction = (_camera_collision - bullet_point.get_global_transform().origin).normalized()

	# Spawning projectile locally
	var Projectile = get_projectile()
	bullet_point.add_child(Projectile)
	var projectile_position = Vector3(
		bullet_point.global_position.x,
		bullet_point.global_position.y,
		bullet_point.global_position.z
	)
	Projectile.set_global_position(projectile_position)
	Projectile.global_transform.basis = bullet_point.global_transform.basis
	Projectile.damage_amount = _passed_item_reference.wieldable_damage
	var projectile_velocity_vector = Direction * projectile_velocity
	Projectile.set_linear_velocity(projectile_velocity_vector)
	Projectile.Direction = Direction
	# Set shooter_peer_id for multiplayer damage sync (only for local player's projectiles)
	if NetworkManager and NetworkManager.is_multiplayer():
		var player = player_interaction_component.get_parent() if player_interaction_component else null
		if player and PlayerManager:
			var player_id = PlayerManager.get_player_id(player)
			var is_local = PlayerManager.has_local_player() and PlayerManager.get_local_player_id() == player_id
			if is_local:
				Projectile.shooter_peer_id = NetworkManager.get_local_peer_id()
	Projectile.reparent(get_tree().get_current_scene())
	
	# Sync projectile spawn to other clients in multiplayer
	if NetworkManager and NetworkManager.is_multiplayer():
		# Only sync if this is the local player's wieldable
		# Check if player_interaction_component belongs to local player
		var player = player_interaction_component.get_parent() if player_interaction_component else null
		if player and PlayerManager:
			var player_id = PlayerManager.get_player_id(player)
			var is_local = PlayerManager.has_local_player() and PlayerManager.get_local_player_id() == player_id
			
			if is_local:
				# Get projectile scene path
				var projectile_scene_path = ""
				if projectile_prefab and projectile_prefab.resource_path:
					projectile_scene_path = projectile_prefab.resource_path
				else:
					# Fallback: try to get from Projectile's scene_file_path
					if Projectile.scene_file_path:
						projectile_scene_path = Projectile.scene_file_path
				
				if not projectile_scene_path.is_empty():
					var projectile_data = {
						"scene_path": projectile_scene_path,
						"position": projectile_position,
						"rotation": Projectile.rotation,
						"linear_velocity": projectile_velocity_vector,
						"damage_amount": _passed_item_reference.wieldable_damage,
						"shooter_peer_id": NetworkManager.get_local_peer_id()
					}
					
					NetworkManager.sync_projectile_spawn.rpc(projectile_data)


func action_secondary(is_released: bool):
	var camera = get_viewport().get_camera_3d()
	if is_released:
		# ADS Camera Zoom OUT
		var tween_cam = get_tree().create_tween()
		tween_cam.tween_property(camera, "fov", 75, .2)
		var tween_pistol = get_tree().create_tween()
		tween_pistol.tween_property(self, "position", default_position, .2)

		# Re-activating crosshair
		player_interaction_component.update_crosshair.emit(true)
	else:
		# ADS Camera Zoom IN
		var tween_cam = get_tree().create_tween()
		tween_cam.tween_property(camera, "fov", ads_fov, .2)
		var tween_pistol = get_tree().create_tween()
		tween_pistol.tween_property(
			self, "position", Vector3(0, default_position.y, default_position.z), .2
		)

		# Deactivating crosshair
		player_interaction_component.update_crosshair.emit(false)


# Function called when wieldable reload is attempted
func reload():
	animation_player.play(anim_reload)
	audio_stream_player_3d.stream = sound_reload
	audio_stream_player_3d.play()
