extends Node
## Test script for NetworkEventBus
## This script demonstrates how to use the Event Bus system

func _ready() -> void:
	# Subscribe to events
	NetworkEventBus.player_registered.connect(_on_player_registered)
	NetworkEventBus.inventory_changed.connect(_on_inventory_changed)
	NetworkEventBus.world_state_changed.connect(_on_world_state_changed)
	
	print("Event Bus Test: Subscribed to events")
	
	# Test emitting events (in a real scenario, these would be emitted by other systems)
	_test_events()


func _test_events() -> void:
	print("\n=== Testing Event Bus ===")
	
	# Test player registered event
	var test_player = Node.new()
	test_player.name = "TestPlayer"
	NetworkEventBus.emit_player_registered(1, test_player)
	
	# Test inventory changed event (with null for testing)
	# NetworkEventBus.emit_inventory_changed(1, null)
	
	# Test world state changed event
	NetworkEventBus.emit_world_state_changed("test_key", "test_value", null)
	
	print("=== Event Bus Test Complete ===\n")


func _on_player_registered(player_id: int, player_node: Node) -> void:
	print("Event Bus Test: Player registered - ID: %d, Node: %s" % [player_id, player_node.name])


func _on_inventory_changed(player_id: int, inventory: Resource) -> void:
	print("Event Bus Test: Inventory changed - Player ID: %d" % player_id)


func _on_world_state_changed(key: String, value: Variant, old_value: Variant) -> void:
	print("Event Bus Test: World state changed - Key: %s, Value: %s" % [key, str(value)])

