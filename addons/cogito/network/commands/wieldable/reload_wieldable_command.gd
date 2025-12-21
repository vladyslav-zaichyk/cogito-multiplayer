extends Command
class_name ReloadWieldableCommand
## Command for reloading a wieldable item.
## This command handles the reload logic and emits WieldableReloadedEvent on success.

## Event class uses class_name for static typing, so we can call it directly


func _init(player_id_value: int):
	super._init(player_id_value)
	validation_type = ValidationType.HOST_VALIDATION  # Host validates reload (important for ammo consumption)


## Execute the command
func execute() -> CommandResult:
	# Get player
	var player = null
	if PlayerManager:
		player = PlayerManager.get_player(player_id)
	
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
	
	# Use strict typing - CogitoPlayer has inventory_data property
	var inventory: CogitoInventory = player.inventory_data
	if not inventory:
		var error_result = CommandResult.new(false, "Player inventory not found")
		error_result.response_code = CommandResult.ResponseCode.PLAYER_NOT_FOUND
		return error_result
	
	# Check if wieldable node exists
	if not player_interaction_component.equipped_wieldable_node:
		var error_result = CommandResult.new(false, "No wieldable equipped")
		error_result.response_code = CommandResult.ResponseCode.ITEM_NOT_FOUND
		return error_result
	
	# Check if animation is playing (can't interrupt)
	if player_interaction_component.equipped_wieldable_node.animation_player.is_playing():
		var error_result = CommandResult.new(false, "Can't interrupt current action / animation")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	# Check if wieldable item exists
	if not player_interaction_component.equipped_wieldable_item:
		var error_result = CommandResult.new(false, "No wieldable item reference")
		error_result.response_code = CommandResult.ResponseCode.ITEM_NOT_FOUND
		return error_result
	
	var wieldable_item = player_interaction_component.equipped_wieldable_item
	
	# Check if item uses reloading
	if wieldable_item.no_reload:
		var error_result = CommandResult.new(false, "Item doesn't use reloading")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	# Calculate ammo needed
	var ammo_needed: int = abs(wieldable_item.charge_max - wieldable_item.charge_current)
	if ammo_needed <= 0:
		var error_result = CommandResult.new(false, "Wieldable is fully charged")
		error_result.response_code = CommandResult.ResponseCode.INVALID_STATE
		return error_result
	
	# Check if player has ammo
	if wieldable_item.get_item_amount_in_inventory(wieldable_item.ammo_item_name) <= 0:
		var error_result = CommandResult.new(false, "You have no ammo for this wieldable")
		error_result.response_code = CommandResult.ResponseCode.ITEM_NOT_FOUND
		return error_result
	
	var result = CommandResult.new()
	
	# Play reload animation
	player_interaction_component.equipped_wieldable_node.reload()
	
	# Consume ammo from inventory
	var total_ammo_used: int = 0
	for slot: InventorySlotPD in inventory.inventory_slots:
		if ammo_needed <= 0:
			break
		if slot == null or slot.inventory_item.name != wieldable_item.ammo_item_name:
			continue
		
		var ammo_used: int
		var slot_ammo: AmmoItemPD = slot.inventory_item
		var quantity_needed: int = ceili(float(ammo_needed) / slot_ammo.reload_amount)
		
		if slot.quantity <= quantity_needed:
			ammo_used = slot_ammo.reload_amount * slot.quantity
			inventory.remove_slot_data(slot)
		elif slot.quantity > quantity_needed:
			ammo_used = slot_ammo.reload_amount * quantity_needed
			slot.quantity -= quantity_needed
		
		wieldable_item.add(ammo_used)
		total_ammo_used += ammo_used
		ammo_needed -= ammo_used
	
	# Emit inventory update
	inventory.inventory_updated.emit(inventory)
	wieldable_item.update_wieldable_data(player_interaction_component)
	
	# Create event
	var event = WieldableReloadedEvent.new(player_id, wieldable_item, total_ammo_used, wieldable_item.charge_current)
	result.add_event(event)
	result.success = true
	result.data["ammo_used"] = total_ammo_used
	result.data["new_charge"] = wieldable_item.charge_current
	
	return result


## Validate the command before execution
func validate() -> bool:
	# Check if player exists
	if not PlayerManager:
		return false
	
	var player = PlayerManager.get_player(player_id)
	if not player:
		return false
	
	# Use strict typing - CogitoPlayer has player_interaction_component property
	var player_interaction_component: PlayerInteractionComponent = player.player_interaction_component
	if not player_interaction_component:
		return false
	
	# Use strict typing - CogitoPlayer has inventory_data property
	var inventory: CogitoInventory = player.inventory_data
	if not inventory:
		return false
	
	# Check if wieldable node exists
	if not player_interaction_component.equipped_wieldable_node:
		return false
	
	# Check if animation is playing
	if player_interaction_component.equipped_wieldable_node.animation_player.is_playing():
		return false
	
	# Check if wieldable item exists
	if not player_interaction_component.equipped_wieldable_item:
		return false
	
	var wieldable_item = player_interaction_component.equipped_wieldable_item
	
	# Check if item uses reloading
	if wieldable_item.no_reload:
		return false
	
	# Check if ammo is needed
	var ammo_needed: int = abs(wieldable_item.charge_max - wieldable_item.charge_current)
	if ammo_needed <= 0:
		return false
	
	# Check if player has ammo
	if wieldable_item.get_item_amount_in_inventory(wieldable_item.ammo_item_name) <= 0:
		return false
	
	return true


## Serialize command for network transmission
func serialize() -> Dictionary:
	var base_data = super.serialize()
	# Reload command doesn't need additional data - it reloads current wieldable
	return base_data


## Deserialize command from network data
static func deserialize(data: Dictionary) -> Command:
	var player_id = data.get("player_id", -1)
	
	var command = ReloadWieldableCommand.new(player_id)
	command.command_id = data.get("command_id", command.command_id)
	command.timestamp = data.get("timestamp", command.timestamp)
	command.executed = data.get("executed", false)
	
	return command

