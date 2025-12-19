extends Area3D

@export var spawn_area: CollisionShape3D

@export_range(1, 100) var spawn_amount: int = 1

@export var object_to_spawn: PackedScene


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if !spawn_area.shape.is_class("BoxShape3D"):
		print("spawn area is not a BoxShape3D!")
	pass  # Replace with function body.


func spawn_objects():
	var left_to_spawn = spawn_amount
	var spawn_points: Array[Vector3] = []
	
	# Generate all spawn points first (for synchronization in multiplayer)
	while left_to_spawn > 0:
		var spawn_point: Vector3 = Vector3.ZERO
		spawn_point.x = randf_range(
			spawn_area.global_position.x - spawn_area.shape.size.x,
			spawn_area.global_position.x + spawn_area.shape.size.x
		)
		spawn_point.y = randf_range(
			spawn_area.global_position.y - spawn_area.shape.size.y,
			spawn_area.global_position.y + spawn_area.shape.size.y
		)
		spawn_point.z = randf_range(
			spawn_area.global_position.z - spawn_area.shape.size.z,
			spawn_area.global_position.z + spawn_area.shape.size.z
		)
		spawn_points.append(spawn_point)
		left_to_spawn -= 1
	
	# Spawn objects locally and sync to other clients
	for spawn_point in spawn_points:
		var spawned_object = object_to_spawn.instantiate()
		spawned_object.position = spawn_point
		get_tree().current_scene.add_child(spawned_object)
		
		# Sync spawn to other clients in multiplayer
		if NetworkManager and NetworkManager.is_multiplayer() and object_to_spawn:
			var spawn_data = {
				"scene_path": object_to_spawn.resource_path,
				"position": spawn_point,
				"rotation": Vector3.ZERO
			}
			# Call RPC for all other peers (not locally, since we already spawned it)
			NetworkManager.sync_object_spawn.rpc(spawn_data)


func _on_generic_button_pressed() -> void:
	spawn_objects()
