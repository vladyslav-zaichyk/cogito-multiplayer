extends Resource
class_name CogitoInventory

signal inventory_interact(inventory_data: CogitoInventory, index: int, mouse_button: int)
signal inventory_button_press(inventory_data: CogitoInventory, index: int, action: String)
signal inventory_updated(inventory_data: CogitoInventory)
signal unbind_quickslot_by_index(quickslot_index: int)
signal picked_up_new_inventory_item(slot_data: InventorySlotPD)

## Enables grid inventory. If using, make sure player and ALL interactables have this set to true.
@export var grid: bool
## Injects items from this into the inventory slots
@export var starter_inventory: Array[InventorySlotPD]
@export var inventory_size: Vector2i = Vector2i(4, 1)
@export var inventory_slots: Array[InventorySlotPD]

var assigned_quickslots: Array[InventorySlotPD]
var owner: Node
## Owner ID for multiplayer support (player_id or other unique identifier)
var owner_id: int = -1

@export var first_slot: InventorySlotPD


func _init():
	if inventory_slots.size() > 0:
		first_slot = inventory_slots[0]


# Call this in your initial scene
func apply_initial_inventory():
	inventory_slots.resize(inventory_size.x * inventory_size.y)
	for item in starter_inventory:
		pick_up_slot_data(item)
	if inventory_slots.size() > 0:
		first_slot = inventory_slots[0]


func on_slot_clicked(index: int, mouse_button: int):
	inventory_interact.emit(self, index, mouse_button)


func on_slot_button_pressed(index: int, action: String):
	CogitoGlobals.debug_log(
		true,
		"cogito_inventory.gd",
		"on_slot_button_pressed. index=" + str(index) + ", action=" + str(action)
	)
	inventory_button_press.emit(self, index, action)


func null_out_slots(slot_data):
	if not slot_data:
		return
	var size = slot_data.inventory_item.item_size if grid else Vector2i(1, 1)
	for x in size.x:
		for y in size.y:
			inventory_slots[slot_data.origin_index + x + (y * inventory_size.x)] = null


# Returns slot data without actually changing the slot
func get_slot_data(index: int) -> InventorySlotPD:
	var slot_data = inventory_slots[index]
	if slot_data:
		return slot_data
	else:
		return null


func grab_slot_data(index: int) -> InventorySlotPD:
	var slot_data = inventory_slots[index]

	if slot_data:
		null_out_slots(slot_data)
		_emit_inventory_updated()
		return slot_data
	else:
		return null


func grab_single_slot_data(index: int) -> InventorySlotPD:
	var slot_data = inventory_slots[index]
	if slot_data:
		slot_data.quantity -= 1
		if slot_data.quantity < 1:
			null_out_slots(slot_data)
		_emit_inventory_updated()
		return slot_data
	else:
		return null


func use_slot_data(index: int):
	if index == -1:  # No item assigned to hotbar
		return

	var slot_data = inventory_slots[index]

	if not slot_data:
		return

	if !slot_data.inventory_item.has_method("use"):
		return

	var use_successful: bool = slot_data.inventory_item.use(owner)

	# Emit inventory_item_used through NetworkEventBus (for multiplayer sync)
	if use_successful and NetworkEventBus:
		var player_id := -1
		if PlayerManager and owner:
			player_id = PlayerManager.get_player_id(owner)
		if player_id != -1:
			NetworkEventBus.inventory_item_used.emit(player_id, slot_data.inventory_item)

	if slot_data.inventory_item.has_method("is_consumable") and use_successful:
		slot_data.quantity -= 1
		if slot_data.quantity < 1:
			null_out_slots(slot_data)

	_emit_inventory_updated()


# Function to remove a specific item from inventory directly (without picking it up etc)
# Used for example by KEY items to be discarded after using them
func remove_slot_data(slot_data_to_remove: InventorySlotPD):
	var index = inventory_slots.find(slot_data_to_remove, 0)
	if index == -1:
		CogitoGlobals.debug_log(
			true, "cogito_inventory.gd", "Couldn't remove item from inventory as it wasn't found."
		)
		return
	else:
		print("Removing ", slot_data_to_remove, " at index ", index)
		null_out_slots(slot_data_to_remove)
		_emit_inventory_updated()


func remove_item_from_stack(slot_data: InventorySlotPD):
	var index = inventory_slots.find(slot_data, 0)
	if index == -1:
		CogitoGlobals.debug_log(
			true, "cogito_inventory.gd", "Couldn't remove item from item stack as it wasn't found."
		)
		return
	else:
		print("Removing ", slot_data, " at index ", index)
		inventory_slots[index].quantity -= 1
		# What happens if last item of stack is removed.
		if inventory_slots[index].quantity <= 0:
			null_out_slots(slot_data)

			# If inventory slot was bind to a quick slot, unbind it.
			var quickslot_index = assigned_quickslots.find(inventory_slots[index], 0)
			if quickslot_index > -1:
				unbind_quickslot_by_index.emit(quickslot_index)

		_emit_inventory_updated()


func drop_slot_data(grabbed_slot_data: InventorySlotPD, index: int) -> InventorySlotPD:
	var slot_data = inventory_slots[index]

	var return_slot_data: InventorySlotPD
	if slot_data and slot_data.can_fully_merge_with(grabbed_slot_data):
		slot_data.fully_merge_with(grabbed_slot_data)
	elif is_enough_space(grabbed_slot_data, index, false):
		# Swap out item
		var item_to_swap = get_item_to_swap(grabbed_slot_data, index)

		# If item to swap is being wielded, cancel the swap
		if (
			item_to_swap
			and item_to_swap.inventory_item
			and item_to_swap.inventory_item.is_being_wielded
		):
			print("cogito_inventory.gd: ERROR - cants swap out item thats being wielded.")
			return grabbed_slot_data

		null_out_slots(item_to_swap)
		grabbed_slot_data.origin_index = index
		inventory_slots[index] = grabbed_slot_data
		add_adjacent_slots(index)
		return_slot_data = item_to_swap
	else:
		# do nothing, the grabbed slot remains the same
		return grabbed_slot_data

	inventory_updated.emit(self)
	return return_slot_data


func drop_single_slot_data(grabbed_slot_data: InventorySlotPD, index: int) -> InventorySlotPD:
	var slot_data = inventory_slots[index]

	if not slot_data and is_enough_space(grabbed_slot_data, index, false):
		inventory_slots[index] = grabbed_slot_data.create_single_slot_data(index)
		add_adjacent_slots(index)
		CogitoGlobals.debug_log(
			true,
			"cogito_inventory.gd",
			"drop_single_slot_data(...): grabbed item placed in inventory."
		)
	elif not slot_data:
		return grabbed_slot_data
	elif slot_data.can_merge_with(grabbed_slot_data):
		slot_data.fully_merge_with(
			grabbed_slot_data.create_single_slot_data(slot_data.origin_index)
		)
		CogitoGlobals.debug_log(
			true,
			"cogito_inventory.gd",
			"drop_single_slot_data(...): grabbed item fully merged with target."
		)
		#return null
	# Logic for ammo items
	elif (
		slot_data.inventory_item.has_method("update_wieldable_data")
		and grabbed_slot_data.inventory_item.has_method("is_ammo_item")
		and slot_data.inventory_item.ammo_item_name == grabbed_slot_data.inventory_item.name
	):
		CogitoGlobals.debug_log(
			true,
			"cogito_inventory.gd",
			"drop_single_slot_data(...): AmmoItem detected. Attempting to reload target."
		)
		# Check if there's room for charge
		if (
			slot_data.inventory_item.charge_max - slot_data.inventory_item.charge_current
			>= grabbed_slot_data.inventory_item.reload_amount
		):
			var player = _get_player_node()
			if player and player.has_method("player_interaction_component"):
				player.player_interaction_component.send_hint(
					null,
					(
						"Charging "
						+ slot_data.inventory_item.name
						+ " by "
						+ str(grabbed_slot_data.inventory_item.reload_amount)
					)
				)
			slot_data.inventory_item.add(grabbed_slot_data.inventory_item.reload_amount)
			grabbed_slot_data.quantity -= 1
		else:
			(
				CogitoGlobals
				. debug_log(
					true,
					"cogito_inventory.gd",
					"drop_single_slot_data(...): AmmoItem detected. Target charge is too high to be reloaded."
				)
			)
	# Check if grabbed item is a combinable AND check if slot item is the target combine item:
	elif (
		grabbed_slot_data.inventory_item.has_method("is_combinable")
		and slot_data.inventory_item.name == grabbed_slot_data.inventory_item.target_item_combine
	):
		# Reduce/destroy both items.
		remove_slot_data(slot_data)
		grabbed_slot_data.quantity -= 1
		# Add resulting item to inventory:
		pick_up_slot_data(grabbed_slot_data.inventory_item.resulting_item)

	inventory_updated.emit(self)

	if grabbed_slot_data.quantity > 0:
		return grabbed_slot_data
	else:
		return null

	#if grabbed_slot_data.quantity > 0:
	## Swapping items
	#var item_to_swap = get_item_to_swap(grabbed_slot_data, index)
	#null_out_slots(item_to_swap)
	#return grabbed_slot_data
	#else:
	## Placing items
	#print("cogito_inventory.gd: drop_single_slot_data( grabbed item name=", grabbed_slot_data.inventory_item.name, ", ", index, "): Placing items reached.")
	#return null


func pick_up_slot_data(slot_data: InventorySlotPD) -> bool:
	for index in inventory_slots.size():
		slot_data.origin_index = index
		if inventory_slots[index] and inventory_slots[index].can_fully_merge_with(slot_data):
			slot_data.origin_index = index
			inventory_slots[index].fully_merge_with(slot_data)
			_emit_inventory_updated()
			# Emit through Event Bus for merged items (so network sync can track them)
			if owner_id != -1 and NetworkEventBus:
				NetworkEventBus.inventory_item_picked.emit(owner_id, slot_data.inventory_item, slot_data)
			return true

	for index in inventory_slots.size():
		slot_data.origin_index = index
		if not inventory_slots[index] and is_enough_space(slot_data, index, true):
			inventory_slots[index] = slot_data
			add_adjacent_slots(index)
			_emit_inventory_updated()
			picked_up_new_inventory_item.emit(slot_data)
			# Emit through Event Bus
			if owner_id != -1 and NetworkEventBus:
				NetworkEventBus.inventory_item_picked.emit(owner_id, slot_data.inventory_item, slot_data)
			return true

	# Try to get player from owner, PlayerManager, or fallback to CogitoSceneManager
	var player = _get_player_node()
	if player and player.has_method("player_interaction_component"):
		player.player_interaction_component.send_hint(null, "Unable to pick up item.")
	return false


## LootComponent - Gets all items in inventory
func get_all_items() -> Array[InventoryItemPD]:
	var result: Array[InventoryItemPD] = []
	for slot in inventory_slots:
		if slot != null:
			result.append(slot.inventory_item)
	return result


# Function to attempt to take all the items in a given inventory.
func take_all_items(target_inventory: CogitoInventory):
	for slot in inventory_slots:
		if slot != null:
			#grab item in slot and add it to target inventory
			if target_inventory.pick_up_slot_data(slot.duplicate()):
				print("Grabbed ", slot.inventory_item.name)
				remove_slot_data(slot)  #Empty the slot
				force_inventory_update()


func force_inventory_update():
	print("Forced inventory update: ", self)
	inventory_updated.emit(self)


func add_adjacent_slots(index: int):
	if not grid:
		return
	var size = inventory_slots[index].inventory_item.item_size
	for x in size.x:
		for y in size.y:
			inventory_slots[index + x + (y * inventory_size.x)] = inventory_slots[index]


# check if an item either has free slots to occupy or can swap one item out
func is_enough_space(grabbed_slot_data: InventorySlotPD, to_place_index: int, pickup: bool):
	var swap_origin = -1
	var size = grabbed_slot_data.inventory_item.item_size if grid else Vector2i(1, 1)
	# check outside of y bounds
	if (
		(to_place_index + (size.x - 1) + ((size.y - 1) * inventory_size.x))
		>= inventory_slots.size()
	):
		return false
	var right_edge: int = to_place_index + size.x - 1
	# check row does not shift
	if int(to_place_index / inventory_size.x) != int(right_edge / inventory_size.x):
		return false
	for x in size.x:
		for y in size.y:
			var adj_item = inventory_slots[to_place_index + x + (y * inventory_size.x)]
			if not adj_item:
				continue
			elif pickup:  # if picking up an item, swap logic should not be invoked
				return false
			elif swap_origin == -1 and adj_item.origin_index != -1:
				swap_origin = adj_item.origin_index
			elif adj_item.origin_index != swap_origin and adj_item.origin_index != -1:
				return false
	return true


func get_item_to_swap(grabbed_slot_data: InventorySlotPD, to_place_index: int):
	var size = grabbed_slot_data.inventory_item.item_size if grid else Vector2i(1, 1)
	for x in size.x:
		for y in size.y:
			var adj_item = inventory_slots[to_place_index + x + (y * inventory_size.x)]
			if not adj_item:
				continue
			if adj_item.origin_index != -1:
				return adj_item


## Set owner and register inventory in InventoryManager
func set_owner(new_owner: Node) -> void:
	owner = new_owner
	
	# Try to get owner_id from owner
	if owner and owner.has_method("get"):
		var pid = owner.get("player_id")
		if pid != null and pid != -1:
			owner_id = pid
			# Register in InventoryManager
			if InventoryManager and not InventoryManager.has_inventory(owner_id):
				InventoryManager.register_inventory(owner_id, self)
			return
	
	# If owner is a player but doesn't have player_id yet, try to get it
	if owner and owner is CogitoPlayer:
		if PlayerManager and PlayerManager.has_local_player():
			var local_player = PlayerManager.get_local_player()
			if local_player == owner:
				owner_id = PlayerManager.get_local_player_id()
				if InventoryManager and owner_id != -1 and not InventoryManager.has_inventory(owner_id):
					InventoryManager.register_inventory(owner_id, self)


## Helper function to get player node (for backward compatibility)
func _get_player_node() -> Node:
	# First try to use owner if it's a player
	if owner and owner is CogitoPlayer:
		return owner
	
	# Try PlayerManager (new system)
	if PlayerManager and PlayerManager.has_local_player():
		return PlayerManager.get_local_player()
	
	# Fallback to old system
	if CogitoSceneManager and CogitoSceneManager.has_method("get") and CogitoSceneManager.get("_current_player_node"):
		return CogitoSceneManager._current_player_node
	
	return null


## Emit inventory updated event through both local signal and Event Bus
func _emit_inventory_updated() -> void:
	inventory_updated.emit(self)
	
	# Try to ensure owner_id is set
	if owner_id == -1 and owner and owner is CogitoPlayer:
		var player = owner as CogitoPlayer
		if player.has_method("get") and player.get("player_id") != null and player.player_id != -1:
			owner_id = player.player_id
			# Register in InventoryManager if not already registered
			if InventoryManager and not InventoryManager.has_inventory(owner_id):
				InventoryManager.register_inventory(owner_id, self)
	
	# Emit through Event Bus if owner_id is set
	if owner_id != -1 and NetworkEventBus:
		NetworkEventBus.inventory_changed.emit(owner_id, self)


## Returns whether the given item fits in inventory
func can_pick_up_slot_data(slot_data: InventorySlotPD) -> bool:
	for index in inventory_slots.size():
		if inventory_slots[index] and inventory_slots[index].can_fully_merge_with(slot_data):
			return true
	for index in inventory_slots.size():
		if not inventory_slots[index] and is_enough_space(slot_data, index, true):
			return true
	return false
