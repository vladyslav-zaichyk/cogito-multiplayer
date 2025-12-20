# 🎯 Command/Event Sourcing Architecture Plan

## Мета
Перехід від State Synchronization до Command/Event Sourcing архітектури для спрощення розробки мультиплеєру та підготовки до майбутніх змін (фізика, View/World моделі).

## Глобальні принципи

### Основні цінності:
1. ✅ **Збереження синглплеєру** - кожна зміна має працювати в синглплеєрі
2. ✅ **Поступовість** - кожна зміна не ламає геймплей
3. ✅ **Self-documented код** - чіткі назви, коментарі, SOLID принципи
4. ✅ **Тестованість** - команди можна тестувати ізольовано
5. ✅ **Уніфікація** - всі дії через команди (і в синглплеєрі, і в мультиплеєрі)

### Технічні принципи:
- **Command Pattern** - всі дії обробляються через команди
- **Event Sourcing** - події зберігаються для майбутнього replay (опціонально)
- **Authority Management** - два типи команд: хост-валідація та клієнт-валідація
- **Оптимістичне виконання** - команди виконуються локально одразу, потім валідуються
- **Абстракція для жорсткої валідації** - можливість перейти на серверну валідацію без змін коду

---

## Фаза 0: Створення базової інфраструктури

**Мета:** Створити фундамент для системи команд та подій.

### Етап 0.1: Базові класи команд

**Пріоритет:** 🔴 Критично - без цього неможливо рухатись далі

**Файли для створення:**
- `addons/cogito/network/commands/command.gd` - базовий клас команди
- `addons/cogito/network/commands/command_result.gd` - результат виконання команди
- `addons/cogito/network/commands/command_bus.gd` - автолоад для маршрутизації команд
- `addons/cogito/network/commands/event.gd` - базовий клас події

**Детальний план:**

#### 0.1.1: Створити базовий клас Command
```gdscript
# command.gd
class_name Command
extends RefCounted

## Унікальний ID команди (UUID або timestamp-based)
var command_id: String
## ID гравця, який виконав команду
var player_id: int
## Timestamp виконання команди
var timestamp: float
## Чи команда вже виконана
var executed: bool = false
## Тип валідації: HOST_VALIDATION або CLIENT_VALIDATION
enum ValidationType { HOST_VALIDATION, CLIENT_VALIDATION }
var validation_type: ValidationType = ValidationType.HOST_VALIDATION

## Виконати команду (override в підкласах)
func execute() -> CommandResult:
    push_error("Command.execute() must be overridden")
    return CommandResult.new(false, "Not implemented")

## Валідувати команду перед виконанням (override в підкласах)
func validate() -> bool:
    return true  # За замовчуванням валідація проходить

## Серіалізувати команду для мережі
func serialize() -> Dictionary:
    return {
        "command_id": command_id,
        "player_id": player_id,
        "timestamp": timestamp,
        "command_type": get_script().get_path().get_file().get_basename()
    }

## Десеріалізувати команду з мережі
static func deserialize(data: Dictionary) -> Command:
    push_error("Command.deserialize() must be overridden")
    return null
```

**Критерії готовності:**
- [x] Клас створено та зареєстровано як class_name
- [x] Всі базові поля визначено
- [x] Методи execute(), validate(), serialize(), deserialize() реалізовано
- [x] Документація додана

#### 0.1.2: Створити CommandResult
```gdscript
# command_result.gd
class_name CommandResult
extends RefCounted

## Чи команда виконана успішно
var success: bool
## Повідомлення про помилку (якщо є)
var error_message: String = ""
## Список подій, які виникли в результаті виконання команди
var events: Array[Event] = []
## Додаткові дані результату
var data: Dictionary = {}

func _init(success_value: bool = true, error: String = ""):
    success = success_value
    error_message = error
```

**Критерії готовності:**
- [x] Клас створено та зареєстровано як class_name
- [x] Всі поля визначено (включає response_code систему)
- [x] Конструктор реалізовано

#### 0.1.3: Створити базовий клас Event
```gdscript
# event.gd
class_name Event
extends RefCounted

## Унікальний ID події
var event_id: String
## ID гравця, який викликав подію
var player_id: int
## Timestamp події
var timestamp: float
## Тип події (для маршрутизації)
var event_type: String

func _init():
    event_id = _generate_id()
    timestamp = Time.get_ticks_msec() / 1000.0

func _generate_id() -> String:
    # Простий UUID генератор (можна замінити на більш надійний)
    return "%s_%d" % [str(Time.get_ticks_msec()), randi()]

## Серіалізувати подію для мережі
func serialize() -> Dictionary:
    return {
        "event_id": event_id,
        "player_id": player_id,
        "timestamp": timestamp,
        "event_type": event_type
    }
```

**Критерії готовності:**
- [x] Клас створено та зареєстровано як class_name
- [x] Всі поля визначено
- [x] Метод serialize() реалізовано

#### 0.1.4: Створити CommandBus (автолоад)
```gdscript
# command_bus.gd
extends Node

## Автолоад для маршрутизації команд

## Реєстр обробників команд (command_type -> handler)
var _command_handlers: Dictionary = {}
## Реєстр обробників подій (event_type -> handlers array)
var _event_handlers: Dictionary = {}
## Чи увімкнено логування
var enable_logging: bool = false

## Зареєструвати обробник команди
func register_command_handler(command_type: String, handler: Callable) -> void:
    if not _command_handlers.has(command_type):
        _command_handlers[command_type] = []
    _command_handlers[command_type].append(handler)

## Зареєструвати обробник події
func register_event_handler(event_type: String, handler: Callable) -> void:
    if not _event_handlers.has(event_type):
        _event_handlers[event_type] = []
    _event_handlers[event_type].append(handler)

## Виконати команду
func execute_command(command: Command) -> CommandResult:
    # Локальне виконання (оптимістичне)
    var result = command.execute()
    
    # Якщо мультиплеєр, відправити команду на валідацію
    if NetworkManager and NetworkManager.is_multiplayer():
        _send_command_for_validation(command)
    
    # Емітувати події
    for event in result.events:
        _emit_event(event)
    
    return result

## Відправити команду на валідацію (хост або клієнт)
func _send_command_for_validation(command: Command) -> void:
    if command.validation_type == Command.ValidationType.HOST_VALIDATION:
        if NetworkManager.is_host():
            # Хост валідує локально
            _validate_and_broadcast(command)
        else:
            # Клієнт відправляє на хост
            NetworkManager.validate_command.rpc(command.serialize())
    else:
        # CLIENT_VALIDATION - клієнт валідує локально
        _validate_and_broadcast(command)

## Валідувати та розіслати команду
func _validate_and_broadcast(command: Command) -> void:
    if command.validate():
        # Розіслати команду всім клієнтам
        NetworkManager.broadcast_command.rpc(command.serialize())
    else:
        # Валідація не пройшла - відкотити локальні зміни
        _rollback_command(command)

## Емітувати подію
func _emit_event(event: Event) -> void:
    if _event_handlers.has(event.event_type):
        for handler in _event_handlers[event.event_type]:
            handler.call(event)
```

**Критерії готовності:**
- [x] Клас створено та зареєстровано як автолоад
- [x] Реєстрація обробників працює
- [x] Виконання команд працює (з оптимістичним виконанням та pre-validation)
- [x] Інтеграція з NetworkManager працює
- [x] Логування додано (через ResponseHandler)
- [x] ResponseHandler створено для централізованої обробки результатів
- [x] ResponseCode система реалізована (SUCCESS, CLIENT_ERROR, SERVER_ERROR)

**Залежності:**
- NetworkManager має RPC методи `validate_command` та `broadcast_command`

**Оцінка часу:** 4-6 годин

---

## Фаза 1: Inventory Commands (Найпростіші)

**Мета:** Переробити базові операції з інвентарем на команди.

**Пріоритет:** 🔴 Високий - найпростіші команди, легше тестувати

### Категорія 1: Pickup Commands

#### Етап 1.1: PickupItemCommand

**Файли для створення:**
- `addons/cogito/network/commands/inventory/pickup_item_command.gd`
- `addons/cogito/network/commands/events/item_picked_event.gd`

**Файли для модифікації:**
- `addons/cogito/Components/Interactions/pickup_component.gd`
- `addons/cogito/inventory_pd/cogito_inventory.gd`

**Детальний план:**

##### 1.1.1: Створити PickupItemCommand
```gdscript
# pickup_item_command.gd
extends Command
class_name PickupItemCommand

## Дані слота предмета для підняття
var slot_data: InventorySlotPD
## Позиція предмета в світі (для ідентифікації)
var item_position: Vector3
## Network ID предмета (якщо є)
var item_network_id: int = -1
## Scene path предмета (для ідентифікації)
var item_scene_path: String = ""

func _init(player_id_value: int, slot_data_value: InventorySlotPD, position: Vector3, network_id: int = -1, scene_path: String = ""):
    command_id = _generate_id()
    player_id = player_id_value
    timestamp = Time.get_ticks_msec() / 1000.0
    slot_data = slot_data_value
    item_position = position
    item_network_id = network_id
    item_scene_path = scene_path
    validation_type = ValidationType.HOST_VALIDATION  # Хост валідує підняття предметів

func execute() -> CommandResult:
    var result = CommandResult.new()
    
    # Отримати інвентар гравця
    var player = PlayerManager.get_player(player_id) if PlayerManager else null
    if not player or not player.inventory_data:
        return CommandResult.new(false, "Player or inventory not found")
    
    # Спробувати підняти предмет
    var success = player.inventory_data.pick_up_slot_data(slot_data)
    
    if success:
        # Створити подію
        var event = ItemPickedEvent.new(player_id, slot_data.inventory_item, slot_data)
        result.events.append(event)
        result.success = true
    else:
        result.success = false
        result.error_message = "Failed to pick up item"
    
    return result

func validate() -> bool:
    # Перевірити, чи предмет існує в світі
    # Перевірити, чи гравець може підняти предмет
    # Перевірити, чи є місце в інвентарі
    return true  # TODO: реалізувати валідацію

static func deserialize(data: Dictionary) -> Command:
    # TODO: реалізувати десеріалізацію
    return null
```

**Критерії готовності:**
- [ ] Команда створена та наслідує Command
- [ ] Метод execute() реалізовано
- [ ] Метод validate() реалізовано (базова валідація)
- [ ] Метод serialize()/deserialize() реалізовано
- [ ] Інтеграція з існуючим кодом працює

##### 1.1.2: Створити ItemPickedEvent
```gdscript
# item_picked_event.gd
extends Event
class_name ItemPickedEvent

var item: InventoryItemPD
var slot_data: InventorySlotPD

func _init(player_id_value: int, item_value: InventoryItemPD, slot_data_value: InventorySlotPD):
    super._init()
    player_id = player_id_value
    event_type = "item_picked"
    item = item_value
    slot_data = slot_data_value
```

**Критерії готовності:**
- [ ] Подія створена та наслідує Event
- [ ] Всі поля визначено
- [ ] Метод serialize() реалізовано

##### 1.1.3: Інтегрувати з PickupComponent
**Зміни в `pickup_component.gd`:**
- Замінити прямий виклик `pick_up()` на `CommandBus.execute_command(PickupItemCommand.new(...))`
- Зберегти fallback для сумісності (якщо CommandBus не доступний)

**Критерії готовності:**
- [ ] PickupComponent використовує команду замість прямого виклику
- [ ] Синглплеєр працює (fallback)
- [ ] Мультиплеєр працює (через команди)
- [ ] Тестування пройдено

**Оцінка часу:** 3-4 години

#### Етап 1.2: DropItemCommand

**Файли для створення:**
- `addons/cogito/network/commands/inventory/drop_item_command.gd`
- `addons/cogito/network/commands/events/item_dropped_event.gd`

**Файли для модифікації:**
- `addons/cogito/inventory_pd/ui_scenes/inventory_interface.gd`
- `addons/cogito/inventory_pd/cogito_inventory.gd`

**Детальний план:** Аналогічно до PickupItemCommand

**Оцінка часу:** 3-4 години

#### Етап 1.3: UseItemCommand

**Файли для створення:**
- `addons/cogito/network/commands/inventory/use_item_command.gd`
- `addons/cogito/network/commands/events/item_used_event.gd`

**Файли для модифікації:**
- `addons/cogito/inventory_pd/cogito_inventory.gd`

**Детальний план:** Аналогічно до PickupItemCommand

**Оцінка часу:** 2-3 години

**Загальний прогрес Фази 1:** ✅ 3/3 етапів (100%) - ЗАВЕРШЕНО
- ✅ Етап 1.1: PickupItemCommand - реалізовано
- ✅ Етап 1.2: DropItemCommand - реалізовано
- ✅ Етап 1.3: UseItemCommand - реалізовано

---

## Фаза 2: Wieldable Commands

**Мета:** Переробити операції зі зброєю на команди.

**Пріоритет:** 🟡 Середній - складніше, але важливо для майбутніх змін

### Категорія 2: Wieldable Management

#### Етап 2.1: EquipWieldableCommand

**Файли для створення:**
- `addons/cogito/network/commands/wieldable/equip_wieldable_command.gd`
- `addons/cogito/network/commands/events/wieldable_equipped_event.gd`

**Файли для модифікації:**
- `addons/cogito/Components/player_interaction_component.gd`
- `addons/cogito/inventory_pd/CustomResources/WieldableItemPD.gd`

**Оцінка часу:** 4-5 годин

#### Етап 2.2: UnequipWieldableCommand

**Оцінка часу:** 2-3 години

#### Етап 2.3: WieldableActionCommand (primary/secondary)

**Оцінка часу:** 3-4 години

#### Етап 2.4: ReloadWieldableCommand

**Оцінка часу:** 2-3 години

**Загальний прогрес Фази 2:** ✅ 4/4 етапів (100%) - ЗАВЕРШЕНО
- ✅ Етап 2.1: EquipWieldableCommand - реалізовано
- ✅ Етап 2.2: UnequipWieldableCommand - реалізовано
- ✅ Етап 2.3: WieldableActionCommand - реалізовано
- ✅ Етап 2.4: ReloadWieldableCommand - реалізовано

---

## Фаза 3: Carry Commands

**Мета:** Переробити операції переносу предметів на команди.

**Пріоритет:** 🟡 Середній

### Категорія 3: Carry Management

#### Етап 3.1: StartCarryingCommand

**Оцінка часу:** 2-3 години

#### Етап 3.2: StopCarryingCommand

**Оцінка часу:** 2-3 години

#### Етап 3.3: ThrowCarriedItemCommand

**Оцінка часу:** 3-4 години

**Загальний прогрес Фази 3:** ✅ 2/3 етапів (67%) - МАЙЖЕ ЗАВЕРШЕНО
- ✅ Етап 3.1: StartCarryingCommand - реалізовано
- ✅ Етап 3.2: StopCarryingCommand - реалізовано (включає drop та throw)
- ⏸️ Етап 3.3: ThrowCarriedItemCommand - об'єднано з StopCarryingCommand

---

## Фаза 4: Interaction Commands

**Мета:** Переробити взаємодії з об'єктами на команди.

**Пріоритет:** 🟢 Низький - вже є NetworkInteractable, можна покращити

### Категорія 4: World Interactions

#### Етап 4.1: InteractWithDoorCommand

**Оцінка часу:** 2-3 години

#### Етап 4.2: InteractWithContainerCommand

**Оцінка часу:** 2-3 години

#### Етап 4.3: InteractWithSwitchCommand

**Оцінка часу:** 2-3 години

**Загальний прогрес Фази 4:** ✅ 4/4 етапів (100%) - ЗАВЕРШЕНО
- ✅ Етап 4.1: InteractWithDoorCommand - реалізовано (включає open_then_unlock для анімації, hold interaction для lock/unlock)
- ✅ Етап 4.2: InteractWithContainerCommand - реалізовано
- ✅ Етап 4.3: InteractWithSwitchCommand - реалізовано
- ✅ Етап 4.4: InteractWithTurnwheelCommand - реалізовано (start/stop/complete, visual replication)

---

## Пріоритизація категорій та скриптів

### Пріоритет 1: Inventory Commands (Фаза 1)
**Чому спочатку:**
- Найпростіші операції
- Легко тестувати
- Мінімальний ризик ламати геймплей
- Базова функціональність для мультиплеєру

**Скрипти для змін (в порядку):**
1. `pickup_component.gd` - найпростіший, найчастіше використовується
2. `cogito_inventory.gd` - `pick_up_slot_data()`, `drop_slot_data()`, `use_slot_data()`
3. `inventory_interface.gd` - UI для дропу

### Пріоритет 2: Wieldable Commands (Фаза 2)
**Чому далі:**
- Важливо для майбутніх змін (ViewModel/WorldModel)
- Складніше, але критично
- Потрібно для синхронізації зброї

**Скрипти для змін (в порядку):**
1. `player_interaction_component.gd` - `equip_wieldable()`, `change_wieldable_to()`
2. `WieldableItemPD.gd` - `take_out()`, `put_away()`
3. `cogito_wieldable.gd` - базові методи
4. Конкретні wieldables (pistol, flashlight, тощо) - `action_primary()`, `action_secondary()`, `reload()`

### Пріоритет 3: Carry Commands (Фаза 3)
**Чому потім:**
- Менш критично
- Використовується рідше
- Можна зробити після базових команд

**Скрипти для змін:**
1. `player_interaction_component.gd` - `start_carrying()`, `stop_carrying()`, `_drop_carried_object()`, `_attempt_throw()`
2. `carryable_component.gd` - `carry()`, `throw()`

### Пріоритет 4: Interaction Commands (Фаза 4)
**Чому останні:**
- Вже є NetworkInteractable
- Менш критично
- Можна покращити існуючу систему

**Скрипти для змін:**
1. `network_interactable.gd` - можна покращити через команди
2. `cogito_door.gd`, `cogito_switch.gd`, `cogito_container.gd` - інтеграція з командами

---

## Стратегія поступової міграції

### Принцип "Feature Flag"
- Кожна команда має fallback на старий код
- Якщо CommandBus не доступний, використовується старий код
- Поступово вмикаємо команди для різних операцій

### Принцип "Backward Compatibility"
- Старий код залишається працювати
- Команди викликають старий код під капотом (поки що)
- Поступово замінюємо внутрішню реалізацію

### Принцип "Incremental Testing"
- Після кожної команди - тестування
- Спершу в синглплеєрі, потім в мультиплеєрі
- Кожна команда має працювати незалежно

---

## Інтеграція з NetworkManager

### Нові RPC методи в NetworkManager:
```gdscript
## RPC: Валідувати команду (клієнт -> хост)
@rpc("any_peer", "call_local", "reliable")
func validate_command(command_data: Dictionary) -> void:
    # Хост валідує команду
    var command = Command.deserialize(command_data)
    if command and command.validate():
        # Розіслати всім клієнтам
        broadcast_command.rpc(command_data)

## RPC: Розіслати команду всім клієнтам (хост -> всі)
@rpc("any_peer", "call_local", "reliable")
func broadcast_command(command_data: Dictionary) -> void:
    # Всі клієнти виконують команду
    var command = Command.deserialize(command_data)
    if command:
        CommandBus.execute_command(command)
```

---

## Тестування

### Для кожної команди:
1. ✅ Тест в синглплеєрі - команда працює
2. ✅ Тест в мультиплеєрі - команда синхронізується
3. ✅ Тест валідації - хост валідує правильно
4. ✅ Тест rollback - невалідна команда відкочується
5. ✅ Тест подій - події емітуються правильно

---

## Загальний прогрес

**Завершено:** ✅ 13/13 основних етапів (100%)  
**Поточний статус:** Всі основні фази завершені, система працює в синглплеєрі та мультиплеєрі

### Детальний прогрес:

**Фаза 0: Базова інфраструктура** - ✅ 100%
- ✅ Command, CommandResult, Event базові класи
- ✅ CommandBus з оптимістичним виконанням та pre-validation
- ✅ ResponseHandler для централізованої обробки результатів
- ✅ ResponseCode система (SUCCESS, CLIENT_ERROR, SERVER_ERROR)

**Фаза 1: Inventory Commands** - ✅ 100%
- ✅ PickupItemCommand
- ✅ DropItemCommand
- ✅ UseItemCommand

**Фаза 2: Wieldable Commands** - ✅ 100%
- ✅ EquipWieldableCommand
- ✅ UnequipWieldableCommand
- ✅ WieldableActionCommand
- ✅ ReloadWieldableCommand

**Фаза 3: Carry Commands** - ✅ 100% (ThrowCarriedItemCommand об'єднано з StopCarryingCommand)
- ✅ StartCarryingCommand
- ✅ StopCarryingCommand (включає drop та throw)

**Фаза 4: Interaction Commands** - ✅ 100%
- ✅ InteractWithDoorCommand (з open_then_unlock для анімації та hold interaction)
- ✅ InteractWithContainerCommand
- ✅ InteractWithSwitchCommand
- ✅ InteractWithTurnwheelCommand (з start/stop/complete та visual replication)

---

## Наступні кроки (опціональні покращення)

### Покращення архітектури (рефакторинг):
1. **Винести обробку turnwheel/door в окремі сервіси/стратегії** - для кращого дотримання SOLID
2. **Реєстрація обробників подій замість жорстко закодованих `_handle_*_event()`** - для кращого Open/Closed принципу
3. **Створити абстракцію для різних типів hold-інтеракцій** - для уникнення дублювання коду

### Додаткові можливості:
1. **Event Store для replay** - зберігання подій для майбутнього replay (якщо потрібно)
2. **Rollback система** - повна реалізація rollback для невалідних команд (зараз тільки логування)
3. **Command Queue** - черга команд для обробки в правильному порядку
4. **Command History** - історія команд для debugging

### Оптимізації:
1. **Batch commands** - групування команд для зменшення мережевого трафіку
2. **Command compression** - стиснення серіалізованих команд
3. **Prediction/Reconciliation** - покращення оптимістичного виконання

---

## Додаткові реалізації (поза основним планом)

### ResponseCode система
- ✅ Реалізовано HTTP-подібну систему кодів відповідей (2xx, 4xx, 5xx)
- ✅ ResponseHandler для централізованої обробки результатів
- ✅ Категорії: SUCCESS, CLIENT_ERROR, SERVER_ERROR
- ✅ Автоматичне логування на основі категорії коду

### Покращення для дверей
- ✅ `open_then_unlock()` - відновлено стару поведінку (анімація перед unlock)
- ✅ Підтримка hold interaction для lock/unlock через DualInteraction
- ✅ Інтеграція LockInteraction з командною системою

### Покращення для turnwheel
- ✅ `start_visual_rotation()`, `stop_visual_rotation()`, `complete_interaction()` - розділення візуальної реплікації та логіки
- ✅ Підтримка "start", "stop", "complete" типів інтеракції
- ✅ Visual replication на всіх клієнтах через `_physics_process`
- ✅ Правильна обробка скасування hold

### Оптимізації CommandBus
- ✅ Pre-validation для запобігання помилок валідації після optimistic execution
- ✅ Правильна обробка подій на remote клієнтах (без re-execution команд)
- ✅ Десеріалізація команд та подій через `class_name` (без preload)

---

## Нотатки

- Команди мають бути ідемпотентними (можна виконати кілька разів без побічних ефектів)
- Події мають бути immutable (не змінюються після створення)
- Валідація має бути швидкою (не блокує геймплей)
- Rollback має бути надійним (відкочує всі зміни) - ⚠️ поки що тільки логування, повна реалізація в майбутньому

