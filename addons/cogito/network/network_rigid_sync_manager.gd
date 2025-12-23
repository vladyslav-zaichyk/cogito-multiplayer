extends Node
var enable_logging: bool = true
var registered_bodies: Dictionary = {}
var auto_enable_sync: bool = true
var sync_group_name: String = ""
var no_sync_group_name: String = ""
var auto_add_helper_script: bool = true
var _rigid_body_bubbles: Dictionary = {}
var _ownership_update_timer: float = 0.0
var _ownership_update_interval: float = 0.1

const COMPONENT_NAME = "NetworkRigidSync"
const COMPONENT_SCRIPT = preload("res://addons/cogito/network/network_rigid_sync.gd")
const BUBBLE_NAME = "NetworkRigidBubble"
const BUBBLE_SCRIPT = preload("res://addons/cogito/network/network_rigid_bubble.gd")
const HELPER_SCRIPT = preload("res://addons/cogito/network/rigid_body_sync_helper.gd")
const NETWORK_ID_SCRIPT = preload("res://addons/cogito/network/network_rigid_body_id.gd")
const NETWORK_ID_NAME = "NetworkRigidBodyID"


func _ready() -> void:
	if get_tree():
		get_tree().node_added.connect(_on_node_added)
		get_tree().node_removed.connect(_on_node_removed)
	
	if NetworkEventBus:
		NetworkEventBus.scene_changed.connect(_on_scene_changed)
	
	await get_tree().process_frame
	_find_and_inject_rigid_bodies()
	
	if auto_enable_sync and NetworkManager and NetworkManager.is_multiplayer():
		await get_tree().create_timer(1.5).timeout
		_enable_sync_for_all_registered()


func _on_node_added(node: Node) -> void:
	if node is RigidBody3D:
		_inject_component_if_needed_async(node)


func _inject_component_if_needed_async(node: Node) -> void:
	await get_tree().process_frame
	await _inject_component_if_needed(node)


func _on_node_removed(node: Node) -> void:
	if node is RigidBody3D:
		var component = node.get_node_or_null(COMPONENT_NAME)
		if component and component.has_method("get_network_id"):
			var network_id = component.get_network_id()
			unregister_rigid_body(network_id)


func _on_scene_changed(scene_path: String, scene_name: String) -> void:
	registered_bodies.clear()
	await get_tree().process_frame
	_find_and_inject_rigid_bodies()


func _find_and_inject_rigid_bodies() -> void:
	var scene = get_tree().current_scene
	if not scene:
		return
	var rigid_bodies = _find_rigid_bodies_recursive(scene)
	for body in rigid_bodies:
		await _inject_component_if_needed(body)


func _find_rigid_bodies_recursive(node: Node) -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	if node is RigidBody3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_rigid_bodies_recursive(child))
	return result


func _inject_component_if_needed(rigid_body: RigidBody3D) -> void:
	if not rigid_body or not is_instance_valid(rigid_body):
		return
	if rigid_body.get_node_or_null(COMPONENT_NAME):
		return
	if not _should_sync_object(rigid_body):
		return
	
	if not rigid_body.get_node_or_null(NETWORK_ID_NAME):
		var network_id_component = NETWORK_ID_SCRIPT.new()
		network_id_component.name = NETWORK_ID_NAME
		rigid_body.add_child(network_id_component)
		await get_tree().process_frame
	
	var component = COMPONENT_SCRIPT.new()
	component.name = COMPONENT_NAME
	rigid_body.add_child(component)
	
	if not rigid_body.get_node_or_null(BUBBLE_NAME):
		var bubble: Area3D = BUBBLE_SCRIPT.new()
		bubble.name = BUBBLE_NAME
		rigid_body.add_child(bubble)
	
	if auto_add_helper_script and not rigid_body.get_script():
		rigid_body.set_script(HELPER_SCRIPT)


func _should_sync_object(rigid_body: RigidBody3D) -> bool:
	return true


func register_rigid_body(component: Node) -> void:
	if not component or not component.has_method("get_network_id"):
		push_error("NetworkRigidSyncManager: Invalid component passed to register_rigid_body")
		return
	var network_id = component.get_network_id()
	if network_id == 0:
		push_error("NetworkRigidSyncManager: Component has invalid network_id (0)")
		return
	registered_bodies[network_id] = component
	if auto_enable_sync and NetworkManager and NetworkManager.is_multiplayer():
		call_deferred("_enable_sync_for_component", component, network_id)


func unregister_rigid_body(network_id: int) -> void:
	if registered_bodies.has(network_id):
		registered_bodies.erase(network_id)


func get_rigid_body(network_id: int) -> Node:
	return registered_bodies.get(network_id, null)


func get_registered_count() -> int:
	return registered_bodies.size()


func enable_sync_for_group(group_name: String) -> void:
	sync_group_name = group_name
	for network_id in registered_bodies:
		var component = registered_bodies[network_id]
		if component and component.has_method("get_parent_rigid_body"):
			var rigid_body = component.get_parent_rigid_body()
			if rigid_body and rigid_body.is_in_group(group_name):
				if component.has_method("set_sync_enabled"):
					component.set_sync_enabled(true)


func enable_sync_for_network_id(network_id: int) -> void:
	var component = get_rigid_body(network_id)
	if component and component.has_method("set_sync_enabled"):
		component.set_sync_enabled(true)


func _enable_sync_for_all_registered() -> void:
	for network_id in registered_bodies:
		var component = registered_bodies[network_id]
		if component and component.has_method("set_sync_enabled"):
			component.set_sync_enabled(true)


func _on_rigid_body_entered_bubble(network_id: int, player_peer_id: int) -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	if not _rigid_body_bubbles.has(network_id):
		_rigid_body_bubbles[network_id] = []
	
	var arr: Array = _rigid_body_bubbles[network_id]
	if not arr.has(player_peer_id):
		arr.append(player_peer_id)
		


func _on_rigid_body_exited_bubble(network_id: int, player_peer_id: int) -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	if not _rigid_body_bubbles.has(network_id):
		return
	
	var arr: Array = _rigid_body_bubbles[network_id]
	var idx := arr.find(player_peer_id)
	if idx != -1:
		arr.remove_at(idx)
		
		if arr.is_empty():
			_rigid_body_bubbles.erase(network_id)


func _process(delta: float) -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	_ownership_update_timer += delta
	if _ownership_update_timer < _ownership_update_interval:
		return
	_ownership_update_timer = 0.0
	
	for network_id in registered_bodies.keys():
		var component = get_rigid_body(network_id)
		if not component or not component.has_method("get_parent_rigid_body"):
			continue
		
		var rb: RigidBody3D = component.get_parent_rigid_body()
		if not rb or not is_instance_valid(rb):
			continue
		
		var bubble_peers: Array = _rigid_body_bubbles.get(network_id, [])
		var desired_owner := _choose_owner_for_rigid(network_id, rb, bubble_peers)
		if desired_owner == -1:
			continue
		
		var current_owner: int = 1
		if "owner_peer_id" in component:
			current_owner = component.owner_peer_id
		
		if desired_owner != current_owner and NetworkManager:
			NetworkManager.grant_rigid_body_ownership.rpc(network_id, desired_owner)


func _choose_owner_for_rigid(network_id: int, rb: RigidBody3D, bubble_peers: Array) -> int:
	if bubble_peers.is_empty():
		return 1  # Host
	
	if bubble_peers.size() == 1:
		return bubble_peers[0] as int
	
	if not PlayerManager:
		return 1
	
	var rb_pos: Vector3 = rb.global_position
	var closest_peer_id := 1
	var closest_dist := INF
	
	for peer_id in bubble_peers:
		var player_node := PlayerManager.get_player_by_peer_id(peer_id)
		if not player_node or not is_instance_valid(player_node):
			continue
		
		if not (player_node is Node3D):
			continue
		
		var dist_sq := rb_pos.distance_squared_to((player_node as Node3D).global_position)
		if dist_sq < closest_dist:
			closest_dist = dist_sq
			closest_peer_id = peer_id as int
	
	return closest_peer_id



func _enable_sync_for_component(component: Node, network_id: int) -> void:
	await get_tree().create_timer(0.6).timeout
	if component and is_instance_valid(component) and component.has_method("set_sync_enabled"):
		component.set_sync_enabled(true)


func _receive_rigid_state(state_data: Array, sender_peer_id: int) -> void:
	if state_data.is_empty() or state_data.size() < 5:
		return
	
	var network_id: int = state_data[0]
	if network_id == 0:
		return
	
	var component = get_rigid_body(network_id)
	var local_peer_id: int = -1
	if NetworkManager and NetworkManager.is_multiplayer():
		local_peer_id = NetworkManager.get_local_peer_id()
	
	if not component or not component.has_method("_receive_state_update"):
		return
	
	if NetworkManager and NetworkManager.is_multiplayer():
		if sender_peer_id == local_peer_id:
			return
		
		if "owner_peer_id" in component:
			var component_owner = component.owner_peer_id
			var is_local_owner_check = component.is_local_owner() if component.has_method("is_local_owner") else (component_owner == local_peer_id)
			if is_local_owner_check:
				return
	
	component._receive_state_update(state_data)


func _handle_ownership_request(network_id: int, requesting_peer_id: int) -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	var component = get_rigid_body(network_id)
	if not component or not component.has_method("_set_ownership"):
		return
	
	component._set_ownership(requesting_peer_id)
	
	if NetworkManager:
		NetworkManager.grant_rigid_body_ownership.rpc(network_id, requesting_peer_id)


func _handle_ownership_grant(network_id: int, owner_peer_id: int) -> void:
	var component = get_rigid_body(network_id)
	if not component or not component.has_method("_set_ownership"):
		return
	
	component._set_ownership(owner_peer_id)


func _handle_ownership_return(network_id: int) -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	
	var component = get_rigid_body(network_id)
	if not component or not component.has_method("_set_ownership"):
		return
	
	component._set_ownership(1)
	
	if NetworkManager:
		NetworkManager.grant_rigid_body_ownership.rpc(network_id, 1)


func set_logging_enabled(enabled: bool) -> void:
	enable_logging = enabled
	for network_id in registered_bodies:
		var component = registered_bodies[network_id]
		if component and component.has("enable_logging"):
			component.enable_logging = enabled
