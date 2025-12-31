extends Area3D
## Network Rigid Body Bubble
## Локальний (host-only) компонент, який відслідковує, які гравці знаходяться поруч із RigidBody3D.
## Він не займається вибором owner самостійно, а лише повідомляє NetworkRigidSyncManager.
##
## Очікування:
## - Parent цього вузла — це RigidBody3D, який має дочірній NetworkRigidSync.
## - На клієнтах цей компонент фактично вимкнений (усі події ігноруються).

var parent_rigid_body: RigidBody3D = null
var network_sync: Node = null  ## NetworkRigidSync

@export var bubble_radius: float = 1.5

## Collision mask для детекції гравців
## За замовчуванням детектуємо layer 1 (CharacterBody3D зазвичай там)
## Якщо гравці на іншому layer, змініть це значення
## Можна встановити кілька layers: 1 = layer 1, 3 = layers 1+2, 7 = layers 1+2+3, тощо
@export var player_collision_mask: int = 1


func _ready() -> void:
	# Працюємо лише на хості. На клієнтах цей компонент пасивний.
	if not NetworkManager or not NetworkManager.is_host():
		monitoring = false
		set_deferred("monitoring", false)
		set_process(false)
		return
	
	parent_rigid_body = get_parent() as RigidBody3D
	if not parent_rigid_body:
		push_error("NetworkRigidBubble: Parent must be a RigidBody3D")
		return
	
	# Знаходимо NetworkRigidSync
	network_sync = parent_rigid_body.get_node_or_null("NetworkRigidSync")
	if not network_sync:
		push_error("NetworkRigidBubble: Parent RigidBody3D must have NetworkRigidSync child")
		return
	
	# Створюємо CollisionShape3D якщо його немає
	var collision_shape = get_node_or_null("CollisionShape3D")
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		add_child(collision_shape)
		
		# Створюємо SphereShape3D для бульбашки
		var sphere_shape = SphereShape3D.new()
		sphere_shape.radius = bubble_radius
		collision_shape.shape = sphere_shape
		
		CogitoGlobals.debug_log(
			false,
			"NetworkRigidBubble",
			"Created CollisionShape3D for bubble on %s (radius=%.1fm)" % [parent_rigid_body.name, bubble_radius]
		)
	else:
		# Оновлюємо радіус якщо він змінився
		if collision_shape.shape is SphereShape3D:
			var sphere_shape = collision_shape.shape as SphereShape3D
			if abs(sphere_shape.radius - bubble_radius) > 0.01:
				sphere_shape.radius = bubble_radius
				CogitoGlobals.debug_log(
					false,
					"NetworkRigidBubble",
					"Updated bubble radius to %.1fm for %s" % [bubble_radius, parent_rigid_body.name]
				)
	
	# Встановлюємо collision layers/mask для детекції гравців
	collision_layer = 0  # Бульбашка не колайдиться сама
	collision_mask = player_collision_mask  # Детектуємо гравців на вказаних layers
	
	# Вмикаємо моніторинг тіл
	monitoring = true
	monitorable = false  # Бульбашка не повинна бути детектована іншими об'єктами
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	if not NetworkRigidSyncManager:
		return
	if not network_sync or not network_sync.has_method("get_network_id"):
		return
	
	# Фільтруємо тільки CharacterBody3D (гравці)
	# Ігноруємо StaticBody3D, AnimatableBody3D, RigidBody3D та інші
	if not body is CharacterBody3D:
		return
	
	var network_id = network_sync.get_network_id()
	if network_id == 0:
		return
	
	var peer_id := _get_peer_id_from_body(body)
	if peer_id <= 0:
		# Якщо peer_id ще не встановлений, спробуємо відкласти перевірку
		# Можливо, peer_id встановлюється пізніше після реєстрації гравця
		_try_again_later(body, network_id)
		return
	
	CogitoGlobals.debug_log(
		false,  # Використовуємо enable_logging з NetworkRigidSyncManager
		"NetworkRigidBubble",
		"Player peer=%d entered bubble for network_id=%d (rigid=%s)" % [
			peer_id, network_id, parent_rigid_body.name
		]
	)
	
	NetworkRigidSyncManager._on_rigid_body_entered_bubble(network_id, peer_id)


func _on_body_exited(body: Node) -> void:
	if not NetworkManager or not NetworkManager.is_host():
		return
	if not NetworkRigidSyncManager:
		return
	if not network_sync or not network_sync.has_method("get_network_id"):
		return
	
	# Фільтруємо тільки CharacterBody3D (гравці)
	# Ігноруємо StaticBody3D, AnimatableBody3D, RigidBody3D та інші
	if not body is CharacterBody3D:
		return
	
	var network_id = network_sync.get_network_id()
	if network_id == 0:
		return
	
	var peer_id := _get_peer_id_from_body(body)
	if peer_id <= 0:
		# Тихо ігноруємо, якщо не можемо визначити peer_id
		return
	
	CogitoGlobals.debug_log(
		false,  # Використовуємо enable_logging з NetworkRigidSyncManager
		"NetworkRigidBubble",
		"Player peer=%d exited bubble for network_id=%d (rigid=%s)" % [
			peer_id, network_id, parent_rigid_body.name
		]
	)
	
	NetworkRigidSyncManager._on_rigid_body_exited_bubble(network_id, peer_id)


## Спроба дістати peer_id гравця з тіла, яке зайшло в бульбашку
## Робимо це максимально обережно, не ламаючи існуючу логіку PlayerManager.
func _get_peer_id_from_body(body: Node) -> int:
	if not PlayerManager:
		return -1
	
	# 1) Пряма спроба: body — це гравець
	var player_id := PlayerManager.get_player_id(body)
	if player_id != -1:
		var peer_id = PlayerManager.get_player_peer_id(player_id)
		# Якщо peer_id встановлений, повертаємо його
		if peer_id > 0:
			return peer_id
		# Якщо peer_id не встановлений (-1), спробуємо fallback через meta або властивість
		# PlayerSpawner встановлює peer_id через set_meta або як властивість
		if body.has_method("get_meta") and body.has_meta("peer_id"):
			var meta_peer_id = body.get_meta("peer_id")
			if meta_peer_id is int and meta_peer_id > 0:
				return meta_peer_id
		# Спробуємо через властивість peer_id
		if body.has_method("get") and body.get("peer_id") != null:
			var prop_peer_id = body.peer_id
			if prop_peer_id is int and prop_peer_id > 0:
				return prop_peer_id
	
	# 2) Спроба через parent (частий кейс, коли колайдер — child гравця)
	if body.get_parent():
		var parent = body.get_parent()
		player_id = PlayerManager.get_player_id(parent)
		if player_id != -1:
			var peer_id = PlayerManager.get_player_peer_id(player_id)
			if peer_id > 0:
				return peer_id
	
	return -1


## Спробувати отримати peer_id пізніше, якщо він ще не встановлений
func _try_again_later(body: Node, network_id: int) -> void:
	# Почекаємо кілька кадрів, щоб peer_id встиг встановитися
	await get_tree().create_timer(0.1).timeout
	
	if not is_instance_valid(body):
		return
	
	var peer_id := _get_peer_id_from_body(body)
	if peer_id > 0:
		NetworkRigidSyncManager._on_rigid_body_entered_bubble(network_id, peer_id)


