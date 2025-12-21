# ПЛАН РЕАЛІЗАЦІЇ СИНХРОНІЗАЦІЇ ФІЗИКИ (RigidBody3D)

## ОГЛЯД

Цей документ описує поетапну реалізацію синхронізації фізичних об'єктів (RigidBody3D) у мультиплеєрному режимі з мінімальною інвазивністю та максимальною стабільністю.

**Архітектурні принципи:**
- Owner-authority модель: один peer симулює фізику, інші отримують snapshot-и
- Динамічна інжекція компонентів (без змін у сценах)
- Синхронізація лише активних об'єктів
- TTL-based ownership з автоматичним скиданням
- Плавна інтерполяція для non-owner peer'ів

---

## PHASE 0: OBSERVABILITY (Інжекція та збір даних)

### Мета фази
Створити систему автоматичної інжекції компонентів синхронізації до всіх RigidBody3D у сцені та збір фізичного стану БЕЗ застосування мережевих апдейтів. Це дозволить перевірити, що система правильно знаходить об'єкти та збирає дані.

### Архітектурні зміни

#### 1. Створення `NetworkRigidSync` компонента
**Файл:** `addons/cogito/network/network_rigid_sync.gd`

**Відповідальність:**
- Зберігає посилання на батьківський RigidBody3D
- Генерує стабільний network_id (String, на основі scene_path + node_path)
- Збирає фізичний стан (position, rotation, velocities, sleeping)
- Логує зміни стану (для debugging)
- НЕ застосовує мережеві апдейти (тільки збір)

**Ключові властивості:**
```gdscript
var parent_rigid_body: RigidBody3D
var network_id: String = ""
var last_state: Dictionary = {}
var is_active: bool = true  # Завжди true в Phase 0
var enable_logging: bool = false
```

**Godot API:**
- `RigidBody3D.position`, `global_position`
- `RigidBody3D.quaternion`, `global_transform.basis.get_rotation_quaternion()`
- `RigidBody3D.linear_velocity`
- `RigidBody3D.angular_velocity`
- `RigidBody3D.sleeping` (Godot 4)

#### 2. Створення `NetworkRigidSyncManager` (autoload)
**Файл:** `addons/cogito/network/network_rigid_sync_manager.gd`

**Відповідальність:**
- Автоматично знаходить всі RigidBody3D у сцені
- Динамічно додає `NetworkRigidSync` компонент до кожного RigidBody3D
- Реєструє об'єкти в централізованому реєстрі
- Слухає додавання нових нод (для динамічно заспавнених об'єктів)
- Фільтрує об'єкти за групами/metadata (опціонально)

**Godot API:**
- `SceneTree.node_added` signal (для нових нод)
- `get_tree().get_nodes_in_group()` (для пошуку за групами)
- `Node.add_child()` (для інжекції компонентів)
- `Node.is_in_group()` (для фільтрації)

**Фільтрація об'єктів:**
- За замовчуванням: синхронізувати всі RigidBody3D
- Опціонально: група `"network_sync"` (якщо об'єкт в групі — синхронізувати)
- Опціонально: група `"network_no_sync"` (якщо об'єкт в групі — НЕ синхронізувати)
- Опціонально: metadata `"network_sync_enabled"` (boolean)

**Реєстр об'єктів:**
```gdscript
var registered_bodies: Dictionary = {}  # network_id -> NetworkRigidSync
```

#### 3. Формат збираних даних (State Snapshot)
```gdscript
{
    "network_id": String,
    "position": Vector3,
    "rotation_quat": Quaternion,  # Використовуємо Quaternion для точності
    "linear_velocity": Vector3,
    "angular_velocity": Vector3,
    "sleeping": bool,
    "timestamp": float,  # Time.get_ticks_msec() / 1000.0
    "tick": int  # Локальний лічильник (опціонально)
}
```

### Реєстрація autoload
**Файл:** `addons/cogito/cogito_plugin.gd` (або `project.godot`)

Додати `NetworkRigidSyncManager` до autoload з ім'ям `NetworkRigidSyncManager`.

### Acceptance Criteria

1. ✅ При завантаженні сцени всі RigidBody3D автоматично отримують `NetworkRigidSync` компонент
2. ✅ У консолі виводяться логи з network_id кожного знайденого об'єкта
3. ✅ `NetworkRigidSyncManager.registered_bodies` містить всі об'єкти
4. ✅ При додаванні нового RigidBody3D під час гри він автоматично отримує компонент
5. ✅ Компонент збирає фізичний стан у `_physics_process` (але не відправляє)
6. ✅ Логи показують зміни стану (position, velocity) при руху об'єктів

### Тестування

**Тест 1: Статичні об'єкти**
- Завантажити сцену з RigidBody3D
- Перевірити, що всі отримали компонент
- Перевірити логи з network_id

**Тест 2: Динамічне додавання**
- Під час гри створити новий RigidBody3D через код
- Перевірити, що він отримав компонент
- Перевірити, що він з'явився в реєстрі

**Тест 3: Збір стану**
- Рухати об'єкт (штовхати, кидати)
- Перевірити логи зі змінами стану
- Перевірити, що `last_state` оновлюється

### Потенційні проблеми

**Проблема:** Компонент додається до об'єктів, які не повинні синхронізуватися
- **Рішення:** Додати фільтрацію за групами/metadata на початку Phase 0

**Проблема:** Дублювання компонентів при перезавантаженні сцени
- **Рішення:** Перевіряти наявність компонента перед додаванням

**Проблема:** network_id нестабільний для динамічно заспавнених об'єктів
- **Рішення:** Використовувати унікальний ID генератор (як у NetworkPickupID) для динамічних об'єктів

---

## PHASE 1: ОБМЕЖЕНИЙ SYNC (Тестова синхронізація)

### Мета фази
Реалізувати базову синхронізацію для 1-2 тестових об'єктів через окрему групу. Це дозволить перевірити мережевий протокол та застосування стану без впливу на всі об'єкти.

### Архітектурні зміни

#### 1. Розширення `NetworkRigidSync`
**Додати:**
- Властивість `sync_enabled: bool = false` (за замовчуванням вимкнено)
- Метод `_send_state_update()` — відправляє стан через NetworkManager RPC
- Метод `_receive_state_update(state: Dictionary)` — застосовує отриманий стан
- Властивість `is_owner: bool = false` (поки не використовується, для Phase 2)

**Логіка відправки:**
- Тільки якщо `sync_enabled == true`
- Тільки якщо стан змінився (порівняння з `last_sent_state`)
- Частота: кожні N фреймів (наприклад, кожні 3 фрейми = ~20 Hz при 60 FPS)

**Логіка застосування:**
- Застосовувати стан тільки якщо `!is_owner` (поки завжди false)
- Застосовувати в `_physics_process`
- Використовувати `lerp` для плавності (поки простий lerp, без складних алгоритмів)

#### 2. Розширення `NetworkRigidSyncManager`
**Додати:**
- Метод `enable_sync_for_group(group_name: String)` — увімкнути sync для об'єктів у групі
- Метод `enable_sync_for_network_id(network_id: String)` — увімкнути sync для конкретного об'єкта

#### 3. Додавання RPC до `NetworkManager`
**Файл:** `addons/cogito/network/network_manager.gd`

**Додати RPC:**
```gdscript
@rpc("any_peer", "call_local", "unreliable")
func sync_rigid_body_state(state_data: Dictionary) -> void:
    # Route to NetworkRigidSyncManager
    if NetworkRigidSyncManager:
        NetworkRigidSyncManager._receive_rigid_state(state_data)
```

**Примітка:** Використовуємо `unreliable` для швидкості (фізика може втратити пакети, але це OK для початку).

#### 4. Розширення `NetworkRigidSyncManager`
**Додати:**
- Метод `_receive_rigid_state(state_data: Dictionary)` — отримує RPC та передає до відповідного `NetworkRigidSync`

### Формат мережевих повідомлень

**Відправка (state_data):**
```gdscript
{
    "network_id": String,
    "position": {"x": float, "y": float, "z": float},
    "rotation_quat": {"x": float, "y": float, "z": float, "w": float},
    "linear_velocity": {"x": float, "y": float, "z": float},
    "angular_velocity": {"x": float, "y": float, "z": float},
    "sleeping": bool,
    "timestamp": float
}
```

**Примітка:** Vector3 та Quaternion серіалізуються як Dictionary для RPC.

### Acceptance Criteria

1. ✅ Об'єкт з групою `"test_physics_sync"` автоматично увімкнений для sync
2. ✅ Owner відправляє стан кожні N фреймів
3. ✅ Non-owner отримує стан та застосовує його
4. ✅ Об'єкт на non-owner peer'і рухається синхронно з owner
5. ✅ Логи показують відправку/отримання стану
6. ✅ Немає помилок у консолі

### Тестування

**Тест 1: Базовий sync**
- Додати об'єкт до групи `"test_physics_sync"`
- Увімкнути sync через `NetworkRigidSyncManager.enable_sync_for_group("test_physics_sync")`
- Owner штовхає об'єкт
- Перевірити, що non-owner бачить рух

**Тест 2: Два об'єкти**
- Додати два об'єкти до групи
- Перевірити, що обидва синхронізуються
- Перевірити, що немає конфліктів

**Тест 3: Відключення sync**
- Увімкнути sync, потім вимкнути
- Перевірити, що відправка зупинилася

### Потенційні проблеми

**Проблема:** Об'єкт "стрибає" при застосуванні стану
- **Рішення:** Використовувати `lerp` з коефіцієнтом 0.1-0.3, застосовувати в `_physics_process`

**Проблема:** Занадто багато пакетів
- **Рішення:** Додати rate limiting (відправляти тільки кожні N фреймів)

**Проблема:** Об'єкт не рухається на non-owner
- **Рішення:** Перевірити, що `freeze` не встановлено, перевірити застосування стану

---

## PHASE 2: OWNERSHIP + FREEZE/UNFREEZE

### Мета фази
Реалізувати owner-authority модель: owner симулює фізику, non-owner заморожують об'єкт та застосовують отриманий стан. Додати механізм запиту ownership при взаємодії.

### Архітектурні зміни

#### 1. Розширення `NetworkRigidSync`
**Додати властивості:**
```gdscript
var owner_peer_id: int = -1  # Peer ID, який володіє об'єктом
var is_owner: bool = false  # Чи є локальний peer owner'ом
var ownership_ttl: float = 5.0  # Час життя ownership (секунди)
var ownership_expiry_time: float = 0.0  # Коли ownership закінчується
```

**Додати методи:**
- `request_ownership()` — запитує ownership через RPC
- `_set_owner(peer_id: int)` — встановлює owner (викликається через RPC)
- `_update_ownership_status()` — оновлює `is_owner` на основі `owner_peer_id`
- `_apply_remote_state(state: Dictionary)` — застосовує стан для non-owner
- `_handle_freeze_unfreeze()` — заморожує/розморожує об'єкт залежно від ownership

**Логіка ownership:**
- Якщо `is_owner == true`: симулює фізику, відправляє стан
- Якщо `is_owner == false`: заморожує об'єкт (`freeze = true`), застосовує отриманий стан

**Godot API:**
- `RigidBody3D.freeze = true/false` — заморожує фізичну симуляцію
- `RigidBody3D.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC` — режим заморозки (опціонально)

#### 2. Додавання RPC для ownership
**Файл:** `addons/cogito/network/network_manager.gd`

**Додати RPC:**
```gdscript
@rpc("any_peer", "call_local", "reliable")
func request_rigid_body_ownership(network_id: String, requester_peer_id: int) -> void:
    # Route to NetworkRigidSyncManager
    if NetworkRigidSyncManager:
        NetworkRigidSyncManager._handle_ownership_request(network_id, requester_peer_id)

@rpc("any_peer", "call_local", "reliable")
func set_rigid_body_owner(network_id: String, owner_peer_id: int) -> void:
    # Route to NetworkRigidSyncManager
    if NetworkRigidSyncManager:
        NetworkRigidSyncManager._set_rigid_body_owner(network_id, owner_peer_id)
```

#### 3. Розширення `NetworkRigidSyncManager`
**Додати методи:**
- `_handle_ownership_request(network_id: String, requester_peer_id: int)` — обробляє запит ownership
- `_set_rigid_body_owner(network_id: String, owner_peer_id: int)` — встановлює owner для об'єкта
- `_resolve_ownership_conflict(network_id: String, requester_peer_id: int, current_owner: int)` — вирішує конфлікти

**Логіка ownership:**
- Якщо об'єкт не має owner — надати ownership запитувачу
- Якщо об'єкт має owner, але ownership закінчився (TTL) — передати новому запитувачу
- Якщо об'єкт має активний owner — відхилити запит (або передати, якщо запитувач має пріоритет)

**Примітка:** На початку Phase 2 використовуємо просту логіку: "останній запитувач отримує ownership".

#### 4. Інтеграція з системою взаємодій
**Мета:** Автоматично запитувати ownership при взаємодії з об'єктом.

**Варіант 1: Через події Cogito**
- Слухати `ItemDroppedEvent`, `CarryingStartedEvent`, `CarryingStoppedEvent`
- При взаємодії автоматично запитувати ownership

**Варіант 2: Через сигнали RigidBody3D**
- Слухати `body_entered`, `body_exited` (якщо є Area3D)
- При контакті з гравцем запитувати ownership

**Варіант 3: Через ручний виклик**
- Додати метод `NetworkRigidSync.request_ownership_on_interaction()`
- Викликати з `CogitoCarryableComponent.hold()`, `PickupComponent.pick_up()` тощо

**Рекомендація:** Почати з Варіанту 3 (найпростіший), потім додати Варіант 1 (найчистіший).

**Файли для змін:**
- `addons/cogito/Components/Interactions/carryable_component.gd` — додати виклик `request_ownership()` в `hold()`
- `addons/cogito/Components/Interactions/pickup_component.gd` — додати виклик при підборі
- `addons/cogito/network/commands/events/item_dropped_event.gd` — додати обробку події

#### 5. Застосування remote state
**Метод `_apply_remote_state()`:**
```gdscript
func _apply_remote_state(state: Dictionary) -> void:
    if is_owner:
        return  # Не застосовуємо remote state якщо ми owner
    
    var target_pos = Vector3(state.position.x, state.position.y, state.position.z)
    var target_rot = Quaternion(state.rotation_quat.x, state.rotation_quat.y, state.rotation_quat.z, state.rotation_quat.w)
    var target_lin_vel = Vector3(state.linear_velocity.x, state.linear_velocity.y, state.linear_velocity.z)
    var target_ang_vel = Vector3(state.angular_velocity.x, state.angular_velocity.y, state.angular_velocity.z)
    
    # Простий lerp для початку
    var lerp_factor = 0.2
    parent_rigid_body.global_position = parent_rigid_body.global_position.lerp(target_pos, lerp_factor)
    parent_rigid_body.quaternion = parent_rigid_body.quaternion.slerp(target_rot, lerp_factor)
    parent_rigid_body.linear_velocity = parent_rigid_body.linear_velocity.lerp(target_lin_vel, lerp_factor)
    parent_rigid_body.angular_velocity = parent_rigid_body.angular_velocity.lerp(target_ang_vel, lerp_factor)
```

**Примітка:** Використовуємо `slerp` для Quaternion (правильна інтерполяція ротації).

### Формат мережевих повідомлень

**Ownership request:**
```gdscript
{
    "network_id": String,
    "requester_peer_id": int
}
```

**Ownership response:**
```gdscript
{
    "network_id": String,
    "owner_peer_id": int,
    "granted": bool  # Чи надано ownership
}
```

### Acceptance Criteria

1. ✅ При взаємодії з об'єктом гравець автоматично запитує ownership
2. ✅ Owner симулює фізику, non-owner заморожені
3. ✅ Owner відправляє стан, non-owner застосовують його
4. ✅ При передачі ownership об'єкт коректно перемикається між freeze/unfreeze
5. ✅ Два peer'и не можуть одночасно бути owner'ами одного об'єкта
6. ✅ Ownership автоматично скидається через TTL (якщо немає взаємодії)

### Тестування

**Тест 1: Базовий ownership**
- Peer 1 взаємодіє з об'єктом → отримує ownership
- Peer 1 штовхає об'єкт → Peer 2 бачить рух
- Peer 2 не може штовхати (freeze)

**Тест 2: Передача ownership**
- Peer 1 має ownership
- Peer 2 взаємодіє з об'єктом → отримує ownership
- Peer 1 втрачає ownership (freeze)
- Peer 2 може штовхати

**Тест 3: TTL ownership**
- Peer 1 отримує ownership
- Чекати TTL секунд без взаємодії
- Перевірити, що ownership скинувся

**Тест 4: Конфлікт ownership**
- Peer 1 та Peer 2 одночасно запитують ownership
- Перевірити, що тільки один отримав

### Потенційні проблеми

**Проблема:** Об'єкт "телепортується" при зміні ownership
- **Рішення:** При передачі ownership відправити поточний стан від старого owner'а до нового

**Проблема:** Об'єкт не заморожується на non-owner
- **Рішення:** Перевірити, що `freeze = true` встановлюється в `_handle_freeze_unfreeze()`

**Проблема:** Ownership не передається
- **Рішення:** Перевірити RPC, перевірити логіку в `_handle_ownership_request()`

---

## PHASE 3: ACTIVE-ONLY ЛОГІКА (Sleeping detection + TTL)

### Мета фази
Додати логіку визначення активних об'єктів: синхронізувати тільки ті, які рухаються або з якими нещодавно взаємодіяли. Об'єкти, які заснули (sleeping) та не мають активного ownership, не синхронізуються.

### Архітектурні зміни

#### 1. Розширення `NetworkRigidSync`
**Додати властивості:**
```gdscript
var is_active: bool = true  # Чи є об'єкт активним для синхронізації
var last_interaction_time: float = 0.0  # Час останньої взаємодії
var interaction_ttl: float = 2.0  # Час, протягом якого об'єкт залишається активним після взаємодії
var last_velocity_magnitude: float = 0.0  # Для визначення руху
var velocity_threshold: float = 0.1  # Мінімальна швидкість для вважання активним
var consecutive_sleeping_frames: int = 0  # Лічильник кадрів у стані sleeping
var sleeping_frames_threshold: int = 60  # Кількість кадрів для вважання "справді sleeping"
```

**Додати методи:**
- `_update_active_status()` — оновлює `is_active` на основі sleeping, velocity, interaction time
- `_check_if_sleeping()` — перевіряє, чи об'єкт справді sleeping
- `_check_if_moving()` — перевіряє, чи об'єкт рухається (за швидкістю)
- `_mark_interaction()` — позначає взаємодію (викликається при ownership request)

**Логіка активності:**
```gdscript
func _update_active_status() -> void:
    var current_time = Time.get_ticks_msec() / 1000.0
    
    # Якщо маємо ownership — завжди активний
    if is_owner:
        is_active = true
        return
    
    # Якщо нещодавно була взаємодія — активний
    if current_time - last_interaction_time < interaction_ttl:
        is_active = true
        return
    
    # Якщо рухається — активний
    if _check_if_moving():
        is_active = true
        return
    
    # Якщо sleeping протягом достатньої кількості кадрів — неактивний
    if _check_if_sleeping():
        consecutive_sleeping_frames += 1
        if consecutive_sleeping_frames >= sleeping_frames_threshold:
            is_active = false
            return
    else:
        consecutive_sleeping_frames = 0
    
    # За замовчуванням активний (якщо не визначено інакше)
    is_active = true
```

**Логіка відправки:**
- Відправляти стан тільки якщо `is_active == true`
- Якщо об'єкт став неактивним — відправити останній стан з прапорцем `"final": true` (опціонально)

#### 2. Розширення `NetworkRigidSyncManager`
**Додати методи:**
- `_update_all_active_status()` — оновлює статус активності для всіх об'єктів (викликається в `_process`)
- `get_active_bodies_count()` — повертає кількість активних об'єктів (для debugging)

#### 3. Інтеграція з взаємодіями
**Оновити файли:**
- `addons/cogito/Components/Interactions/carryable_component.gd` — викликати `_mark_interaction()` при `hold()`
- `addons/cogito/network/commands/events/item_dropped_event.gd` — викликати `_mark_interaction()` при скиданні

**Додати метод до `NetworkRigidSync`:**
```gdscript
func mark_interaction() -> void:
    last_interaction_time = Time.get_ticks_msec() / 1000.0
    is_active = true
    consecutive_sleeping_frames = 0
```

### Формат мережевих повідомлень

**Додати до state_data:**
```gdscript
{
    ...
    "is_active": bool,  # Чи є об'єкт активним
    "sleeping": bool    # Вже було, але тепер використовується для логіки
}
```

### Acceptance Criteria

1. ✅ Об'єкт, який заснув (sleeping) та не має ownership, стає неактивним
2. ✅ Об'єкт, з яким нещодавно взаємодіяли, залишається активним
3. ✅ Об'єкт, який рухається, залишається активним
4. ✅ Неактивні об'єкти не відправляють стан (економія трафіку)
5. ✅ При новій взаємодії неактивний об'єкт стає активним
6. ✅ Owner завжди активний (навіть якщо sleeping)

### Тестування

**Тест 1: Sleeping detection**
- Створити об'єкт, який засинає
- Перевірити, що він стає неактивним через N кадрів
- Перевірити, що він перестав відправляти стан

**Тест 2: Interaction reactivation**
- Об'єкт став неактивним (sleeping)
- Взаємодіяти з ним
- Перевірити, що він став активним

**Тест 3: Movement detection**
- Об'єкт рухається (не sleeping, але має velocity)
- Перевірити, що він залишається активним

**Тест 4: Owner always active**
- Owner має ownership, об'єкт sleeping
- Перевірити, що owner продовжує відправляти стан

### Потенційні проблеми

**Проблема:** Об'єкт стає неактивним занадто швидко
- **Рішення:** Збільшити `sleeping_frames_threshold` або `interaction_ttl`

**Проблема:** Об'єкт не стає активним при взаємодії
- **Рішення:** Перевірити виклик `_mark_interaction()` з місць взаємодії

**Проблема:** Об'єкт "пропадає" на non-owner після стану неактивним
- **Рішення:** Не видаляти компонент, просто не відправляти стан; при реактивації відправити поточний стан

---

## PHASE 4: ОПТИМІЗАЦІЯ (Thresholds, Rate Limiting, Batching)

### Мета фази
Оптимізувати мережевий трафік: відправляти стан тільки при значних змінах, обмежити частоту відправки, об'єднати кілька об'єктів в один пакет.

### Архітектурні зміни

#### 1. Розширення `NetworkRigidSync`
**Додати властивості:**
```gdscript
var position_threshold: float = 0.01  # Мінімальна зміна позиції для відправки
var rotation_threshold: float = 0.01  # Мінімальна зміна ротації (в радіанах або як кут)
var velocity_threshold: float = 0.1  # Мінімальна зміна швидкості
var last_sent_state: Dictionary = {}  # Останній відправлений стан (для порівняння)
var send_interval_frames: int = 3  # Відправляти кожні N фреймів (при 60 FPS = 20 Hz)
var frames_since_last_send: int = 0  # Лічильник кадрів
```

**Додати методи:**
- `_has_state_changed_significantly(new_state: Dictionary) -> bool` — перевіряє, чи змінився стан значно
- `_should_send_update() -> bool` — перевіряє, чи потрібно відправляти (частота + зміни)
- `_calculate_state_delta(old_state: Dictionary, new_state: Dictionary) -> Dictionary` — обчислює дельту змін

**Логіка відправки:**
```gdscript
func _should_send_update() -> bool:
    frames_since_last_send += 1
    
    # Перевірити частоту
    if frames_since_last_send < send_interval_frames:
        return false
    
    # Перевірити зміни
    var current_state = _collect_state()
    if not _has_state_changed_significantly(current_state):
        return false
    
    frames_since_last_send = 0
    return true
```

**Порівняння стану:**
```gdscript
func _has_state_changed_significantly(new_state: Dictionary) -> bool:
    if last_sent_state.is_empty():
        return true  # Перший раз завжди відправляємо
    
    # Порівняти позицію
    var pos_delta = (Vector3(new_state.position.x, new_state.position.y, new_state.position.z) - 
                     Vector3(last_sent_state.position.x, last_sent_state.position.y, last_sent_state.position.z)).length()
    if pos_delta > position_threshold:
        return true
    
    # Порівняти ротацію (через кут між quaternions)
    var old_quat = Quaternion(last_sent_state.rotation_quat.x, last_sent_state.rotation_quat.y, 
                               last_sent_state.rotation_quat.z, last_sent_state.rotation_quat.w)
    var new_quat = Quaternion(new_state.rotation_quat.x, new_state.rotation_quat.y, 
                              new_state.rotation_quat.z, new_state.rotation_quat.w)
    var rot_angle = abs(old_quat.angle_to(new_quat))
    if rot_angle > rotation_threshold:
        return true
    
    # Порівняти швидкості
    var lin_vel_delta = (Vector3(new_state.linear_velocity.x, new_state.linear_velocity.y, new_state.linear_velocity.z) - 
                         Vector3(last_sent_state.linear_velocity.x, last_sent_state.linear_velocity.y, last_sent_state.linear_velocity.z)).length()
    if lin_vel_delta > velocity_threshold:
        return true
    
    # Порівняти sleeping
    if new_state.sleeping != last_sent_state.get("sleeping", false):
        return true
    
    return false
```

#### 2. Batching (об'єднання пакетів)
**Розширення `NetworkRigidSyncManager`:**
**Додати властивості:**
```gdscript
var pending_states: Array[Dictionary] = []  # Черга станів для відправки
var batch_send_interval: float = 0.05  # Відправляти батч кожні 50ms (20 Hz)
var max_batch_size: int = 10  # Максимальна кількість об'єктів в одному пакеті
var last_batch_send_time: float = 0.0
```

**Додати методи:**
- `_queue_state_for_send(state_data: Dictionary)` — додає стан до черги
- `_send_batched_states()` — відправляє батч через RPC
- `_process_batching()` — обробляє батчінг (викликається в `_process`)

**Логіка батчингу:**
```gdscript
func _process_batching() -> void:
    var current_time = Time.get_ticks_msec() / 1000.0
    
    # Відправити батч якщо:
    # 1. Досягнуто максимальний розмір
    # 2. Пройшов інтервал часу
    if pending_states.size() >= max_batch_size or \
       (pending_states.size() > 0 and current_time - last_batch_send_time >= batch_send_interval):
        _send_batched_states()
```

**Оновлення RPC:**
```gdscript
# В NetworkManager
@rpc("any_peer", "call_local", "unreliable")
func sync_rigid_bodies_batch(batch_data: Array[Dictionary]) -> void:
    # Route to NetworkRigidSyncManager
    if NetworkRigidSyncManager:
        NetworkRigidSyncManager._receive_rigid_batch(batch_data)
```

**Формат батч-пакету:**
```gdscript
[
    {
        "network_id": String,
        "position": {...},
        "rotation_quat": {...},
        ...
    },
    {
        "network_id": String,
        ...
    },
    ...
]
```

#### 3. Налаштування thresholds
**Додати export змінні до `NetworkRigidSync`:**
```gdscript
@export_group("Sync Settings")
@export var position_threshold: float = 0.01
@export var rotation_threshold: float = 0.01
@export var velocity_threshold: float = 0.1
@export var send_interval_frames: int = 3
```

**Додати глобальні налаштування до `NetworkRigidSyncManager`:**
```gdscript
@export_group("Global Sync Settings")
@export var default_position_threshold: float = 0.01
@export var default_rotation_threshold: float = 0.01
@export var default_velocity_threshold: float = 0.1
@export var default_send_interval_frames: int = 3
@export var batch_send_interval: float = 0.05
@export var max_batch_size: int = 10
```

### Acceptance Criteria

1. ✅ Стан відправляється тільки при значних змінах (пороги)
2. ✅ Частота відправки обмежена (rate limiting)
3. ✅ Кілька об'єктів об'єднуються в один пакет (batching)
4. ✅ Трафік значно зменшився (перевірити через Network Profiler)
5. ✅ Візуальна якість синхронізації не погіршилася
6. ✅ Налаштування можна змінювати через Inspector

### Тестування

**Тест 1: Thresholds**
- Об'єкт рухається на дуже малу відстань (< threshold)
- Перевірити, що стан не відправляється
- Об'єкт рухається на велику відстань (> threshold)
- Перевірити, що стан відправляється

**Тест 2: Rate limiting**
- Об'єкт рухається постійно
- Перевірити, що стан відправляється тільки кожні N фреймів

**Тест 3: Batching**
- Кілька об'єктів рухаються одночасно
- Перевірити, що стани об'єднуються в один пакет
- Перевірити, що non-owner отримує всі стани

**Тест 4: Performance**
- Виміряти трафік до та після оптимізації
- Перевірити, що CPU usage не зріс

### Потенційні проблеми

**Проблема:** Об'єкт "стрибає" через занадто великі thresholds
- **Рішення:** Зменшити thresholds, додати адаптивні thresholds (більші для швидких об'єктів)

**Проблема:** Batching затримує синхронізацію
- **Рішення:** Зменшити `batch_send_interval` або відправляти критичні об'єкти окремо

**Проблема:** Занадто багато об'єктів в одному пакеті
- **Рішення:** Обмежити `max_batch_size`, розділити на кілька пакетів

---

## PHASE 5: ОПЦІОНАЛЬНІ ПОКРАЩЕННЯ

### 5.1 Interest Management (відстань/видимість)

**Мета:** Синхронізувати тільки об'єкти, які близько до гравця або видимі.

**Архітектурні зміни:**
- Додати перевірку відстані до гравця
- Додати перевірку видимості (через VisibilityNotifier3D або ручний raycast)
- Відправляти стан тільки для об'єктів у зоні інтересу

**Складність:** Середня
**Пріоритет:** Низький (можна відкласти)

### 5.2 Late Join (синхронізація для пізніх підключень)

**Мета:** Коли новий peer підключається, відправити йому поточний стан всіх активних об'єктів.

**Архітектурні зміни:**
- Слухати `NetworkManager.peer_connected`
- При підключенні нового peer'а відправити snapshot всіх активних об'єктів
- Використовувати reliable RPC для snapshot

**Складність:** Низька
**Пріоритет:** Середній

### 5.3 Покращена інтерполяція

**Мета:** Використовувати більш складні алгоритми інтерполяції (extrapolation, lag compensation).

**Архітектурні зміни:**
- Додати буфер станів (ring buffer)
- Використовувати timestamp для правильного вибору стану
- Додати extrapolation для компенсації затримки

**Складність:** Висока
**Пріоритет:** Низький (простіша інтерполяція достатня для початку)

### 5.4 Rollback/Reconciliation

**Мета:** Компенсувати packet loss та jitter через rollback механізм.

**Складність:** Дуже висока
**Пріоритет:** Дуже низький (не обов'язково для базової реалізації)

### 5.5 Стабільний network_id для динамічних об'єктів

**Мета:** Забезпечити стабільний network_id для об'єктів, заспавнених під час гри.

**Архітектурні зміни:**
- Використовувати унікальний ID генератор (як у NetworkPickupID)
- Зберігати mapping network_id -> об'єкт в NetworkRigidSyncManager
- Синхронізувати network_id через RPC при spawn

**Складність:** Низька
**Пріоритет:** Середній (якщо є динамічні об'єкти)

---

## EDGE CASES ТА ЇХ РІШЕННЯ

### 1. Об'єкти, заспавнені під час гри

**Проблема:** Динамічно заспавнені об'єкти не мають стабільного network_id.

**Рішення:**
- Використовувати унікальний ID генератор (static counter)
- Host генерує ID та синхронізує через RPC
- Зберігати mapping в NetworkRigidSyncManager

**Реалізація:**
```gdscript
# В NetworkRigidSyncManager
static var _next_dynamic_id: int = 1000000  # Починаємо з великого числа

func _generate_dynamic_network_id() -> String:
    var id = "dynamic_%d" % _next_dynamic_id
    _next_dynamic_id += 1
    return id
```

### 2. Два peer'и одночасно взаємодіють з одним тілом

**Проблема:** Конфлікт ownership.

**Рішення:**
- Використовувати "last-write-wins" (останній запитувач отримує ownership)
- Або використовувати пріоритет (наприклад, host має пріоритет)
- Або використовувати timestamp для вирішення конфліктів

**Реалізація:**
```gdscript
func _resolve_ownership_conflict(network_id: String, requester_peer_id: int, current_owner: int) -> bool:
    # Варіант 1: Last-write-wins
    return true  # Завжди надаємо новому запитувачу
    
    # Варіант 2: Host priority
    if NetworkManager.is_host():
        return requester_peer_id == NetworkManager.get_local_peer_id()
    return false
```

### 3. Об'єкт засинає у owner і має стати неактивним всюди

**Проблема:** Owner продовжує відправляти стан для sleeping об'єкта.

**Рішення:**
- Owner також перевіряє `is_active` перед відправкою
- Якщо об'єкт sleeping та не має нещодавньої взаємодії → неактивний навіть для owner
- Але owner завжди може "прокинути" об'єкт (взаємодія)

**Реалізація:**
```gdscript
# В NetworkRigidSync._update_active_status()
if is_owner:
    # Owner завжди активний, якщо нещодавно була взаємодія
    if current_time - last_interaction_time < interaction_ttl:
        is_active = true
    elif _check_if_moving():
        is_active = true
    elif _check_if_sleeping() and consecutive_sleeping_frames >= sleeping_frames_threshold:
        is_active = false  # Owner теж може стати неактивним
    else:
        is_active = true
```

### 4. Packet loss / jitter

**Проблема:** Втрачені пакети або затримка призводять до "стрибків".

**Рішення:**
- Використовувати interpolation з буфером станів
- Додати timestamp до кожного стану
- Використовувати extrapolation для компенсації затримки
- При великій розбіжності → snap (телепорт)

**Реалізація (базова):**
```gdscript
func _apply_remote_state(state: Dictionary) -> void:
    var state_time = state.get("timestamp", 0.0)
    var current_time = Time.get_ticks_msec() / 1000.0
    var latency = current_time - state_time
    
    # Якщо затримка занадто велика → snap
    if latency > 0.5:  # 500ms
        _snap_to_state(state)
        return
    
    # Інакше → interpolation
    _lerp_to_state(state, latency)
```

### 5. Reload сцени / reparenting

**Проблема:** При перезавантаженні сцени network_id може змінитися.

**Рішення:**
- Використовувати стабільний network_id (на основі scene_path + node_path)
- При reload сцени компоненти автоматично реінжектуються
- Очищати реєстр при зміні сцени

**Реалізація:**
```gdscript
# В NetworkRigidSyncManager
func _on_scene_changed() -> void:
    registered_bodies.clear()
    # Автоматично знайде нові об'єкти через node_added signal
```

### 6. Стабільний network_id (НЕ NodePath)

**Проблема:** NodePath може змінитися при reparenting.

**Рішення:**
- Використовувати String ID на основі scene_path + node_path (як у NetworkInteractable)
- Для динамічних об'єктів — унікальний ID генератор
- Зберігати mapping network_id -> об'єкт в NetworkRigidSyncManager

**Реалізація:**
```gdscript
# В NetworkRigidSync._generate_network_id()
func _generate_network_id() -> String:
    var scene = get_tree().current_scene
    if not scene:
        return ""
    
    var scene_path = scene.scene_file_path
    var node_path = parent_rigid_body.get_path()
    
    # Для статичних об'єктів
    return "%s::%s" % [scene_path, str(node_path)]
    
    # Для динамічних (якщо потрібно)
    # return NetworkRigidSyncManager._generate_dynamic_network_id()
```

---

## ТЕХНІЧНІ ДЕТАЛІ

### Godot 4 API, які будуть використовуватися

1. **RigidBody3D:**
   - `position`, `global_position`
   - `quaternion`, `global_transform.basis.get_rotation_quaternion()`
   - `linear_velocity`, `angular_velocity`
   - `sleeping` (bool)
   - `freeze` (bool)
   - `freeze_mode` (enum)
   - `set_lock_rotation_enabled(bool)`
   - `apply_central_impulse(Vector3)`

2. **SceneTree:**
   - `node_added` signal
   - `get_nodes_in_group(String)`
   - `current_scene`

3. **Multiplayer:**
   - `@rpc()` анотації
   - `multiplayer.get_unique_id()`
   - `multiplayer.is_server()`

4. **Time:**
   - `Time.get_ticks_msec()`

5. **Quaternion:**
   - `Quaternion.slerp(Quaternion, float)`
   - `Quaternion.angle_to(Quaternion)`

### Структура файлів

```
addons/cogito/network/
├── network_rigid_sync.gd          # Компонент синхронізації (додається до RigidBody3D)
├── network_rigid_sync_manager.gd # Autoload менеджер (інжекція, реєстр, батчінг)
└── (оновлення network_manager.gd) # Додавання RPC для rigid body sync
```

### Залежності

- `NetworkManager` (autoload) — для RPC
- `PlayerManager` (autoload) — для отримання гравців (опціонально, для interest management)
- `CommandBus` / `EventBus` — для інтеграції з взаємодіями (опціонально)

---

## ПОРЯДОК РЕАЛІЗАЦІЇ

1. **Phase 0** (1-2 дні): Інжекція та збір даних
2. **Phase 1** (1 день): Обмежений sync
3. **Phase 2** (2-3 дні): Ownership + freeze/unfreeze
4. **Phase 3** (1-2 дні): Active-only логіка
5. **Phase 4** (2-3 дні): Оптимізація
6. **Phase 5** (опціонально): Покращення

**Загальний час:** ~7-11 днів для базової реалізації (Phase 0-4)

---

## КРИТЕРІЇ УСПІХУ

✅ Всі RigidBody3D автоматично синхронізуються без змін у сценах
✅ Owner-authority працює стабільно
✅ Тільки активні об'єкти синхронізуються (економія трафіку)
✅ Плавна синхронізація без "стрибків"
✅ Мінімальний трафік (оптимізація)
✅ Стабільна робота з edge cases

---

## ПРИМІТКИ

- План розроблений з урахуванням поточної архітектури проекту (NetworkManager, Command/Event система, компонентна модель)
- Кожна фаза може бути протестована незалежно
- Можна пропустити Phase 5, якщо базової функціональності достатньо
- Рекомендується тестувати на реальних сценах з багатьма об'єктами

