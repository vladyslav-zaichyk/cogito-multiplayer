extends InventoryItemPD
class_name CombinableItemPD

@export_group("Combinable settings")
## The name of the item that this item combines with. Caution: String has to be a perfect match, so watch casing and space.
@export var target_item_combine: String = ""
## The item that gets created when this item is combined with the one above.
@export var resulting_item: InventorySlotPD = null


func use(target) -> bool:
	# Target should always be player? Null check to override using the CogitoSceneManager, which stores a reference to current player node
	if target == null or target.is_in_group("external_inventory"):
		# Get player from PlayerManager (new system) or fallback to old system
		var player = PlayerManager.get_current_player() if PlayerManager else null
		if not player and CogitoSceneManager and CogitoSceneManager.has_method("get") and CogitoSceneManager.get("_current_player_node"):
			player = CogitoSceneManager._current_player_node
		CogitoGlobals.debug_log(
			true,
			"CombinableItemPD",
			"Bad target pass. Setting target to" + str(player)
		)
		target = player

	if hint_text_on_use != "":
		target.player_interaction_component.send_hint(hint_icon_on_use, hint_text_on_use)
	return true


# Method to check if this is a combinable item.
func is_combinable():
	pass
