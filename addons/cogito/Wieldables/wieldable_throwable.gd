extends CogitoWieldable

@export_group("Throwable Settings")
## Leave empty if projectile and pickup are the same scene
@export var projectile_override: PackedScene
## Speed the projectile spawns with
@export var projectile_velocity: float
## Node the projectile spawns at
@onready var bullet_point: Node3D = %Bullet_Point

@export_group("Audio")
@export var sound_primary_use: AudioStream
@export var sound_reload: AudioStream

var player_inventory: CogitoInventory
var item_slot: InventorySlotPD


# Function called when wieldable is unequipped.
func equip(_player_interaction_component: PlayerInteractionComponent):
	animation_player.play(anim_equip)
	player_interaction_component = _player_interaction_component
	player_inventory = player_interaction_component.get_parent().inventory_data
	item_slot = get_slot_reference()


# Function to get the AmmoItemPD
func get_slot_reference() -> InventorySlotPD:
	var slot_reference: InventorySlotPD
	if player_inventory != null:
		for slot in player_inventory.inventory_slots:
			if slot != null and slot.inventory_item.name == item_reference.name:
				slot_reference = slot

	return slot_reference


# This gets called by player interaction compoment when the wieldable is equipped and primary action is pressed
func action_primary(_passed_item_reference: InventoryItemPD, _is_released: bool):
	if _is_released:
		return

	# Not firing if animation player is playing. This enforces fire rate.
	if animation_player.is_playing():
		return

	# Sound and animation
	animation_player.play(anim_action_primary)
	audio_stream_player_3d.stream = sound_primary_use
	audio_stream_player_3d.play()

	unequip()

	### Reduce the stack of the dart items:
	if item_slot:
		item_slot.quantity -= 1
		if item_slot.quantity < 1:
			player_inventory.remove_slot_data(item_slot)
			item_reference.put_away()
		else:
			equip(player_interaction_component)

	player_inventory.inventory_updated.emit(player_inventory)

	# Gettting camera_collision pos from player interaction component:
	var _camera_collision = player_interaction_component.Get_Camera_Collision()
	var Direction = (_camera_collision - bullet_point.get_global_transform().origin).normalized()

	# Spawning projectile locally
	var projectile = instantiate_projectile()
	bullet_point.add_child(projectile)
	var projectile_position = bullet_point.global_position
	projectile.damage_amount = _passed_item_reference.wieldable_damage
	var projectile_velocity_vector = Direction * projectile_velocity
	projectile.set_linear_velocity(projectile_velocity_vector)
	projectile.reparent(get_tree().get_current_scene())
	
	# Sync projectile spawn to other clients in multiplayer
	if NetworkManager and NetworkManager.is_multiplayer():
		# Only sync if this is the local player's wieldable
		var player = player_interaction_component.get_parent() if player_interaction_component else null
		if player and PlayerManager:
			var player_id = PlayerManager.get_player_id(player)
			var is_local = PlayerManager.has_local_player() and PlayerManager.get_local_player_id() == player_id
			
			if is_local:
				# Get projectile scene path
				var projectile_scene_path = ""
				if projectile_override and projectile_override.resource_path:
					projectile_scene_path = projectile_override.resource_path
				elif item_reference and item_reference.drop_scene:
					projectile_scene_path = item_reference.drop_scene
				else:
					# Fallback: try to get from projectile's scene_file_path
					if projectile.scene_file_path:
						projectile_scene_path = projectile.scene_file_path
				
				if not projectile_scene_path.is_empty():
					var projectile_data = {
						"scene_path": projectile_scene_path,
						"position": projectile_position,
						"rotation": projectile.rotation,
						"linear_velocity": projectile_velocity_vector,
						"damage_amount": _passed_item_reference.wieldable_damage,
						"shooter_peer_id": NetworkManager.get_local_peer_id()
					}
					
					NetworkManager.sync_projectile_spawn.rpc(projectile_data)


func instantiate_projectile() -> Node3D:
	if projectile_override != null:
		return projectile_override.instantiate()
	return load(item_reference.drop_scene).instantiate()
