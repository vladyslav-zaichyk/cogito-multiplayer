extends InteractionComponent
class_name PickupComponent

## Preload command class for static typing
const PickupItemCommand = preload("res://addons/cogito/network/commands/inventory/pickup_item_command.gd")

@export var slot_data: InventorySlotPD
@export var display_item_name: bool = false

var player_interaction_component


func _enter_tree() -> void:
	if display_item_name:
		var owner_object: CogitoObject = get_parent()
		owner_object.display_name = slot_data.inventory_item.name
	
	# Add NetworkPickupID component for multiplayer synchronization (deferred to avoid blocking)
	if NetworkManager and NetworkManager.is_multiplayer():
		call_deferred("_add_network_pickup_id")


func _add_network_pickup_id() -> void:
	var parent_obj = get_parent()
	if not parent_obj:
		return
	
	# Check if NetworkPickupID already exists
	var has_network_id = false
	for child in parent_obj.get_children():
		if child.has_method("get_network_id"):
			has_network_id = true
			break
	
	if not has_network_id:
		var network_id_component = preload("res://addons/cogito/network/network_pickup_id.gd").new()
		network_id_component.name = "NetworkPickupID"
		parent_obj.add_child(network_id_component)


func interact(_player_interaction_component: PlayerInteractionComponent):
	if !is_disabled:
		pick_up(_player_interaction_component)


func pick_up(_player_interaction_component: PlayerInteractionComponent):
	### Currency Item handling
	if slot_data.inventory_item is CurrencyItemPD and slot_data.inventory_item.add_on_pickup:
		if slot_data.inventory_item.use(_player_interaction_component.get_parent()):
			#_player_interaction_component.send_hint(slot_data.inventory_item.hint_icon_on_use, slot_data.inventory_item.hint_text_on_use)
			Audio.play_sound(slot_data.inventory_item.sound_pickup)
			was_interacted_with.emit(interaction_text, input_map_action)
			self.get_parent().queue_free()
			return
		else:
			_player_interaction_component.send_hint(
				slot_data.inventory_item.icon,
				tr(slot_data.inventory_item.name) + " " + tr("HINT_cant_pick_up")
			)
			return

	# Use Command/Event Sourcing architecture
	# CommandBus is an autoload singleton (registered in cogito_plugin.gd)
	# Accessible directly as global variable at runtime
	# Get player ID
	var player_id = -1
	if PlayerManager:
		player_id = PlayerManager.get_player_id(_player_interaction_component.get_parent())
	
	if player_id == -1:
		# Fallback to old system if player not found
		if not _player_interaction_component.get_parent().inventory_data.pick_up_slot_data(slot_data):
			return
		_handle_pickup_success(_player_interaction_component)
		return
	
	# Get item position and network ID
	var parent_obj = get_parent()
	var item_position = Vector3.ZERO
	var network_id = -1
	var scene_path = ""
	
	if parent_obj is Node3D:
		item_position = (parent_obj as Node3D).global_position
	
	# Try to get network_id from NetworkPickupID component
	for child in parent_obj.get_children():
		if child.has_method("get_network_id"):
			network_id = child.get_network_id()
			break
	
	# Get scene path if available
	if parent_obj.is_inside_tree():
		scene_path = str(parent_obj.get_path())
	
	# Create and execute command (using class_name for static typing)
	var command = PickupItemCommand.new(player_id, slot_data, item_position, network_id, scene_path)
	var result = CommandBus.execute_command(command)
	
	if result.success:
		# Command executed successfully, handle UI updates
		_handle_pickup_success(_player_interaction_component)
	else:
		# Command failed, show error
		_player_interaction_component.send_hint(
			null,
			result.error_message if result.error_message else "Failed to pick up item"
		)


## Handle successful pickup (UI updates, etc.)
func _handle_pickup_success(_player_interaction_component: PlayerInteractionComponent) -> void:

	# Update wieldable UI if we have picked up ammo for current wieldable
	# TODO: Possibly replace with a better solution, maybe by signaling the change
	# to the UI instead of having the PlayerInteractionComponent doing it.
	if _player_interaction_component.is_wielding:
		var is_ammo: bool = "reload_amount" in slot_data.inventory_item
		var is_current_ammo: bool = (
			_player_interaction_component.equipped_wieldable_item.ammo_item_name
			== slot_data.inventory_item.name
		)
		if is_ammo and is_current_ammo:
			var equipped_wieldable = _player_interaction_component.equipped_wieldable_item
			if equipped_wieldable.charge_current < equipped_wieldable.charge_max:
				_player_interaction_component.equipped_wieldable_item.update_wieldable_data(
					_player_interaction_component
				)

	_player_interaction_component.send_hint(
		slot_data.inventory_item.icon,
		tr(slot_data.inventory_item.name) + " " + tr("INVENTORY_add_item")
	)
	was_interacted_with.emit(interaction_text, input_map_action)
	Audio.play_sound(slot_data.inventory_item.sound_pickup)
	self.get_parent().queue_free()
