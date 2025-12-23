extends Node
## Network Wieldable Sync Component
## Synchronizes player wieldables (weapons, tools) in multiplayer
## Attach this to a CogitoPlayer

## Enable/disable logging
var enable_logging: bool = false  # Disabled by default

## Reference to the parent CogitoPlayer
var parent_body: CogitoPlayer = null

## Is this the local player?
var is_local: bool = false

## Peer ID of this player
var peer_id: int = 0

## Reference to player interaction component
var player_interaction_component: PlayerInteractionComponent = null

## Currently equipped wieldable item resource path (for remote players)
var current_wieldable_path: String = ""

## Currently spawned wieldable node (for remote players)
var remote_wieldable_node: Node3D = null

## Last wieldable item (for change detection)
var _last_wieldable_item: WieldableItemPD = null


func _ready() -> void:
	parent_body = get_parent() as CogitoPlayer
	if not parent_body:
		push_error("NetworkWieldableSync: Parent must be a CogitoPlayer")
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
	
	# Get player interaction component
	if parent_body.has_method("get") and parent_body.get("player_interaction_component"):
		player_interaction_component = parent_body.player_interaction_component
		if player_interaction_component:
			_setup_wieldable_tracking()
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkWieldableSync",
		"Initialized for %s player (peer_id: %d)" % ["local" if is_local else "remote", peer_id]
	)


## Setup tracking for wieldable changes
func _setup_wieldable_tracking() -> void:
	if not player_interaction_component:
		return
	
	# Only track local player's wieldables
	if not is_local:
		return
	
	# Connect to updated_wieldable_data signal to track when wieldable changes
	if not player_interaction_component.updated_wieldable_data.is_connected(_on_wieldable_updated):
		player_interaction_component.updated_wieldable_data.connect(_on_wieldable_updated)
	
	# Also track equipped_wieldable_item changes directly
	# We'll check periodically or use a different approach
	# For now, the signal should be enough
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkWieldableSync",
		"Connected to wieldable signals"
	)
	
	# Store last wieldable to detect changes
	_last_wieldable_item = player_interaction_component.equipped_wieldable_item if player_interaction_component else null


## Called when wieldable is updated (equipped/unequipped)
func _on_wieldable_updated(wieldable_item: WieldableItemPD, ammo_count: int, ammo_item: InventoryItemPD) -> void:
	if not is_local:
		return
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return
	
	# Get current wieldable item from player_interaction_component
	# This is the source of truth for what's actually equipped
	var current_wieldable = player_interaction_component.equipped_wieldable_item if player_interaction_component else null
	
	# Special handling for unequip
	# When unequipping, wieldable_item is null (signal emits null), but current_wieldable might still be set temporarily
	# We detect unequip by checking if signal passed null but we had a wieldable before
	var is_unequipping = (wieldable_item == null and _last_wieldable_item != null)
	
	# If unequipping, use null for current_wieldable to ensure proper sync
	if is_unequipping:
		current_wieldable = null
	
	# IMPORTANT: Check if wieldable actually changed by comparing current_wieldable with _last_wieldable_item
	# The signal parameter (wieldable_item) might be from a previous wieldable (e.g., if pistol is still firing
	# projectiles while switching to laser rifle), so we always use current_wieldable from player_interaction_component
	# as the source of truth.
	# But allow unequip to always sync
	if not is_unequipping and current_wieldable == _last_wieldable_item:
		# Same wieldable, just data update (ammo, charge, etc.)
		# Don't sync this - we only sync equip/unequip changes
		return
	
	# Wieldable changed - update last and sync
	_last_wieldable_item = current_wieldable
	
	# Serialize wieldable data
	var wieldable_data = _serialize_wieldable(current_wieldable)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkWieldableSync",
		"[LOCAL] Wieldable changed: %s" % (wieldable_data.get("name", "none") if wieldable_data else "unequipped")
	)
	
	# Sync wieldable change to all clients
	if NetworkManager.is_multiplayer() and peer_id > 0:
		NetworkManager.sync_wieldable_change.rpc(wieldable_data)


## Serialize wieldable data for RPC
func _serialize_wieldable(wieldable_item: WieldableItemPD) -> Dictionary:
	if not wieldable_item:
		return {
			"resource_path": "",
			"name": "",
			"is_equipped": false
		}
	
	# Get resource path - this should be set if the item was loaded from a .tres file
	var resource_path = wieldable_item.resource_path
	
	# If resource_path is empty or points to a script, try to find the .tres file
	if resource_path.is_empty() or resource_path.ends_with(".gd"):
		# Try to find resource by name in known paths
		var item_name = ""
		if wieldable_item.get("name") != null:
			item_name = wieldable_item.get("name")
		
		if not item_name.is_empty():
			# Try common resource paths
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
					var test_resource = load(path) as WieldableItemPD
					if test_resource and test_resource.name == item_name:
						resource_path = path
						CogitoGlobals.debug_log(
							enable_logging,
							"NetworkWieldableSync",
							"Found resource_path for '%s': %s" % [item_name, resource_path]
						)
						break
		
		if resource_path.is_empty() or resource_path.ends_with(".gd"):
			CogitoGlobals.debug_log(
				enable_logging,
				"NetworkWieldableSync",
				"Warning: Wieldable item '%s' has no valid resource_path, using name as fallback" % item_name
			)
	
	var item_name = ""
	if wieldable_item.get("name") != null:
		item_name = wieldable_item.get("name")
	
	return {
		"resource_path": resource_path,
		"name": item_name,
		"is_equipped": true
	}


## Called by RPC when a player changes wieldable
func _receive_wieldable_change(changing_peer_id: int, wieldable_data: Dictionary) -> void:
	# Only process if this is about a remote player
	if is_local and changing_peer_id == peer_id:
		# This is about ourselves, but we already handled it locally
		return
	
	var item_name = wieldable_data.get("name", "unknown")
	var is_equipped = wieldable_data.get("is_equipped", false)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"NetworkWieldableSync",
		"[REMOTE] Peer %d wieldable changed: %s" % [changing_peer_id, item_name]
	)
	
	# Update remote player's wieldable
	_update_remote_wieldable(wieldable_data)


## Update remote player's wieldable visual
func _update_remote_wieldable(wieldable_data: Dictionary) -> void:
	if not player_interaction_component:
		return
	
	var resource_path = wieldable_data.get("resource_path", "")
	var is_equipped = wieldable_data.get("is_equipped", false)
	
	# Remove current wieldable if exists
	if remote_wieldable_node and is_instance_valid(remote_wieldable_node):
		remote_wieldable_node.queue_free()
		remote_wieldable_node = null
	
	current_wieldable_path = ""
	
	# If no wieldable, we're done
	if not is_equipped:
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkWieldableSync",
			"[REMOTE] Player unequipped wieldable"
		)
		return
	
	# Load wieldable resource
	var wieldable_resource: WieldableItemPD = null
	
	if not resource_path.is_empty():
		# Try to load from resource path
		wieldable_resource = load(resource_path) as WieldableItemPD
		if not wieldable_resource:
			CogitoGlobals.debug_log(
				enable_logging,
				"NetworkWieldableSync",
				"[REMOTE] Failed to load wieldable resource: %s" % resource_path
			)
			# Try fallback: search by name in player's inventory
			wieldable_resource = _find_wieldable_by_name(wieldable_data.get("name", ""))
	else:
		# No resource path - try to find by name
		wieldable_resource = _find_wieldable_by_name(wieldable_data.get("name", ""))
	
	if not wieldable_resource:
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkWieldableSync",
			"[REMOTE] Could not find wieldable: %s (path: %s)" % [wieldable_data.get("name", "unknown"), resource_path]
		)
		return
	
	if not wieldable_resource.wieldable_scene:
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkWieldableSync",
			"[REMOTE] Wieldable has no wieldable_scene: %s" % resource_path
		)
		return
	
	# Build and spawn wieldable node
	var wieldable_node = wieldable_resource.build_wieldable_scene()
	if not wieldable_node:
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkWieldableSync",
			"[REMOTE] Failed to build wieldable scene: %s" % resource_path
		)
		return
	
	# Add to wieldable container
	if player_interaction_component.wieldable_container:
		# Check if wieldable already exists in container (prevent duplicates)
		var existing_wieldables = player_interaction_component.wieldable_container.get_children()
		var already_exists = false
		for existing in existing_wieldables:
			if existing == remote_wieldable_node:
				# This is our tracked node, skip it
				continue
			if existing is CogitoWieldable and existing.item_reference == wieldable_resource:
				# Same wieldable already exists
				already_exists = true
				CogitoGlobals.debug_log(
					enable_logging,
					"NetworkWieldableSync",
					"[REMOTE] Wieldable already exists in container, skipping duplicate: %s" % wieldable_data.get("name", "unknown")
				)
				break
		
		if not already_exists:
			player_interaction_component.wieldable_container.add_child(wieldable_node)
			remote_wieldable_node = wieldable_node
			wieldable_node.item_reference = wieldable_resource
			current_wieldable_path = resource_path if not resource_path.is_empty() else wieldable_data.get("name", "")
			
			CogitoGlobals.debug_log(
				enable_logging,
				"NetworkWieldableSync",
				"[REMOTE] Added wieldable to container: %s" % wieldable_data.get("name", "unknown")
			)
		else:
			# Clean up the node we created since it's a duplicate
			wieldable_node.queue_free()
			return
		
		# Wait a frame for _ready() to complete (which hides the mesh)
		await get_tree().process_frame
		
		# Show mesh for remote players so others can see what they're holding
		# The wieldable_mesh is hidden by default in _ready(), so we need to show it
		if wieldable_node is CogitoWieldable:
			# Set up player_interaction_component reference (needed for wieldable to work)
			wieldable_node.player_interaction_component = player_interaction_component
			
			# For remote players, we DON'T call equip() because:
			# 1. The wieldable is already in the correct default state from the scene
			# 2. The Wieldables container is under Head, so it will automatically rotate with head.rotation
			# 3. Calling equip() and seeking to end can cause incorrect orientation
			# We just need to set up the reference and show the mesh
			# TODO: This will be properly fixed with ViewModel/WorldModel architecture (Phase 2.4)
			
			CogitoGlobals.debug_log(
				enable_logging,
				"NetworkWieldableSync",
				"[REMOTE] Setting up wieldable for: %s" % wieldable_data.get("name", "unknown")
			)
			
			if wieldable_node.wieldable_mesh:
				wieldable_node.wieldable_mesh.show()
			else:
				# If no specific wieldable_mesh, try to show all MeshInstance3D children
				_show_all_meshes(wieldable_node)
			
			# For flashlight, also show the mesh immediately (it's hidden in _ready())
			# Default to off for remote players (state will be synced via RPC when toggled)
			if wieldable_node.has_method("toggle_flashlight"):
				# Flashlight - show mesh immediately
				if wieldable_node.wieldable_mesh:
					wieldable_node.wieldable_mesh.show()
				
				# Default to off for remote players
				# The actual state will be synced when the local player toggles it
				wieldable_node.toggle_flashlight(false)
		
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkWieldableSync",
			"[REMOTE] Spawned wieldable: %s" % wieldable_data.get("name", "unknown")
		)
	else:
		CogitoGlobals.debug_log(
			enable_logging,
			"NetworkWieldableSync",
			"[REMOTE] No wieldable_container found"
		)
		wieldable_node.queue_free()


## Show all mesh instances in a node (for wieldables without specific wieldable_mesh)
func _show_all_meshes(node: Node) -> void:
	if not node:
		return
	
	# Show all MeshInstance3D nodes
	for child in node.get_children():
		if child is MeshInstance3D:
			child.visible = true
		# Recursively check children
		_show_all_meshes(child)


## Find wieldable by name in player's inventory (fallback method)
func _find_wieldable_by_name(item_name: String) -> WieldableItemPD:
	if item_name.is_empty():
		return null
	
	if not parent_body or not parent_body.has_method("get") or not parent_body.get("inventory_data"):
		return null
	
	var inventory = parent_body.inventory_data
	if not inventory:
		return null
	
	# Search through inventory slots
	for slot in inventory.inventory_slots:
		if slot and slot.inventory_item and slot.inventory_item is WieldableItemPD:
			if slot.inventory_item.name == item_name:
				return slot.inventory_item as WieldableItemPD
	
	return null
