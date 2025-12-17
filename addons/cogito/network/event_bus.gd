extends Node
## Centralized Event Bus for decoupling systems and preparing for multiplayer.
## This system allows components to communicate without direct dependencies.
## Note: This is an autoload singleton, not a class_name

## Enable/disable event logging for debugging
@export var enable_event_logging: bool = false

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
#endregion

#region Inventory Events
## Emitted when a player picks up an item
## Note: Using Resource/Variant to avoid class loading order issues
signal inventory_item_picked(player_id: int, item: Resource, slot_data: Resource)
## Emitted when a player drops an item
signal inventory_item_dropped(player_id: int, item: Resource, position: Vector3)
## Emitted when an inventory changes (items moved, used, etc.)
signal inventory_changed(player_id: int, inventory: Resource)
## Emitted when an item is used from inventory
signal inventory_item_used(player_id: int, item: Resource)
## Emitted when an item is equipped to quickslot
signal item_equipped(player_id: int, item: Resource, quickslot_index: int)
## Emitted when an item is unequipped from quickslot
signal item_unequipped(player_id: int, quickslot_index: int)
#endregion

#region Quest Events
## Emitted when a quest is started for a player
## Note: Using Resource to avoid class loading order issues
signal quest_started(player_id: int, quest: Resource)
## Emitted when a quest is completed by a player
signal quest_completed(player_id: int, quest: Resource)
## Emitted when a quest is updated (counter changed, etc.)
signal quest_updated(player_id: int, quest: Resource)
## Emitted when a quest fails
signal quest_failed(player_id: int, quest: Resource)
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
#endregion


func _ready() -> void:
	CogitoGlobals.debug_log(
		true, "NetworkEventBus", "Event Bus initialized and ready to receive events."
	)


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
func emit_inventory_changed(player_id: int, inventory: Resource) -> void:
	emit_event("inventory_changed", [player_id, inventory])
	inventory_changed.emit(player_id, inventory)


## Convenience method to emit world state changed event
func emit_world_state_changed(key: String, value: Variant, old_value: Variant = null) -> void:
	emit_event("world_state_changed", [key, value, old_value])
	if old_value != null:
		world_state_changed.emit(key, value, old_value)
	else:
		world_state_changed.emit(key, value, null)
