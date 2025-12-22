extends Node
## Network Rigid Body ID Component
## Adds a unique network ID to rigid bodies for proper synchronization
## Attach this to RigidBody3D nodes (automatically added by NetworkRigidSyncManager)

## Unique network ID for this rigid body (set by host/server)
var network_id: int = 0

## Enable/disable logging
var enable_logging: bool = false

## Static counter for generating unique IDs (host only)
static var _next_network_id: int = 1


func _ready() -> void:
	# Wait a frame to ensure parent is in tree
	await get_tree().process_frame
	
	# Only host generates network IDs
	if NetworkManager and NetworkManager.is_multiplayer() and NetworkManager.is_host():
		network_id = _next_network_id
		_next_network_id += 1
		
		# Sync network_id to all clients
		if is_inside_tree():
			var parent_obj = get_parent()
			if parent_obj:
				# Wait a bit more to ensure scene is fully loaded
				await get_tree().process_frame
				_sync_network_id_to_clients()
		
		var parent_obj = get_parent()
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkRigidBodyID",
			"Generated network_id %d for rigid body: %s" % [network_id, parent_obj.name if parent_obj else "unknown"]
		)


## Sync network_id to all clients via RPC
func _sync_network_id_to_clients() -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# Get parent object's path in scene
	var parent_obj = get_parent()
	if not parent_obj or not is_inside_tree():
		return
	
	# Get scene path
	var scene = get_tree().current_scene
	if not scene:
		return
	
	var scene_path = scene.scene_file_path
	if scene_path.is_empty():
		scene_path = scene.name
	
	# Get node path relative to scene root
	var node_path = parent_obj.get_path()
	var scene_path_str = str(node_path)
	
	# Get position for finding dynamically spawned items
	var position = Vector3.ZERO
	if parent_obj is Node3D:
		position = parent_obj.global_position
	
	# Send RPC to all clients
	NetworkManager.sync_rigid_body_network_id.rpc(scene_path_str, network_id, position)


## Set network_id (called from RPC on clients)
func set_network_id(new_id: int) -> void:
	network_id = new_id
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkRigidBodyID",
		"Set network_id %d for rigid body: %s" % [network_id, get_parent().name if get_parent() else "unknown"]
	)


## Get network_id
func get_network_id() -> int:
	return network_id
