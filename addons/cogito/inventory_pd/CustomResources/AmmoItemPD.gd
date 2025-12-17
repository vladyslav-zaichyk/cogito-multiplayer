extends InventoryItemPD
class_name AmmoItemPD

@export_group("Ammo settings")
## The amount one item addes to the target item charge. For bullets this should be 1.
@export var reload_amount: int = 1


# Using method to enable other scripts to check if this is an ammo item. Used in cogito_inventory.gd.
func is_ammo_item():
	pass


func use(target) -> bool:
	# Target should always be player? Null check to override using the CogitoSceneManager, which stores a reference to current player node
	if target == null or target.is_in_group("external_inventory"):
		# Get player from PlayerManager (new system) or fallback to old system
		var player = PlayerManager.get_current_player() if PlayerManager else null
		if not player and CogitoSceneManager and CogitoSceneManager.has_method("get") and CogitoSceneManager.get("_current_player_node"):
			player = CogitoSceneManager._current_player_node
		CogitoGlobals.debug_log(
			true,
			"AmmoItemPD",
			"Bad target pass. Setting target to" + str(player)
		)
		target = player

	if hint_text_on_use != "":
		target.player_interaction_component.send_hint(hint_icon_on_use, hint_text_on_use)
	return true
