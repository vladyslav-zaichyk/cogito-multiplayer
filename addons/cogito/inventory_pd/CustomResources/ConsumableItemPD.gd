extends InventoryItemPD
class_name ConsumableItemPD

@export_group("Consumable settings")
## Name of attribute that the item is going to replenish. (For example "health")
@export var attribute_name: String
## The change amount that gets applied to the attribute. (For example 25 to heal 25 HP. Allows negative values too.)
@export var attribute_change_amount: float

enum ValueType { CURRENT, MAX }
## Set if the attribute value you want to change is the current one or the maximum one.
@export var value_to_change: ValueType

@export var consumable_effects: Array[ConsumableEffect]


func use(target) -> bool:
	# Target should always be player? Null check to override using the CogitoSceneManager, which stores a reference to current player node
	if target == null or target.is_in_group("external_inventory"):
		# Get player from PlayerManager (new system) or fallback to old system
		var player = PlayerManager.get_current_player() if PlayerManager else null
		if not player and CogitoSceneManager and CogitoSceneManager.has_method("get") and CogitoSceneManager.get("_current_player_node"):
			player = CogitoSceneManager._current_player_node
		CogitoGlobals.debug_log(
			true,
			"ConsumableItemPD",
			"Bad target pass. Setting target to" + str(player)
		)
		target = player

	if target.increase_attribute(attribute_name, attribute_change_amount, value_to_change):
		print("Inventory item: Target ", target, " is using ", self)
		Audio.play_sound(sound_use)
		if hint_text_on_use != "":
			target.player_interaction_component.send_hint(hint_icon_on_use, hint_text_on_use)

		if consumable_effects:
			print(self.name, ": Attemtping to apply consumable effects...")
			for effect in consumable_effects:
				effect.use(target)

		return true
	else:
		target.player_interaction_component.send_hint(
			hint_icon_on_use, str(attribute_name + " is already maxed.")
		)
		return false


## Check if this item is consumable.
## Returns true for consumable items (items that should be removed from inventory after use).
func is_consumable() -> bool:
	return true
