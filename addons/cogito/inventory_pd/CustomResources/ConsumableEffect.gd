extends Resource
class_name ConsumableEffect

## Name of attribute that the item is going to replenish. (For example "health")
@export var attribute_name: String
## The change amount that gets applied to the attribute. (For example 25 to heal 25 HP. Allows negative values too.)
@export var attribute_change_amount: float

enum ValueType { CURRENT, MAX }
## Set if the attribute value you want to change is the current one or the maximum one.
@export var value_to_change: ValueType


func use(target) -> bool:
	# Target should always be player? Null check to override using the CogitoSceneManager, which stores a reference to current player node
	if target == null or target.is_in_group("external_inventory"):
		# Get player from PlayerManager (new system) or fallback to old system
		var player = PlayerManager.get_current_player() if PlayerManager else null
		if not player and CogitoSceneManager and CogitoSceneManager.has_method("get") and CogitoSceneManager.get("_current_player_node"):
			player = CogitoSceneManager._current_player_node
		CogitoGlobals.debug_log(
			true,
			"ConsumableEffect",
			"Bad target pass. Setting target to" + str(player)
		)
		target = player

	if target.increase_attribute(attribute_name, attribute_change_amount, value_to_change):
		print(
			"Inventory item: Target ",
			target.name,
			": ",
			attribute_name,
			" ",
			attribute_change_amount
		)
		return true
	else:
		return false
