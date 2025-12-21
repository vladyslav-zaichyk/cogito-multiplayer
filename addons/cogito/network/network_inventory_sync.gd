extends Node
## Network Inventory Sync Component
## Synchronizes player inventory in multiplayer
## Attach this to a CogitoPlayer

## Enable/disable logging
var enable_logging: bool = true  # Enable by default for debugging

## Reference to the parent CogitoPlayer
var parent_body: CogitoPlayer = null

## Is this the local player?
var is_local: bool = false

## Peer ID of this player
var peer_id: int = 0

## Reference to player inventory
var player_inventory: CogitoInventory = null


func _ready() -> void:
	parent_body = get_parent() as CogitoPlayer
	if not parent_body:
		push_error("NetworkInventorySync: Parent must be a CogitoPlayer")
		return
	
	# Wait a frame for player to be initialized
	await get_tree().process_frame
	
	# Determine if this is local player
	if NetworkManager and NetworkManager.is_multiplayer():
		# Get peer_id from PlayerManager
		if PlayerManager:
			var player_id = PlayerManager.get_player_id(parent_body)
			if player_id != -1:
				peer_id = PlayerManager.get_player_peer_id(player_id)
				var local_peer_id = NetworkManager.get_local_peer_id()
				is_local = (peer_id == local_peer_id)
			else:
				# Player not registered yet, wait a bit
				await get_tree().process_frame
				player_id = PlayerManager.get_player_id(parent_body)
				if player_id != -1:
					peer_id = PlayerManager.get_player_peer_id(player_id)
					var local_peer_id = NetworkManager.get_local_peer_id()
					is_local = (peer_id == local_peer_id)
	else:
		is_local = false
		peer_id = 0
	
	# Get player inventory
	if parent_body.has_method("get") and parent_body.get("inventory_data"):
		player_inventory = parent_body.inventory_data
		if player_inventory:
			# Connect to inventory signals
			_setup_inventory_tracking()
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInventorySync",
		"Initialized for %s player (peer_id: %d)" % ["local" if is_local else "remote", peer_id]
	)


## Setup tracking for inventory changes
func _setup_inventory_tracking() -> void:
	if not player_inventory:
		return
	
	# Only track local player's inventory
	if not is_local:
		return
	
	# Connect to inventory signals
	if not player_inventory.picked_up_new_inventory_item.is_connected(_on_item_picked):
		player_inventory.picked_up_new_inventory_item.connect(_on_item_picked)
	
	if not player_inventory.inventory_updated.is_connected(_on_inventory_updated):
		player_inventory.inventory_updated.connect(_on_inventory_updated)
	
	# Also connect to NetworkEventBus for merged items (when quantity increases)
	if NetworkEventBus and not NetworkEventBus.inventory_item_picked.is_connected(_on_event_bus_item_picked):
		NetworkEventBus.inventory_item_picked.connect(_on_event_bus_item_picked)
	
	# Connect to NetworkEventBus for dropped items
	if NetworkEventBus and not NetworkEventBus.inventory_item_dropped.is_connected(_on_item_dropped):
		NetworkEventBus.inventory_item_dropped.connect(_on_item_dropped)

	# Connect to NetworkEventBus for item usage (consumables, wieldables, etc.)
	if NetworkEventBus and not NetworkEventBus.inventory_item_used.is_connected(_on_event_bus_item_used):
		NetworkEventBus.inventory_item_used.connect(_on_event_bus_item_used)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInventorySync",
		"Connected to inventory signals"
	)


## Called when NetworkEventBus emits inventory_item_picked (for merged items too)
func _on_event_bus_item_picked(player_id: int, item: InventoryItemPD, slot_data: InventorySlotPD) -> void:
	# Only process if this is about the local player
	if not is_local:
		return
	
	# Check if this is about us
	var local_player_id = PlayerManager.get_local_player_id() if PlayerManager else -1
	if player_id != local_player_id:
		return
	
	# Call the same handler as _on_item_picked
	_on_item_picked(slot_data)


## Called when NetworkEventBus emits inventory_item_used (локальний гравець використав предмет)
func _on_event_bus_item_used(player_id: int, item: InventoryItemPD) -> void:
	# Only process if this is about the local player
	if not is_local:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# Check if this is about us
	var local_player_id = PlayerManager.get_local_player_id() if PlayerManager else -1
	if player_id != local_player_id:
		return
	
	# Serialize item and send RPC so інші клієнти знали, що предмет використано
	var item_data = _serialize_item(item)
	
	CogitoGlobals.debug_log(
		true,
		"NetworkInventorySync",
		"[LOCAL USE] Player %d used item: %s (resource_path=%s)" % [
			player_id,
			item_data.get("name", "unknown"),
			item_data.get("resource_path", "unknown")
		]
	)
	
	if NetworkManager.is_multiplayer() and peer_id > 0:
		NetworkManager.sync_inventory_item_used.rpc(peer_id, item_data)


## Called by RPC when a remote player uses an item
func _receive_item_used(using_peer_id: int, item_data: Dictionary) -> void:
	# For now ми не дублюємо геймплей-ефект (атрибути вже синхронізуються окремо),
	# але можемо використовувати цей хук для візуалів/логів
	var item_name = item_data.get("name", "unknown")
	CogitoGlobals.debug_log(
		true,
		"NetworkInventorySync",
		"[REMOTE USE RECEIVED] Peer %d used item: %s" % [using_peer_id, item_name]
	)


## Called by RPC when a remote player removes/consumes a pickup item from world
func _receive_pickup_removed(removing_peer_id: int, item_data: Dictionary) -> void:
	# Only process if this is about a remote player
	if is_local and removing_peer_id == peer_id:
		# This is about ourselves, but we already handled it locally
		return
	
	CogitoGlobals.debug_log(
		true,
		"NetworkInventorySync",
		"[REMOTE PICKUP REMOVED] Peer %d removed/consumed item from world: %s" % [
			removing_peer_id,
			item_data.get("name", "unknown")
		]
	)
	
	# Remove the item from world using the same method as pickup
	_remove_pickup_from_world(item_data)


## Called when local player picks up an item
func _on_item_picked(slot_data: InventorySlotPD) -> void:
	CogitoGlobals.debug_log(
		true,
		"NetworkInventorySync",
		"[_on_item_picked] Called with slot_data: %s, is_local: %s" % [slot_data.inventory_item.name if slot_data and slot_data.inventory_item else "null", is_local]
	)
	
	if not is_local:
		CogitoGlobals.debug_log(
			true,
			"NetworkInventorySync",
			"[_on_item_picked] Not local player, returning"
		)
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		CogitoGlobals.debug_log(
			true,
			"NetworkInventorySync",
			"[_on_item_picked] Not multiplayer, returning"
		)
		return
	
	if not slot_data or not slot_data.inventory_item:
		CogitoGlobals.debug_log(
			true,
			"NetworkInventorySync",
			"[_on_item_picked] Invalid slot_data or inventory_item, returning"
		)
		return
	
	# Sync item pickup to all clients
	# Note: We'll need to serialize the item data for RPC
	var item_data = _serialize_item(slot_data.inventory_item)
	var slot_index = slot_data.origin_index
	# Also include quantity from slot_data
	item_data["quantity"] = slot_data.quantity
	
	# If this is a WieldableItemPD, ensure charge_current is included
	# (it should already be in _serialize_item, but double-check)
	if slot_data.inventory_item is WieldableItemPD:
		var wieldable_item = slot_data.inventory_item as WieldableItemPD
		item_data["charge_current"] = wieldable_item.charge_current
		item_data["charge_max"] = wieldable_item.charge_max
		CogitoGlobals.debug_log(
			true,
			"NetworkInventorySync",
			"[_on_item_picked] Serialized charge_current: %s / %s for %s" % [
				wieldable_item.charge_current,
				wieldable_item.charge_max,
				slot_data.inventory_item.name
			]
		)
	
	# Find the picked up item in the world to get its position, network_id, and scene path
	# Note: instance_id is not used anymore (not reliable in multiplayer, local to each client)
	var pickup_position = Vector3.ZERO
	var pickup_network_id = 0
	var pickup_scene_path = ""
	
	# Try to find the item that was just picked up
	# The item should be in the interaction component's interactable
	if parent_body and parent_body.has_method("get") and parent_body.get("player_interaction_component"):
		var interaction_component = parent_body.player_interaction_component
		if interaction_component and interaction_component.interactable:
			var interactable = interaction_component.interactable
			# Check if this interactable has a PickupComponent
			for child in interactable.get_children():
				if child is PickupComponent:
					var pickup = child as PickupComponent
					if pickup.slot_data and pickup.slot_data.inventory_item == slot_data.inventory_item:
						# Found the item that was picked up
						pickup_position = interactable.global_position
						
						# Get scene path (most reliable for static items)
						if interactable.is_inside_tree():
							pickup_scene_path = str(interactable.get_path())
						
						# Try to get network_id from NetworkPickupID component
						# Note: Check specifically for NetworkPickupID to avoid NetworkRigidSync (which returns String)
						for child2 in interactable.get_children():
							if child2.has_method("get_network_id"):
								var script_path = child2.get_script().resource_path if child2.get_script() else ""
								# NetworkPickupID returns int, NetworkRigidSync returns String
								if script_path.ends_with("network_pickup_id.gd"):
									pickup_network_id = child2.get_network_id()
									break
						
						# If network_id is 0, try to find NetworkPickupID by name
						if pickup_network_id == 0:
							var network_id_node = interactable.get_node_or_null("NetworkPickupID")
							if network_id_node and network_id_node.has_method("get_network_id"):
								var script_path = network_id_node.get_script().resource_path if network_id_node.get_script() else ""
								if script_path.ends_with("network_pickup_id.gd"):
									pickup_network_id = network_id_node.get_network_id()
						
						break
	
	# Add position, network_id, and scene path to item_data for precise identification
	# Note: instance_id removed (not reliable in multiplayer)
	item_data["pickup_position"] = pickup_position
	item_data["pickup_network_id"] = pickup_network_id
	item_data["pickup_scene_path"] = pickup_scene_path
	
	CogitoGlobals.debug_log(
		true,  # Always log for debugging
		"NetworkInventorySync",
		"[LOCAL PICKUP] Item: %s | Position: %s | Network ID: %d | Scene Path: %s" % [
			slot_data.inventory_item.name,
			pickup_position,
			pickup_network_id,
			pickup_scene_path
		]
	)
	
	# Only sync if we're in multiplayer and have a valid peer_id
	if NetworkManager.is_multiplayer() and peer_id > 0:
		NetworkManager.sync_inventory_item_picked.rpc(peer_id, item_data, slot_index)


## Called when local player drops an item
func _on_item_dropped(player_id: int, item: InventoryItemPD, position: Vector3) -> void:
	# Only process if this is about the local player
	if not is_local or player_id != PlayerManager.get_player_id(parent_body) if PlayerManager else -1:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	if not item:
		return
	
	# Try to find slot_data in inventory to get charge_current and resource_path
	# This is important for WieldableItemPD to preserve ammo state
	var found_slot_data: InventorySlotPD = null
	var original_resource_path = item.resource_path
	
	if player_inventory:
		for slot_data in player_inventory.inventory_slots:
			if slot_data and slot_data.inventory_item == item:
				found_slot_data = slot_data
				# Found the slot, try to get resource_path from the slot's item
				if slot_data.inventory_item.resource_path != "":
					original_resource_path = slot_data.inventory_item.resource_path
					CogitoGlobals.debug_log(
						true,
						"NetworkInventorySync",
						"[_on_item_dropped] Found resource_path from inventory slot: %s" % original_resource_path
					)
				break
	
	# Sync item drop to all clients
	var item_data = _serialize_item(item)
	
	# Override resource_path if we found a better one
	if original_resource_path != "" and original_resource_path != "unknown" and item_data.get("resource_path") == "unknown":
		item_data["resource_path"] = original_resource_path
		CogitoGlobals.debug_log(
			true,
			"NetworkInventorySync",
			"[_on_item_dropped] Overriding resource_path with found path: %s" % original_resource_path
		)
	
	# If this is a WieldableItemPD, get charge_current from found_slot_data or item directly
	if item is WieldableItemPD:
		var wieldable_item = item as WieldableItemPD
		# Prefer charge_current from slot_data (more reliable)
		if found_slot_data and found_slot_data.inventory_item is WieldableItemPD:
			var slot_wieldable = found_slot_data.inventory_item as WieldableItemPD
			item_data["charge_current"] = slot_wieldable.charge_current
			item_data["charge_max"] = slot_wieldable.charge_max
			CogitoGlobals.debug_log(
				true,
				"NetworkInventorySync",
				"[_on_item_dropped] Serialized charge_current from slot_data: %s / %s" % [
					slot_wieldable.charge_current,
					slot_wieldable.charge_max
				]
			)
		# Fallback to item directly (if slot_data not found)
		elif wieldable_item.charge_current >= 0:
			item_data["charge_current"] = wieldable_item.charge_current
			item_data["charge_max"] = wieldable_item.charge_max
			CogitoGlobals.debug_log(
				true,
				"NetworkInventorySync",
				"[_on_item_dropped] Serialized charge_current from item: %s / %s" % [
					wieldable_item.charge_current,
					wieldable_item.charge_max
				]
			)
	
	CogitoGlobals.debug_log(
		true,  # Always log for debugging
		"NetworkInventorySync",
		"[LOCAL DROP] Item: %s | Resource Path: %s | Position: %s" % [
			item_data.get("name", "unknown"),
			item_data.get("resource_path", "unknown"),
			position
		]
	)
	
	# Only sync if we're in multiplayer and have a valid peer_id
	if NetworkManager.is_multiplayer() and peer_id > 0:
		NetworkManager.sync_inventory_item_dropped.rpc(peer_id, item_data, position)


## Called when local player's inventory changes (items moved, used, etc.)
func _on_inventory_updated(inventory: CogitoInventory) -> void:
	if not is_local:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# For now, we'll sync individual item changes
	# Full inventory sync can be added later if needed
	# This is called for moves, merges, etc.
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkInventorySync",
		"Inventory updated (items may have been moved or merged)"
	)


## Serialize item data for RPC (simplified - just item resource path)
func _serialize_item(item: InventoryItemPD) -> Dictionary:
	if not item:
		CogitoGlobals.debug_log(
			true,
			"NetworkInventorySync",
			"[_serialize_item] Item is null!"
		)
		return {}
	
	# Get resource path if it's a resource
	var item_path = ""
	if item.resource_path != "" and item.resource_path != "unknown":
		item_path = item.resource_path
	else:
		# Try to get resource path from script if available
		# When item is used, resource_path might be lost, but script should still have it
		if item.get_script():
			var script_path = item.get_script().resource_path
			if script_path != "":
				# Try to find the original resource by script path
				# This is a fallback - ideally resource_path should always be set
				item_path = script_path
			else:
				# Last resort: try to find by name in known resources
				# This is not ideal but better than "unknown"
				var item_name = item.get("name") if item.get("name") != null else ""
				CogitoGlobals.debug_log(
					true,
					"NetworkInventorySync",
					"[_serialize_item] WARNING: Item '%s' has no resource_path! Script path: %s" % [item_name, script_path if item.get_script() else "none"]
				)
				item_path = "unknown"
		else:
			var item_name = item.get("name") if item.get("name") != null else ""
			CogitoGlobals.debug_log(
				true,
				"NetworkInventorySync",
				"[_serialize_item] WARNING: Item '%s' has no resource_path and no script!" % item_name
			)
			item_path = "unknown"
	
	# Get item name and quantity safely
	var item_name = ""
	var item_quantity = 1
	
	# Try to get name property (most items have this)
	# InventoryItemPD has name as @export var, so we can access it directly
	if item.get("name") != null:
		item_name = item.get("name")
	
	# Note: quantity is in InventorySlotPD, not InventoryItemPD
	# So we don't need to serialize quantity here (it's handled separately)
	
	CogitoGlobals.debug_log(
		true,
		"NetworkInventorySync",
		"[_serialize_item] Serialized item: name='%s', resource_path='%s'" % [item_name, item_path]
	)
	
	var item_dict = {
		"resource_path": item_path,
		"name": item_name,
		"quantity": item_quantity
	}
	
	# If this is a WieldableItemPD, serialize ammo state (charge_current and charge_max)
	if item is WieldableItemPD:
		var wieldable_item = item as WieldableItemPD
		item_dict["charge_current"] = wieldable_item.charge_current
		item_dict["charge_max"] = wieldable_item.charge_max
	
	return item_dict


## Called by RPC when a player picks up an item
func _receive_item_picked(picking_peer_id: int, item_data: Dictionary, slot_index: int) -> void:
	# Only process if this is about a remote player
	if is_local and picking_peer_id == peer_id:
		# This is about ourselves, but we already handled it locally
		return
	
	var item_name = item_data.get("name", "unknown")
	var pickup_position = item_data.get("pickup_position", Vector3.ZERO)
	var pickup_network_id = item_data.get("pickup_network_id", 0)
	var pickup_scene_path = item_data.get("pickup_scene_path", "")
	# Note: instance_id removed (not reliable in multiplayer)
	
	CogitoGlobals.debug_log(
		true,  # Always log for debugging
		"NetworkInventorySync",
		"[REMOTE PICKUP RECEIVED] Peer %d picked up: %s | Position: %s | Network ID: %d | Scene Path: %s" % [
			picking_peer_id,
			item_name,
			pickup_position,
			pickup_network_id,
			pickup_scene_path
		]
	)
	
	# Find and remove the item from the world scene
	# We need to find the CogitoObject with PickupComponent that matches this item
	_remove_pickup_from_world(item_data)


## Called by RPC when a player drops an item
func _receive_item_dropped(dropping_peer_id: int, item_data: Dictionary, position: Vector3) -> void:
	# Only process if this is about a remote player
	if is_local and dropping_peer_id == peer_id:
		# This is about ourselves, but we already handled it locally
		return
	
	var item_name = item_data.get("name", "unknown")
	var item_path = item_data.get("resource_path", "unknown")
	
	CogitoGlobals.debug_log(
		true,  # Always log for debugging
		"NetworkInventorySync",
		"[REMOTE DROP RECEIVED] Peer %d dropped: %s | Resource Path: %s | Position: %s" % [
			dropping_peer_id,
			item_name,
			item_path,
			position
		]
	)
	
	# Spawn the dropped item in the world
	_spawn_pickup_in_world(item_data, position)


## Remove pickup item from world (called when remote player picks it up)
func _remove_pickup_from_world(item_data: Dictionary) -> void:
	var item_name = item_data.get("name", "")
	var item_path = item_data.get("resource_path", "")
	var pickup_position = item_data.get("pickup_position", Vector3.ZERO)
	var pickup_network_id = item_data.get("pickup_network_id", 0)
	var pickup_scene_path = item_data.get("pickup_scene_path", "")
	# Note: instance_id removed (not reliable in multiplayer)
	
	if item_name.is_empty() and item_path.is_empty():
		return
	
	# Get current scene root
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	
	# Priority 1: Try to find by scene path (most reliable for static items)
	if not pickup_scene_path.is_empty():
		CogitoGlobals.debug_log(
			true,
			"NetworkInventorySync",
			"[REMOVE ATTEMPT] Trying to find by scene_path: %s" % pickup_scene_path
		)
		var target_node = scene_root.get_node_or_null(NodePath(pickup_scene_path))
		if target_node and is_instance_valid(target_node):
			CogitoGlobals.debug_log(
				true,
				"NetworkInventorySync",
				"[REMOVE ATTEMPT] Found node by scene_path, verifying..."
			)
			# Verify it has PickupComponent and matches the item
			for child in target_node.get_children():
				if child is PickupComponent:
					var pickup = child as PickupComponent
					if pickup.slot_data and pickup.slot_data.inventory_item:
						var item = pickup.slot_data.inventory_item
						var item_n = item.get("name") if item.get("name") else ""
						# Verify it matches the item we're looking for
						if item_n == item_name or (item_path != "" and item.resource_path == item_path):
							CogitoGlobals.debug_log(
								true,
								"NetworkInventorySync",
								"[REMOVE SUCCESS] Removing pickup item by scene_path: %s (path: %s, item name: %s)" % [item_name, pickup_scene_path, item_n]
							)
							target_node.queue_free()
							return
						else:
							CogitoGlobals.debug_log(
								true,
								"NetworkInventorySync",
								"[REMOVE FAIL] Item name mismatch: expected '%s', found '%s'" % [item_name, item_n]
							)
		else:
			CogitoGlobals.debug_log(
				true,
				"NetworkInventorySync",
				"[REMOVE FAIL] Could not find node by scene_path: %s" % pickup_scene_path
			)
	
	# Priority 2: Try to find by network_id (works across clients for dynamic items)
	if pickup_network_id > 0:
		CogitoGlobals.debug_log(
			true,
			"NetworkInventorySync",
			"[REMOVE ATTEMPT] Trying to find by network_id: %d" % pickup_network_id
		)
		var all_nodes = scene_root.get_children()
		var nodes_to_check = []
		nodes_to_check.append_array(all_nodes)
		var found_count = 0
		
		# Recursively find all nodes
		while nodes_to_check.size() > 0:
			var node = nodes_to_check.pop_front()
			if not is_instance_valid(node):
				continue
			
			# Check if this node has a NetworkPickupID component with matching network_id
			# Note: Check specifically for NetworkPickupID to avoid NetworkRigidSync (which returns String)
			for child in node.get_children():
				if child.has_method("get_network_id"):
					var script_path = child.get_script().resource_path if child.get_script() else ""
					# Only check NetworkPickupID (returns int), not NetworkRigidSync (returns String)
					if script_path.ends_with("network_pickup_id.gd"):
						var child_network_id = child.get_network_id()
						if child_network_id == pickup_network_id:
							found_count += 1
						CogitoGlobals.debug_log(
							true,
							"NetworkInventorySync",
							"[REMOVE ATTEMPT] Found node with matching network_id %d (node: %s)" % [pickup_network_id, node.name]
						)
						# Found matching network_id, verify it has PickupComponent
						for child2 in node.get_children():
							if child2 is PickupComponent:
								var pickup = child2 as PickupComponent
								if pickup.slot_data and pickup.slot_data.inventory_item:
									var item = pickup.slot_data.inventory_item
									var item_n = item.get("name") if item.get("name") else ""
									# Verify it matches the item we're looking for
									if item_n == item_name or (item_path != "" and item.resource_path == item_path):
										CogitoGlobals.debug_log(
											true,
											"NetworkInventorySync",
											"[REMOVE SUCCESS] Removing pickup item by network_id: %s (network_id: %d, item name: %s)" % [item_name, pickup_network_id, item_n]
										)
										node.queue_free()
										return
									else:
										CogitoGlobals.debug_log(
											true,
											"NetworkInventorySync",
											"[REMOVE FAIL] Item name mismatch: expected '%s', found '%s' (network_id: %d)" % [item_name, item_n, pickup_network_id]
										)
						break
			
			# Add children to check
			for child in node.get_children():
				nodes_to_check.append(child)
		
		if found_count == 0:
			CogitoGlobals.debug_log(
				true,
				"NetworkInventorySync",
				"[REMOVE FAIL] No nodes found with network_id: %d" % pickup_network_id
			)
	
	# Priority 3: Try to find by position (if position is provided and valid)
	# Note: instance_id method removed (not reliable in multiplayer, local to each client)
	if pickup_position != Vector3.ZERO:
		CogitoGlobals.debug_log(
			true,
			"NetworkInventorySync",
			"[REMOVE ATTEMPT] Trying to find by position: %s" % pickup_position
		)
		var closest_match = null
		var closest_distance = 0.5  # Max distance to consider a match (0.5 units)
		
		var all_nodes = scene_root.get_children()
		var nodes_to_check = []
		nodes_to_check.append_array(all_nodes)
		
		# Recursively find all nodes
		while nodes_to_check.size() > 0:
			var node = nodes_to_check.pop_front()
			if not is_instance_valid(node):
				continue
			
			# Check if this node has a PickupComponent
			for child in node.get_children():
				if child is PickupComponent:
					var pickup = child as PickupComponent
					if pickup.slot_data and pickup.slot_data.inventory_item:
						var item = pickup.slot_data.inventory_item
						# Match by name or resource path
						if item.get("name") == item_name or (item_path != "" and item.resource_path == item_path):
							# Check distance to pickup position
							var distance = node.global_position.distance_to(pickup_position)
							if distance < closest_distance:
								closest_match = node
								closest_distance = distance
			
			# Add children to check
			for child in node.get_children():
				nodes_to_check.append(child)
		
		if closest_match and is_instance_valid(closest_match):
			CogitoGlobals.debug_log(
				true,
				"NetworkInventorySync",
				"[REMOVE SUCCESS] Removing pickup item by position: %s at distance %f" % [item_name, closest_distance]
			)
			closest_match.queue_free()
			return
		else:
			CogitoGlobals.debug_log(
				true,
				"NetworkInventorySync",
				"[REMOVE FAIL] No matching item found by position (searched within 0.5 units of %s)" % pickup_position
			)
	
	# Priority 4: Fallback to first matching item (less precise, but better than nothing)
	CogitoGlobals.debug_log(
		true,
		"NetworkInventorySync",
		"[REMOVE ATTEMPT] Fallback: searching for any matching item: %s" % item_name
	)
	var all_nodes = scene_root.get_children()
	var nodes_to_check = []
	nodes_to_check.append_array(all_nodes)
	var matches_found = 0
	
	# Recursively find all nodes
	while nodes_to_check.size() > 0:
		var node = nodes_to_check.pop_front()
		if not is_instance_valid(node):
			continue
		
		# Check if this node has a PickupComponent
		for child in node.get_children():
			if child is PickupComponent:
				var pickup = child as PickupComponent
				if pickup.slot_data and pickup.slot_data.inventory_item:
					var item = pickup.slot_data.inventory_item
					var item_n = item.get("name") if item.get("name") else ""
					# Match by name or resource path
					if item_n == item_name or (item_path != "" and item.resource_path == item_path):
						matches_found += 1
						# Found matching item, remove it
						var parent_obj = pickup.get_parent()
						if parent_obj and is_instance_valid(parent_obj):
							var pos_str = ""
							if parent_obj is Node3D:
								pos_str = str((parent_obj as Node3D).global_position)
							CogitoGlobals.debug_log(
								true,
								"NetworkInventorySync",
								"[REMOVE SUCCESS] Removing pickup item (fallback, match #%d): %s at %s" % [matches_found, item_name, pos_str]
							)
							parent_obj.queue_free()
							return
		
		# Add children to check
		for child in node.get_children():
			nodes_to_check.append(child)
	
	CogitoGlobals.debug_log(
		true,
		"NetworkInventorySync",
		"[REMOVE FAIL] Fallback search found %d matching items, but none were removed" % matches_found
	)
	
	# Final log if item was not found at all
	CogitoGlobals.debug_log(
		true,
		"NetworkInventorySync",
		"[REMOVE FAIL] Could not remove item '%s' from world. All search methods failed. Scene path: %s, Network ID: %d, Position: %s" % [
			item_name,
			pickup_scene_path if not pickup_scene_path.is_empty() else "N/A",
			pickup_network_id,
			pickup_position if pickup_position != Vector3.ZERO else "N/A"
		]
	)


## Spawn pickup item in world (called when remote player drops it)
func _spawn_pickup_in_world(item_data: Dictionary, position: Vector3) -> void:
	var item_name = item_data.get("name", "unknown")
	var item_path = item_data.get("resource_path", "")
	
	CogitoGlobals.debug_log(
		true,
		"NetworkInventorySync",
		"[SPAWN ATTEMPT] Trying to spawn item: %s | Resource Path: %s | Position: %s" % [item_name, item_path, position]
	)
	
	# Try to load the item resource
	var item_resource: InventoryItemPD = null
	
	# Try resource_path first (skip if it's a .gd script or empty/unknown)
	if not item_path.is_empty() and item_path != "unknown" and not item_path.ends_with(".gd"):
		item_resource = load(item_path) as InventoryItemPD
		if not item_resource:
			CogitoGlobals.debug_log(
				true,
				"NetworkInventorySync",
				"[SPAWN] Failed to load item from resource_path: %s, trying fallback" % item_path
			)
	
	# Fallback: try to find by name if resource_path failed or missing
	if not item_resource and not item_name.is_empty() and item_name != "unknown":
		# Try common resource paths (similar to network_wieldable_sync.gd)
		var possible_paths = [
			"res://addons/cogito/inventory_pd/Items/Cogito_%s.tres" % item_name.replace(" ", ""),
			"res://addons/cogito/inventory_pd/Items/Cogito_%s.tres" % item_name.replace(" ", "_"),
			"res://addons/cogito/inventory_pd/Items/%s.tres" % item_name.replace(" ", ""),
			"res://addons/cogito/inventory_pd/Items/%s.tres" % item_name.replace(" ", "_"),
		]
		
		# Special cases
		if item_name == "Foam Pistol":
			possible_paths.insert(0, "res://addons/cogito/inventory_pd/Items/Cogito_Pistol.tres")
		
		for path in possible_paths:
			if ResourceLoader.exists(path):
				var test_resource = load(path) as InventoryItemPD
				if test_resource and test_resource.name == item_name:
					item_resource = test_resource
					break
	
	if not item_resource:
		CogitoGlobals.debug_log(
			true,
			"NetworkInventorySync",
			"[SPAWN FAIL] Cannot spawn item '%s': failed to load resource (path: '%s')" % [item_name, item_path]
		)
		return
	
	# Note: We don't modify item_resource here because it's a shared resource
	# Instead, we'll restore charge_current on slot_data.inventory_item after it's created
	
	# Check if item has a drop_scene
	if not item_resource.drop_scene or item_resource.drop_scene.is_empty():
		CogitoGlobals.debug_log(
			true,
			"NetworkInventorySync",
			"Cannot spawn item: no drop_scene defined for %s" % item_resource.get("name")
		)
		return
	
	# Load and instantiate the drop scene
	var drop_scene = load(item_resource.drop_scene) as PackedScene
	if not drop_scene:
		CogitoGlobals.debug_log(
			true,
			"NetworkInventorySync",
			"Cannot spawn item: failed to load drop_scene at %s" % item_resource.drop_scene
		)
		return
	
	var dropped_item = drop_scene.instantiate()
	if not dropped_item:
		return
	
	# Get scene root
	var scene_root = CogitoSceneManager._current_scene_root_node if CogitoSceneManager else get_tree().current_scene
	if not scene_root:
		scene_root = get_tree().current_scene
	
	if not scene_root:
		CogitoGlobals.debug_log(
			true,
			"NetworkInventorySync",
			"Cannot spawn item: no scene root found"
		)
		return
	
	# Add to scene and set position
	scene_root.add_child(dropped_item)
	dropped_item.global_position = position
	
	# Find PickupComponent and set slot_data if needed
	for child in dropped_item.get_children():
		if child is PickupComponent:
			var pickup = child as PickupComponent
			if pickup.slot_data and pickup.slot_data.inventory_item:
				# Update quantity if provided
				var quantity = item_data.get("quantity", 1)
				if quantity > 1:
					pickup.slot_data.quantity = quantity
				
				# If this is a WieldableItemPD, restore ammo state (charge_current and charge_max)
				# Duplicate the resource to avoid modifying the shared resource
				if pickup.slot_data.inventory_item is WieldableItemPD and item_data.has("charge_current"):
					var original_item = pickup.slot_data.inventory_item as WieldableItemPD
					var original_charge = original_item.charge_current
					var duplicated_item = original_item.duplicate() as WieldableItemPD
					var restored_charge = item_data.get("charge_current", 0.0)
					var restored_max = item_data.get("charge_max", 0.0)
					duplicated_item.charge_current = restored_charge
					duplicated_item.charge_max = restored_max
					pickup.slot_data.inventory_item = duplicated_item
					
					# Verify that charge_current was set correctly
					var verify_item = pickup.slot_data.inventory_item as WieldableItemPD
					CogitoGlobals.debug_log(
						true,
						"NetworkInventorySync",
						"[_spawn_pickup_in_world] Restored charge_current: %s / %s for %s (original: %s, verified: %s)" % [
							restored_charge,
							restored_max,
							item_name,
							original_charge,
							verify_item.charge_current
						]
					)
			break
	
	# Add NetworkPickupID component if in multiplayer (for proper synchronization)
	if NetworkManager and NetworkManager.is_multiplayer():
		# Check if NetworkPickupID already exists
		var existing_network_id = dropped_item.get_node_or_null("NetworkPickupID")
		if not existing_network_id:
			# Load and add NetworkPickupID component
			var network_pickup_id_scene = preload("res://addons/cogito/network/network_pickup_id.gd")
			var network_pickup_id = Node.new()
			network_pickup_id.set_script(network_pickup_id_scene)
			network_pickup_id.name = "NetworkPickupID"
			dropped_item.add_child(network_pickup_id)
			CogitoGlobals.debug_log(
				true,
				"NetworkInventorySync",
				"Added NetworkPickupID to spawned item: %s" % item_resource.get("name")
			)
	
	CogitoGlobals.debug_log(
		true,  # Always log for debugging
		"NetworkInventorySync",
		"Spawned pickup item in world: %s at %s" % [item_resource.get("name"), position]
	)
