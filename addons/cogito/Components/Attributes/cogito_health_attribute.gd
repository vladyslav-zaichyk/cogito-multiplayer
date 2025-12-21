extends CogitoAttribute
class_name CogitoHealthAttribute

## Emitted when health is reduced.
signal damage_taken
## Emitted when health reaches zeor.
signal death

## Amount of damage received per second if sanity is zero. Usually only used for Players.
@export var no_sanity_damage: float
## Sound that plays when taking damage, also played on death. Useful as Bullet impact sound
@export var sound_on_hit: AudioStream
## Sound that plays when taking damage, not played on death. Useful as Damage NPC reaction sound
@export var sound_on_damage_taken: AudioStream
## Sound that plays on death.
@export var sound_on_death: AudioStream
## Nodepaths to nodes that get destroyed on death.
@export var destroy_on_death: Array[NodePath]
## Array of Scenes that will get spawned on parent position on death.
@export var spawn_on_death: Array[PackedScene] = []

var parent_position: Vector3


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	value_current = value_start
	attribute_reached_zero.connect(on_death)
	attribute_changed.connect(on_health_change)
	attribute_changed.emit(attribute_name, value_current, value_max, true)


func on_health_change(
	_health_name: String, _health_current: float, _health_max: float, has_increased: bool
):
	if !has_increased:
		damage_taken.emit()
		if sound_on_hit:
			Audio.play_sound_3d(sound_on_hit).global_position = get_parent().global_position
		if sound_on_damage_taken and not _health_current <= 0:
			Audio.play_sound_3d(sound_on_damage_taken).global_position = (
				get_parent().global_position
			)


func on_death(_attribute_name: String, _value_current: float, _value_max: float):
	death.emit()
	parent_position = get_parent().global_position

	if sound_on_death:
		Audio.play_sound_3d(sound_on_death).position = parent_position

	for scene in spawn_on_death:
		if scene:
			var spawned_object = scene.instantiate()
			spawned_object.position = parent_position
			get_tree().current_scene.add_child(spawned_object)

	# Sync object destruction to other clients in multiplayer
	# Only sync if we're in multiplayer and this is a local destruction
	var should_sync_destruction = false
	var destroyer_peer_id = 0
	
	if NetworkManager and NetworkManager.is_multiplayer():
		# Check if this is a player's health attribute (player death)
		var parent_node = get_parent()
		if parent_node and PlayerManager:
			var player_id = PlayerManager.get_player_id(parent_node)
			if player_id != -1:
				# This is a player - check if it's the local player
				var is_local = PlayerManager.has_local_player() and PlayerManager.get_local_player_id() == player_id
				if is_local:
					should_sync_destruction = true
					destroyer_peer_id = NetworkManager.get_local_peer_id()
		else:
			# This is not a player (e.g., a target) - sync destruction from host
			# In multiplayer, only host should trigger destruction for non-player objects
			if NetworkManager.is_host():
				should_sync_destruction = true
				destroyer_peer_id = NetworkManager.get_local_peer_id()
	
	# Destroy objects locally
	for nodepath in destroy_on_death:
		var node_to_destroy = get_node(nodepath) if nodepath else null
		if node_to_destroy and is_instance_valid(node_to_destroy):
			# Get object path for network sync
			var object_path = str(node_to_destroy.get_path())
			
			# Sync destruction to other clients if needed
			if should_sync_destruction and NetworkManager:
				var destruction_data = {
					"object_path": object_path,
					"destroyer_peer_id": destroyer_peer_id
				}
				NetworkManager.sync_object_destroyed.rpc(destruction_data)
			
			# Destroy the object
			node_to_destroy.queue_free()
