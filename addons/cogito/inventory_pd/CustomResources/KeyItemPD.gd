extends InventoryItemPD
class_name KeyItemPD

@export_group("Key settings")
## If this is checked, the key item will be removed from the inventory after it's been used on the target object. CAUTION: If you set this to true, make sure there are enough keys in your game to open all doors that require them. Otherwise you might softlock your player.
@export var discard_after_use: bool = false


func use(target) -> bool:
	# Target should always be player? Null check to override using the CogitoSceneManager, which stores a reference to current player node
	if target == null or target.is_in_group("external_inventory"):
		# Get player from PlayerManager (new system) or fallback to old system
		var player = PlayerManager.get_current_player() if PlayerManager else null
		if not player and CogitoSceneManager and CogitoSceneManager.has_method("get") and CogitoSceneManager.get("_current_player_node"):
			player = CogitoSceneManager._current_player_node
		CogitoGlobals.debug_log(
			true,
			"KeyItemPD",
			"Bad target pass. Setting target to" + str(player)
		)
		target = player

	if hint_text_on_use != "":
		target.player_interaction_component.send_hint(hint_icon_on_use, hint_text_on_use)
	return true
