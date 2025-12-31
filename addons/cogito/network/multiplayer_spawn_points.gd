extends Node
## Utility for creating spawn points in multiplayer scenes
## Adds spawn points dynamically after scene loads (doesn't edit original scenes)

## Enable/disable logging
var enable_logging: bool = false

## Spawn point offset from ground (Y axis)
const SPAWN_HEIGHT_OFFSET: float = 0.8

## Minimum distance between spawn points
const MIN_SPAWN_DISTANCE: float = 2.0


## Create spawn points from existing connectors
## This is called after scene loads to ensure players can spawn
func create_spawn_points_from_connectors(scene_root: Node) -> Array[Node3D]:
	var spawn_points: Array[Node3D] = []
	
	if not scene_root:
		return spawn_points
	
	# Check if scene has CogitoScene script with connectors
	if scene_root.has_method("get") and scene_root.get("connectors"):
		var connectors = scene_root.connectors
		
		if connectors.size() > 0:
			CogitoGlobals.debug_log(
				enable_logging,
				"MultiplayerSpawnPoints",
				"Found %d connectors, creating spawn points" % connectors.size()
			)
			
			# Create spawn points from connectors
			for i in range(connectors.size()):
				var connector = connectors[i]
				if connector is Node3D:
					var spawn_point = _create_spawn_point(connector, i, scene_root)
					if spawn_point:
						spawn_points.append(spawn_point)
	
	# If no connectors found, create default spawn points
	if spawn_points.size() == 0:
		CogitoGlobals.debug_log(
			enable_logging,
			"MultiplayerSpawnPoints",
			"No connectors found, creating default spawn points"
		)
		spawn_points = _create_default_spawn_points(scene_root)
	
	return spawn_points


## Create a spawn point from a connector
func _create_spawn_point(connector: Node3D, index: int, scene_root: Node) -> Node3D:
	var spawn_point = Marker3D.new()
	spawn_point.name = "SpawnPoint_%d" % index
	
	# Add to SpawnPoint group for PlayerSpawner to find
	spawn_point.add_to_group("SpawnPoint")
	
	# Add to scene root first so we can use global_position
	scene_root.add_child(spawn_point)
	
	# Get connector position - use global_position if in tree, otherwise calculate from transform
	var connector_pos: Vector3
	var connector_rot: Vector3
	
	if connector.is_inside_tree():
		connector_pos = connector.global_position
		connector_rot = connector.global_rotation
	else:
		# If connector is not in tree, calculate global position from its transform chain
		connector_pos = connector.position
		connector_rot = connector.rotation
		
		# Walk up the parent chain to calculate global position
		var current = connector.get_parent()
		while current and current != scene_root:
			if current is Node3D:
				var parent_3d = current as Node3D
				connector_pos = parent_3d.transform * connector_pos
			current = current.get_parent()
	
	# Position at connector location
	spawn_point.global_position = connector_pos
	spawn_point.global_rotation = connector_rot
	
	CogitoGlobals.debug_log(
		enable_logging,
		"MultiplayerSpawnPoints",
		"Created spawn point %d at position: %s" % [index, connector_pos]
	)
	
	return spawn_point


## Create default spawn points if no connectors exist
func _create_default_spawn_points(scene_root: Node) -> Array[Node3D]:
	var spawn_points: Array[Node3D] = []
	
	# Try to find a good spawn location (e.g., near origin, on ground)
	var spawn_positions = [
		Vector3(0, SPAWN_HEIGHT_OFFSET, 0),
		Vector3(2, SPAWN_HEIGHT_OFFSET, 0),
		Vector3(-2, SPAWN_HEIGHT_OFFSET, 0),
		Vector3(0, SPAWN_HEIGHT_OFFSET, 2),
		Vector3(0, SPAWN_HEIGHT_OFFSET, -2),
		Vector3(2, SPAWN_HEIGHT_OFFSET, 2),
		Vector3(-2, SPAWN_HEIGHT_OFFSET, -2),
		Vector3(2, SPAWN_HEIGHT_OFFSET, -2),
	]
	
	for i in range(spawn_positions.size()):
		var spawn_point = Marker3D.new()
		spawn_point.name = "SpawnPoint_Default_%d" % i
		spawn_point.global_position = spawn_positions[i]
		spawn_point.add_to_group("SpawnPoint")
		scene_root.add_child(spawn_point)
		spawn_points.append(spawn_point)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"MultiplayerSpawnPoints",
		"Created %d default spawn points" % spawn_points.size()
	)
	
	return spawn_points
