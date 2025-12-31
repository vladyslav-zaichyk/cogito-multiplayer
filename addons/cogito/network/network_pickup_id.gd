extends Node
## Network Pickup ID Component
## Adds a unique network ID to pickup items for proper synchronization
## Attach this to CogitoObject with PickupComponent

## Unique network ID for this pickup item (set by host/server)
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
		
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkPickupID",
			"Generated network_id %d for pickup item" % network_id
		)


## Sync network_id to all clients via RPC
func _sync_network_id_to_clients() -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# Get parent object's path in scene
	var parent_obj = get_parent()
	if not parent_obj or not is_inside_tree():
		return
	
	# Try to get scene path, but it might not work for dynamically spawned items
	var scene_path = NodePath()
	if parent_obj.is_inside_tree():
		scene_path = parent_obj.get_path()
	
	var pickup_position = Vector3.ZERO
	if parent_obj.has_method("get") and parent_obj.get("global_position"):
		pickup_position = parent_obj.global_position
	elif parent_obj is Node3D:
		pickup_position = (parent_obj as Node3D).global_position
	
	# Get item name from PickupComponent for better identification
	var item_name = ""
	for child in parent_obj.get_children():
		if child is PickupComponent:
			var pickup = child as PickupComponent
			if pickup.slot_data and pickup.slot_data.inventory_item:
				item_name = pickup.slot_data.inventory_item.get("name") if pickup.slot_data.inventory_item.get("name") else ""
			break
	
	# Send network_id to all clients
	NetworkManager.sync_pickup_network_id.rpc(str(scene_path), network_id, pickup_position, item_name)


## Set network_id (called by RPC from host)
func set_network_id(id: int) -> void:
	network_id = id
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkPickupID",
		"Received network_id %d from host" % network_id
	)


## Get network_id
func get_network_id() -> int:
	return network_id

