extends Node
## Manager for handling multiple inventories in the system.
## Supports both player inventories and external inventories (containers, NPCs, etc.)
## Note: This is an autoload singleton, not a class_name

## Dictionary of registered inventories: owner_id -> inventory
var _inventories: Dictionary = {}

## Enable/disable logging
var enable_logging: bool = false


func _ready() -> void:
	CogitoGlobals.debug_log(
		true, "InventoryManager", "Inventory Manager initialized and ready."
	)


## Register an inventory in the system
## owner_id can be player_id or any unique identifier for the owner
func register_inventory(owner_id: int, inventory: Resource) -> void:
	if not inventory:
		push_error("InventoryManager: Cannot register null inventory")
		return
	
	_inventories[owner_id] = inventory
	
	CogitoGlobals.debug_log(
		enable_logging,
		"InventoryManager",
		"Inventory registered for owner ID: %d" % owner_id
	)
	
	# Emit event through Event Bus
	if NetworkEventBus:
		NetworkEventBus.inventory_changed.emit(owner_id, inventory)


## Unregister an inventory from the system
func unregister_inventory(owner_id: int) -> void:
	if not _inventories.has(owner_id):
		CogitoGlobals.debug_log(
			true,
			"InventoryManager",
			"Attempted to unregister non-existent inventory for owner ID: %d" % owner_id
		)
		return
	
	_inventories.erase(owner_id)
	
	CogitoGlobals.debug_log(
		enable_logging,
		"InventoryManager",
		"Inventory unregistered for owner ID: %d" % owner_id
	)


## Get an inventory by owner ID
func get_inventory(owner_id: int) -> Resource:
	return _inventories.get(owner_id)


## Get player inventory by player ID
func get_player_inventory(player_id: int) -> Resource:
	return get_inventory(player_id)


## Get local player inventory
func get_local_player_inventory() -> Resource:
	if PlayerManager and PlayerManager.has_local_player():
		var player_id = PlayerManager.get_local_player_id()
		return get_inventory(player_id)
	return null


## Check if an inventory is registered
func has_inventory(owner_id: int) -> bool:
	return _inventories.has(owner_id)


## Get all registered owner IDs
func get_all_owner_ids() -> Array:
	return _inventories.keys()


## Get all registered inventories
func get_all_inventories() -> Array:
	return _inventories.values()


## Get inventory count
func get_inventory_count() -> int:
	return _inventories.size()


## Clear all registered inventories (useful for scene transitions)
func clear_all_inventories() -> void:
	var owner_ids = _inventories.keys().duplicate()
	for owner_id in owner_ids:
		unregister_inventory(owner_id)
	
	_inventories.clear()
	
	CogitoGlobals.debug_log(
		enable_logging,
		"InventoryManager",
		"All inventories cleared"
	)


## Helper function for backward compatibility
## Returns the local player inventory, or falls back to finding inventory from owner
func get_current_player_inventory() -> Resource:
	# Try to get from local player ID
	var local_inv = get_local_player_inventory()
	if local_inv:
		return local_inv
	
	# Fallback: try to find inventory from player node
	if PlayerManager and PlayerManager.has_local_player():
		var player = PlayerManager.get_local_player()
		if player and player.has_method("get") and player.get("inventory_data"):
			return player.inventory_data
	
	# Final fallback: try CogitoSceneManager
	if CogitoSceneManager and CogitoSceneManager.has_method("get") and CogitoSceneManager.get("_current_player_node"):
		var player = CogitoSceneManager._current_player_node
		if player and player.has_method("get") and player.get("inventory_data"):
			return player.inventory_data
	
	return null

