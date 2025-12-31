extends Node
## Centralized Event Bus for decoupling systems and preparing for multiplayer.
## This system allows components to communicate without direct dependencies.
## Note: This is an autoload singleton, not a class_name

## Enable/disable event logging for debugging
@export var enable_event_logging: bool = false

# Preload classes to ensure they're available when parsing signals
const CogitoInventory = preload("res://addons/cogito/inventory_pd/cogito_inventory.gd")
const InventoryItemPD = preload("res://addons/cogito/inventory_pd/CustomResources/InventoryItemPD.gd")
const InventorySlotPD = preload("res://addons/cogito/inventory_pd/CustomResources/InventorySlotPD.gd")
const CogitoQuest = preload("res://addons/cogito/quest_system/CustomResources/cogito_quest.gd")
const PlayerData = preload("res://addons/cogito/network/player_data.gd")

#region Player Events
## Emitted when a player is registered in the system
signal player_registered(player_id: int, player_node: Node)
## Emitted when a player is unregistered from the system
signal player_unregistered(player_id: int)
## Emitted when a player spawns in the game world
signal player_spawned(player_id: int, position: Vector3)
## Emitted when a player dies
signal player_died(player_id: int)
## Emitted when a player moves (for potential network sync)
signal player_moved(player_id: int, position: Vector3, rotation: Vector3)
## Emitted when a player performs an input action
signal player_input(player_id: int, action: String, pressed: bool)
## Emitted when player data is updated (name, etc.)
signal player_data_updated(peer_id: int, player_data: PlayerData)
#endregion

#region Inventory Events
## Emitted when a player picks up an item
signal inventory_item_picked(player_id: int, item: InventoryItemPD, slot_data: InventorySlotPD)
## Emitted when a player drops an item
signal inventory_item_dropped(player_id: int, item: InventoryItemPD, position: Vector3)
## Emitted when an inventory changes (items moved, used, etc.)
signal inventory_changed(player_id: int, inventory: CogitoInventory)
## Emitted when an item is used from inventory
signal inventory_item_used(player_id: int, item: InventoryItemPD)
## Emitted when an item is equipped to quickslot
signal item_equipped(player_id: int, item: InventoryItemPD, quickslot_index: int)
## Emitted when an item is unequipped from quickslot
signal item_unequipped(player_id: int, quickslot_index: int)
#endregion

#region Quest Events
## Emitted when a quest is started for a player
signal quest_started(player_id: int, quest: CogitoQuest)
## Emitted when a quest is completed by a player
signal quest_completed(player_id: int, quest: CogitoQuest)
## Emitted when a quest is updated (counter changed, etc.)
signal quest_updated(player_id: int, quest: CogitoQuest)
## Emitted when a quest fails
signal quest_failed(player_id: int, quest: CogitoQuest)
#endregion

#region World Events
## Emitted when world state changes (key-value pair)
signal world_state_changed(key: String, value: Variant, old_value: Variant)
## Emitted when scene changes
signal scene_changed(scene_path: String, scene_name: String)
## Emitted when scene is about to change
signal scene_changing(from_scene: String, to_scene: String)
#endregion

#region Interaction Events
## Emitted when a player starts an interaction
signal interaction_started(player_id: int, target: Node, interaction_type: String)
## Emitted when a player completes an interaction
signal interaction_completed(player_id: int, target: Node, interaction_type: String)
## Emitted when an interaction is cancelled
signal interaction_cancelled(player_id: int, target: Node)
#endregion

#region Attribute Events
## Emitted when a player attribute changes
signal attribute_changed(player_id: int, attribute_name: String, current_value: float, max_value: float)
## Emitted when a player attribute reaches zero (e.g., health -> death)
signal attribute_reached_zero(player_id: int, attribute_name: String)
#endregion

#region Network Events (for future multiplayer)
## Emitted when network connection is established
signal network_connected(peer_id: int)
## Emitted when network connection is lost
signal network_disconnected(peer_id: int)
## Emitted when network error occurs
signal network_error(error: String)
## Emitted when game is paused (server authorized)
signal game_paused
## Emitted when game is resumed (server authorized)
signal game_resumed
#endregion


## Enable/disable automatic network synchronization
@export var enable_network_sync: bool = true

## Authority mode: SERVER_ONLY (only server can emit), CLIENT_AUTHORITY (any client can emit)
enum AuthorityMode { SERVER_ONLY, CLIENT_AUTHORITY }
@export var authority_mode: AuthorityMode = AuthorityMode.SERVER_ONLY


func _ready() -> void:
	CogitoGlobals.debug_log(
		true, "NetworkEventBus", "Event Bus initialized and ready to receive events."
	)
	
	# Connect to network events (NetworkManager emits through this Event Bus)
	# We connect to our own signals to track network state
	network_connected.connect(_on_network_connected)
	network_disconnected.connect(_on_network_disconnected)


## Helper function to emit events with optional logging
func emit_event(event_name: String, args: Array = []) -> void:
	if enable_event_logging:
		CogitoGlobals.debug_log(
			true,
			"NetworkEventBus",
			"Event emitted: %s with args: %s" % [event_name, str(args)]
		)


## Convenience method to emit player registered event
func emit_player_registered(player_id: int, player_node: Node) -> void:
	emit_event("player_registered", [player_id, player_node])
	player_registered.emit(player_id, player_node)


## Convenience method to emit player unregistered event
func emit_player_unregistered(player_id: int) -> void:
	emit_event("player_unregistered", [player_id])
	player_unregistered.emit(player_id)


## Convenience method to emit inventory changed event
func emit_inventory_changed(player_id: int, inventory: CogitoInventory) -> void:
	emit_event("inventory_changed", [player_id, inventory])
	inventory_changed.emit(player_id, inventory)


## Convenience method to emit world state changed event
func emit_world_state_changed(key: String, value: Variant, old_value: Variant = null) -> void:
	emit_event("world_state_changed", [key, value, old_value])
	if old_value != null:
		world_state_changed.emit(key, value, old_value)
	else:
		world_state_changed.emit(key, value, null)


## Check if we should sync this event over network
func _should_sync_event() -> bool:
	if not enable_network_sync:
		return false
	
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return false
	
	return true


## Check if this peer has authority to emit events
func _has_authority() -> bool:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		return true  # Single-player always has authority
	
	if authority_mode == AuthorityMode.SERVER_ONLY:
		return NetworkManager.is_host()
	
	# CLIENT_AUTHORITY mode - any client can emit
	return true


## Callback when network connects
func _on_network_connected(peer_id: int) -> void:
	CogitoGlobals.debug_log(
		enable_event_logging,
		"NetworkEventBus",
		"Network connected, event sync enabled for peer: %d" % peer_id
	)


## Callback when network disconnects
func _on_network_disconnected(peer_id: int) -> void:
	CogitoGlobals.debug_log(
		enable_event_logging,
		"NetworkEventBus",
		"Network disconnected for peer: %d" % peer_id
	)


## Emit event locally and sync over network if needed
func emit_and_sync(signal_name: String, args: Array) -> void:
	# Emit locally first
	emit_event(signal_name, args)
	
	# Sync over network if needed
	if _should_sync_event() and _has_authority():
		_sync_event_rpc.rpc(signal_name, args)


## RPC method to sync events between clients
@rpc("any_peer", "call_local", "reliable")
func _sync_event_rpc(signal_name: String, args: Array) -> void:
	# Only process if we're not the sender (to avoid duplicate events)
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == multiplayer.get_unique_id():
		return
	
	# Emit the event locally on receiving clients
	emit_event("network_sync_" + signal_name, args)
	
	# Map signal names to actual signal emissions
	# This is a simplified version - in production, you'd want a more robust mapping
	match signal_name:
		"player_registered":
			if args.size() >= 2:
				player_registered.emit(args[0], args[1])
		"player_unregistered":
			if args.size() >= 1:
				player_unregistered.emit(args[0])
		"inventory_changed":
			if args.size() >= 2:
				inventory_changed.emit(args[0], args[1])
		"world_state_changed":
			if args.size() >= 3:
				world_state_changed.emit(args[0], args[1], args[2])
		"interaction_started":
			if args.size() >= 3:
				interaction_started.emit(args[0], args[1], args[2])
		"interaction_completed":
			if args.size() >= 3:
				interaction_completed.emit(args[0], args[1], args[2])
		# Add more mappings as needed
