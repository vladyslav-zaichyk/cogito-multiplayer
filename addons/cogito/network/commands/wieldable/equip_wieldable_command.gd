extends Command
class_name EquipWieldableCommand
## Command for equipping a wieldable item.
## This command handles the equip logic and emits WieldableEquippedEvent on success.

## Event class uses class_name for static typing, so we can call it directly

## Wieldable item to equip
var wieldable_item: WieldableItemPD
## Inventory slot index where the wieldable is located
var slot_index: int = -1


func _init(player_id_value: int, wieldable_value: WieldableItemPD, slot_index_value: int = -1):
	super._init(player_id_value)
	wieldable_item = wieldable_value
	slot_index = slot_index_value
	validation_type = ValidationType.CLIENT_VALIDATION  # Client validates wieldable equip (can be changed to HOST_VALIDATION if needed)


## Execute the command
func execute() -> CommandResult:
	# Get player with strict typing
	var player: CogitoPlayer = null
	if PlayerManager:
		player = PlayerManager.get_player(player_id) as CogitoPlayer
	
	if not player:
		var error_result = CommandResult.new(false, "Player not found")
		error_result.response_code = CommandResult.ResponseCode.PLAYER_NOT_FOUND
		return error_result
	
	# Use strict typing - CogitoPlayer has player_interaction_component property
	var player_interaction_component: PlayerInteractionComponent = player.player_interaction_component
	if not player_interaction_component:
		var error_result = CommandResult.new(false, "Player interaction component not found")
		error_result.response_code = CommandResult.ResponseCode.EXECUTION_FAILED
		return error_result
	
	# Check if player is carrying something (can't equip while carrying)
	if player_interaction_component.carried_object != null:
		var error_result = CommandResult.new(false, "Can't equip item while carrying")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	# Check if wieldable is already being wielded
	if wieldable_item.is_being_wielded:
		var error_result = CommandResult.new(false, "Wieldable is already being wielded")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	# Check if player is currently changing wieldables
	if player_interaction_component.is_changing_wieldables:
		var error_result = CommandResult.new(false, "Player is already changing wieldables")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	var result = CommandResult.new()
	
	# Execute equip logic (similar to WieldableItemPD.take_out())
	# IMPORTANT: change_wieldable_to() must be called to set equipped_wieldable_item first.
	# The change_wieldable_to() -> equip_wieldable() chain will call update_wieldable_data()
	# at the end (in equip_wieldable(), line 496), which emits updated_wieldable_data signal
	# with the correct new wieldable for network sync.
	# We don't need to call update_wieldable_data() here because equip_wieldable() does it.
	wieldable_item.is_being_wielded = true
	player_interaction_component.change_wieldable_to(wieldable_item)
	
	# Create event
	var event = WieldableEquippedEvent.new(player_id, wieldable_item, slot_index)
	result.add_event(event)
	result.success = true
	result.data["slot_index"] = slot_index
	
	return result


## Validate the command before execution
func validate() -> bool:
	# Check if player exists
	if not PlayerManager:
		return false
	
	var player: CogitoPlayer = PlayerManager.get_player(player_id) as CogitoPlayer
	if not player:
		return false
	
	# Use strict typing - CogitoPlayer has player_interaction_component property
	var player_interaction_component: PlayerInteractionComponent = player.player_interaction_component
	if not player_interaction_component:
		return false
	
	# Check if player is carrying something
	if player_interaction_component.carried_object != null:
		return false
	
	# Check if wieldable is already being wielded
	if wieldable_item.is_being_wielded:
		return false
	
	# Check if player is currently changing wieldables
	if player_interaction_component.is_changing_wieldables:
		return false
	
	return true


## Serialize command for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	
	# Serialize wieldable item data
	var item_data = {}
	if wieldable_item:
		# Try to get resource_path - prefer .tres files over .gd scripts
		var resource_path = wieldable_item.resource_path
		
		# If resource_path is empty or points to a script (.gd), try to find the .tres file
		if resource_path.is_empty() or resource_path.ends_with(".gd"):
			var item_name = wieldable_item.name
			if not item_name.is_empty():
				# Try common resource paths (similar to network_wieldable_sync.gd)
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
							break
		
		item_data = {
			"name": wieldable_item.name,
			"resource_path": resource_path,
			"item_type": wieldable_item.get_script().get_path().get_file().get_basename() if wieldable_item.get_script() else "",
			"charge_current": wieldable_item.charge_current,
			"charge_max": wieldable_item.charge_max
		}
	
	base_data["wieldable_item"] = item_data
	base_data["slot_index"] = slot_index
	return base_data


## Deserialize command from network data
static func deserialize(data: Dictionary) -> Command:
	var player_id = data.get("player_id", -1)
	var item_data = data.get("wieldable_item", {})
	var slot_index = data.get("slot_index", -1)
	
	# Try to load wieldable from resource path
	var wieldable: WieldableItemPD = null
	
	# Check if item_data exists
	if item_data.is_empty():
		push_error("EquipWieldableCommand: Failed to deserialize wieldable_item - item_data is empty")
		return null
	
	# Try resource_path first (skip if it's a .gd script)
	if item_data.has("resource_path") and not item_data["resource_path"].is_empty():
		var resource_path = item_data["resource_path"]
		# Skip .gd scripts - they're not loadable resources
		if not resource_path.ends_with(".gd"):
			wieldable = load(resource_path) as WieldableItemPD
			if wieldable:
				# Restore charge state
				wieldable.charge_current = item_data.get("charge_current", 0.0)
				wieldable.charge_max = item_data.get("charge_max", 0.0)
			else:
				push_warning("EquipWieldableCommand: Failed to load wieldable from resource_path: %s, trying fallback" % resource_path)
		else:
			push_warning("EquipWieldableCommand: resource_path points to script (.gd), trying fallback: %s" % resource_path)
	
	# Fallback: try to find by name if resource_path failed or missing
	if not wieldable and item_data.has("name"):
		var item_name = item_data["name"]
		# Try common resource paths (similar to network_wieldable_sync.gd)
		var possible_paths = [
			"res://addons/cogito/inventory_pd/Items/Cogito_%s.tres" % item_name.replace(" ", ""),
			"res://addons/cogito/inventory_pd/Items/Cogito_%s.tres" % item_name.replace(" ", "_"),
			"res://addons/cogito/inventory_pd/Items/%s.tres" % item_name.replace(" ", ""),
			"res://addons/cogito/inventory_pd/Items/%s.tres" % item_name.replace(" ", "_"),
		]
		
		# Special cases (like in network_wieldable_sync.gd)
		if item_name == "Foam Pistol":
			possible_paths.insert(0, "res://addons/cogito/inventory_pd/Items/Cogito_Pistol.tres")
		
		for path in possible_paths:
			if ResourceLoader.exists(path):
				var test_resource = load(path) as WieldableItemPD
				if test_resource and test_resource.name == item_name:
					wieldable = test_resource
					# Restore charge state
					wieldable.charge_current = item_data.get("charge_current", 0.0)
					wieldable.charge_max = item_data.get("charge_max", 0.0)
					break
	
	if not wieldable:
		var item_name = item_data.get("name", "unknown") if item_data.has("name") else "unknown"
		push_error("EquipWieldableCommand: Failed to deserialize wieldable_item - cannot load wieldable '%s' (resource_path missing or invalid)" % item_name)
		return null
	
	var command = EquipWieldableCommand.new(player_id, wieldable, slot_index)
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	return command
