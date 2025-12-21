# 🔧 Command/Event Sourcing Refactoring Plan

## Мета
Покращити якість коду системи команд та подій, дотримуючись принципів SOLID, KISS та Godot конвенцій (строга типізація, compile-time перевірки).

---

## 📋 Оцінка поточного стану

### Файли для аналізу (31 файл)

#### Базові класи (4 файли)
1. `command.gd` - базовий клас команди
2. `event.gd` - базовий клас події
3. `command_result.gd` - результат виконання команди
4. `response_handler.gd` - обробник результатів

#### CommandBus (1 файл)
5. `command_bus.gd` - центральний маршрутизатор команд та подій

#### Команди (17 файлів)
- Inventory: `pickup_item_command.gd`, `drop_item_command.gd`, `use_item_command.gd`
- Wieldable: `equip_wieldable_command.gd`, `unequip_wieldable_command.gd`, `wieldable_action_command.gd`, `reload_wieldable_command.gd`
- Carry: `start_carrying_command.gd`, `stop_carrying_command.gd`
- Interaction: `interact_with_door_command.gd`, `interact_with_switch_command.gd`, `interact_with_container_command.gd`, `interact_with_turnwheel_command.gd`

#### Події (13 файлів)
- Всі події в `events/` директорії

---

## 🔍 Детальна оцінка по файлах

### 1. `command.gd` - Базовий клас команди

**Оцінка:**
- **SOLID:** ✅ 9/10 - добре
  - Single Responsibility: ✅ Один клас - одна відповідальність
  - Open/Closed: ✅ Можна розширювати через наслідування
  - Liskov Substitution: ✅ Підкласи можуть замінювати базовий клас
  - Interface Segregation: ✅ Мінімальний інтерфейс
  - Dependency Inversion: ✅ Залежить від абстракцій (CommandResult)
- **KISS:** ✅ 9/10 - простий та зрозумілий
- **Чистота коду:** ✅ 8/10
- **Godot конвенції:** ⚠️ 7/10
  - ❌ Використовує `get_script().get_path()` для визначення типу (runtime check)
  - ❌ `_generate_id()` може бути краще (UUID)
  - ✅ Використовує `class_name` для статичної типізації

**Симптоми:**
1. Runtime визначення типу команди через `get_script().get_path()`
2. Простий ID генератор (може бути колізії)
3. Немає compile-time перевірки типу команди

**Рішення:**
1. Додати `command_type: String` поле, яке встановлюється в `_init()` підкласів
2. Використати UUID для генерації ID (або залишити як є, якщо достатньо)
3. Додати статичний метод `get_command_type() -> String` в підкласах

---

### 2. `event.gd` - Базовий клас події

**Оцінка:**
- **SOLID:** ✅ 9/10 - добре
- **KISS:** ✅ 9/10 - простий
- **Чистота коду:** ✅ 8/10
- **Godot конвенції:** ⚠️ 7/10
  - ❌ Те ж саме, що і в Command - runtime визначення типу

**Симптоми:**
1. Runtime визначення типу події
2. Простий ID генератор

**Рішення:**
1. Додати `event_type: String` поле (вже є, але встановлюється в `_init()`)
2. Переконатися, що всі підкласи правильно встановлюють `event_type`

---

### 3. `command_result.gd` - Результат виконання команди

**Оцінка:**
- **SOLID:** ✅ 10/10 - відмінно
- **KISS:** ✅ 9/10 - простий
- **Чистота коду:** ✅ 9/10
- **Godot конвенції:** ✅ 9/10
  - ✅ Використовує enum для типізації
  - ✅ Строга типізація полів

**Симптоми:**
- Мінімальні - клас добре спроектований

**Рішення:**
- Немає критичних проблем

---

### 4. `response_handler.gd` - Обробник результатів

**Оцінка:**
- **SOLID:** ✅ 8/10
  - Single Responsibility: ✅ Обробка результатів
  - Open/Closed: ⚠️ 6/10 - жорстко закодовані обробники для кожного коду
- **KISS:** ✅ 8/10
- **Чистота коду:** ✅ 8/10
- **Godot конвенції:** ✅ 8/10

**Симптоми:**
1. Жорстко закодовані обробники для кожного ResponseCode в `match` блоці
2. Дублювання логіки між `_log_levels` та `_code_messages`

**Рішення:**
1. Використати реєстрацію обробників замість `match` блоку
2. Об'єднати `_log_levels` та `_code_messages` в одну структуру даних

---

### 5. `command_bus.gd` - Центральний маршрутизатор ⚠️ КРИТИЧНО

**Оцінка:**
- **SOLID:** ⚠️ 5/10 - потребує рефакторингу
  - Single Responsibility: ❌ 4/10 - знає про конкретні типи команд/подій
  - Open/Closed: ❌ 3/10 - додавання нового типу вимагає змін у `_deserialize_command()` та `_deserialize_event()`
  - Liskov Substitution: ✅ 8/10
  - Interface Segregation: ✅ 8/10
  - Dependency Inversion: ⚠️ 6/10 - залежить від конкретних класів команд/подій
- **KISS:** ⚠️ 6/10 - занадто складний через жорстко закодовані обробники
- **Чистота коду:** ⚠️ 6/10
- **Godot конвенції:** ⚠️ 6/10
  - ❌ Величезний `match` блок для десеріалізації (253-286 рядки)
  - ❌ Величезний `match` блок для десеріалізації подій (440-473 рядки)
  - ❌ Жорстко закодовані обробники подій (`_handle_turnwheel_event`, `_handle_door_event`)
  - ❌ Використання `"property_name" in event` для перевірки властивостей (runtime check)
  - ❌ Використання `event.property_name` без типізації

**Симптоми:**
1. **Порушення Open/Closed Principle:** Додавання нового типу команди/події вимагає змін у CommandBus
2. **Порушення Single Responsibility:** CommandBus знає про конкретні типи об'єктів (turnwheel, door)
3. **Дублювання коду:** `_handle_turnwheel_event()` та `_handle_door_event()` мають схожу структуру
4. **Runtime перевірки:** Використання `"property_name" in event` замість compile-time перевірок
5. **Величезні match блоки:** 30+ рядків для десеріалізації команд та подій
6. **Відсутність типізації:** Події обробляються як `RefCounted` без типізації

**Рішення:**
1. **Реєстрація обробників:** Створити систему реєстрації для команд та подій
2. **Event Handler Registry:** Винести обробку подій в окремі класи-обробники
3. **Factory Pattern:** Використати фабрики для десеріалізації
4. **Строга типізація:** Використовувати `class_name` та типізовані змінні
5. **Видалення жорстко закодованих обробників:** Замінити `_handle_*_event()` на реєстровані обробники

---

### 6. Команди (приклад: `pickup_item_command.gd`)

**Оцінка:**
- **SOLID:** ✅ 8/10
  - Single Responsibility: ✅ Одна команда - одна дія
  - Open/Closed: ✅ Можна розширювати
  - Liskov Substitution: ✅
  - Interface Segregation: ✅
  - Dependency Inversion: ⚠️ 7/10 - залежить від конкретних класів (InventorySlotPD)
- **KISS:** ✅ 9/10
- **Чистота коду:** ✅ 8/10
- **Godot конвенції:** ⚠️ 7/10
  - ❌ Використання `"property_name" in slot_data` для перевірки властивостей
  - ❌ Runtime перевірки типів
  - ✅ Використовує `class_name` для статичної типізації

**Симптоми:**
1. Runtime перевірки властивостей через `"property_name" in object`
2. Складність серіалізації/десеріалізації (багато коду)

**Рішення:**
1. Використовувати строгу типізацію замість runtime перевірок
2. Винести логіку серіалізації в окремі методи або класи

---

### 7. Події (приклад: `item_picked_event.gd`)

**Оцінка:**
- **SOLID:** ✅ 9/10
- **KISS:** ✅ 9/10
- **Чистота коду:** ✅ 9/10
- **Godot конвенції:** ✅ 8/10
  - ✅ Використовує `class_name`
  - ✅ Строга типізація полів

**Симптоми:**
- Мінімальні - події добре спроектовані

**Рішення:**
- Немає критичних проблем

---

## 🎯 Пріоритети рефакторингу

### 🔴 Критично (потрібно виправити негайно)
1. **CommandBus** - порушення Open/Closed Principle, величезні match блоки
2. **Runtime перевірки** - замінити на compile-time перевірки

### 🟡 Важливо (потрібно виправити скоро)
3. **ResponseHandler** - жорстко закодовані обробники
4. **Команди** - runtime перевірки властивостей

### 🟢 Бажано (можна виправити пізніше)
5. **ID генератори** - покращити (UUID)
6. **Серіалізація** - винести в окремі класи

---

## 📝 Детальний план рефакторингу

### Етап 1: Реєстрація обробників для CommandBus

**Мета:** Виправити порушення Open/Closed Principle в CommandBus

**Симптоми:**
- Додавання нового типу команди/події вимагає змін у CommandBus
- Величезні match блоки (30+ рядків кожен)
- Неможливо додати новий тип без модифікації CommandBus

**Рішення:**
1. Створити `CommandRegistry` клас для реєстрації команд
2. Створити `EventRegistry` клас для реєстрації подій
3. Замінити match блоки на реєстрацію
4. Використати фабричний паттерн для десеріалізації

**Детальні кроки:**

#### Крок 1.1: Створити CommandRegistry
**Файл:** `addons/cogito/network/commands/command_registry.gd`

```gdscript
extends RefCounted
class_name CommandRegistry
## Registry for command deserialization.
## Allows registering command types without modifying CommandBus.

## Registry of command type -> deserialize function
var _deserializers: Dictionary = {}

## Register a command type for deserialization
## command_type: String identifier (e.g., "pickup_item_command")
## deserializer: Static function that takes Dictionary and returns Command
func register_command_type(command_type: String, deserializer: Callable) -> void:
	_deserializers[command_type] = deserializer

## Deserialize command from data
func deserialize(data: Dictionary) -> Command:
	var command_type = data.get("command_type", "")
	if not _deserializers.has(command_type):
		push_error("CommandRegistry: Unknown command type: %s" % command_type)
		return null
	
	var deserializer = _deserializers[command_type]
	return deserializer.call(data)
```

**Критерії готовності:**
- [x] Клас створено та зареєстровано як `class_name`
- [x] Метод `register_command_type()` працює
- [x] Метод `deserialize()` працює
- [x] Тестування пройдено

#### Крок 1.2: Створити EventRegistry
**Файл:** `addons/cogito/network/commands/event_registry.gd`

```gdscript
extends RefCounted
class_name EventRegistry
## Registry for event deserialization.
## Allows registering event types without modifying CommandBus.

## Registry of event type -> deserialize function
var _deserializers: Dictionary = {}

## Register an event type for deserialization
## event_type: String identifier (e.g., "item_picked")
## deserializer: Static function that takes Dictionary and returns Event
func register_event_type(event_type: String, deserializer: Callable) -> void:
	_deserializers[event_type] = deserializer

## Deserialize event from data
func deserialize(data: Dictionary) -> Event:
	var event_type = data.get("event_type", "")
	if not _deserializers.has(event_type):
		push_error("EventRegistry: Unknown event type: %s" % event_type)
		return null
	
	var deserializer = _deserializers[event_type]
	return deserializer.call(data)
```

**Критерії готовності:**
- [x] Клас створено та зареєстровано як `class_name`
- [x] Метод `register_event_type()` працює
- [x] Метод `deserialize()` працює
- [x] Тестування пройдено

#### Крок 1.3: Модифікувати CommandBus для використання реєстрів
**Зміни в `command_bus.gd`:**

1. Додати поля для реєстрів:
```gdscript
var command_registry: CommandRegistry = CommandRegistry.new()
var event_registry: EventRegistry = EventRegistry.new()
```

2. Замінити `_deserialize_command()` на використання реєстру:
```gdscript
func _deserialize_command(data: Dictionary) -> Command:
	return command_registry.deserialize(data)
```

3. Замінити `_deserialize_event()` на використання реєстру:
```gdscript
func _deserialize_event(data: Dictionary) -> Event:
	return event_registry.deserialize(data)
```

4. Додати метод `_register_all_commands()` для реєстрації всіх команд:
```gdscript
func _register_all_commands() -> void:
	# Register all command types
	command_registry.register_command_type("pickup_item_command", PickupItemCommand.deserialize)
	command_registry.register_command_type("drop_item_command", DropItemCommand.deserialize)
	# ... (всі інші команди)
```

5. Додати метод `_register_all_events()` для реєстрації всіх подій:
```gdscript
func _register_all_events() -> void:
	# Register all event types
	event_registry.register_event_type("item_picked", ItemPickedEvent.deserialize)
	event_registry.register_event_type("item_dropped", ItemDroppedEvent.deserialize)
	# ... (всі інші події)
```

6. Викликати реєстрацію в `_ready()`:
```gdscript
func _ready() -> void:
	_register_all_commands()
	_register_all_events()
```

**Критерії готовності:**
- [x] CommandBus використовує реєстри замість match блоків
- [x] Всі команди реєструються в `_register_all_commands()`
- [x] Всі події реєструються в `_register_all_events()`
- [x] Старі match блоки видалені
- [x] Тестування пройдено (синглплеєр + мультиплеєр)

#### Крок 1.4: Тестування
1. Перевірити, що всі команди десеріалізуються правильно
2. Перевірити, що всі події десеріалізуються правильно
3. Перевірити в синглплеєрі - все працює
4. Перевірити в мультиплеєрі - синхронізація працює
5. Перевірити, що додавання нової команди/події не вимагає змін у CommandBus

**Оцінка часу:** 3-4 години

---

### Етап 2: Event Handler System

**Мета:** Видалити жорстко закодовані обробники подій (`_handle_turnwheel_event`, `_handle_door_event`)

**Симптоми:**
- CommandBus знає про конкретні типи об'єктів (turnwheel, door)
- Дублювання коду між обробниками
- Неможливо додати новий обробник без модифікації CommandBus
- Порушення Single Responsibility Principle

**Рішення:**
1. Створити базовий клас `EventHandler`
2. Створити конкретні обробники: `TurnwheelEventHandler`, `DoorEventHandler`
3. Реєструвати обробники в CommandBus
4. Видалити жорстко закодовані методи

**Детальні кроки:**

#### Крок 2.1: Створити базовий клас EventHandler
**Файл:** `addons/cogito/network/commands/handlers/event_handler.gd`

```gdscript
extends RefCounted
class_name EventHandler
## Base class for event handlers.
## Each handler is responsible for processing a specific event type.

## Event type this handler processes
var event_type: String = ""

## Process an event
## event: Event to process
func handle(event: Event) -> void:
	push_error("EventHandler.handle() must be overridden in subclass")
```

**Критерії готовності:**
- [ ] Клас створено та зареєстровано як `class_name`
- [ ] Метод `handle()` визначено
- [ ] Тестування пройдено

#### Крок 2.2: Створити TurnwheelEventHandler
**Файл:** `addons/cogito/network/commands/handlers/turnwheel_event_handler.gd`

```gdscript
extends EventHandler
class_name TurnwheelEventHandler
## Handler for TurnwheelInteractedEvent.
## Handles visual replication of turnwheel interactions on remote clients.

func _init():
	event_type = "turnwheel_interacted"

func handle(event: Event) -> void:
	if not event is TurnwheelInteractedEvent:
		push_error("TurnwheelEventHandler: Expected TurnwheelInteractedEvent, got %s" % event.get_class())
		return
	
	var turnwheel_event = event as TurnwheelInteractedEvent
	_process_turnwheel_event(turnwheel_event)

func _process_turnwheel_event(event: TurnwheelInteractedEvent) -> void:
	# Move logic from CommandBus._handle_turnwheel_event() here
	# Use strict typing (event.turnwheel_path instead of "turnwheel_path" in event)
	# ...
```

**Критерії готовності:**
- [x] Клас створено та наслідує EventHandler
- [x] Логіка з `_handle_turnwheel_event()` перенесена
- [x] Використовується строга типізація
- [x] Тестування пройдено

#### Крок 2.3: Створити DoorEventHandler
**Файл:** `addons/cogito/network/commands/handlers/door_event_handler.gd`

```gdscript
extends EventHandler
class_name DoorEventHandler
## Handler for DoorInteractedEvent.
## Handles visual replication of door interactions on remote clients.

func _init():
	event_type = "door_interacted"

func handle(event: Event) -> void:
	if not event is DoorInteractedEvent:
		push_error("DoorEventHandler: Expected DoorInteractedEvent, got %s" % event.get_class())
		return
	
	var door_event = event as DoorInteractedEvent
	_process_door_event(door_event)

func _process_door_event(event: DoorInteractedEvent) -> void:
	# Move logic from CommandBus._handle_door_event() here
	# Use strict typing (event.door_path instead of "door_path" in event)
	# ...
```

**Критерії готовності:**
- [x] Клас створено та наслідує EventHandler
- [x] Логіка з `_handle_door_event()` перенесена
- [x] Використовується строга типізація
- [x] Тестування пройдено

#### Крок 2.4: Модифікувати CommandBus для використання обробників
**Зміни в `command_bus.gd`:**

1. Додати поле для реєстрації обробників:
```gdscript
var _event_handlers_registry: Dictionary = {}  # event_type -> EventHandler
```

2. Додати метод реєстрації обробників:
```gdscript
func register_event_handler(handler: EventHandler) -> void:
	_event_handlers_registry[handler.event_type] = handler
```

3. Замінити `_handle_turnwheel_event()` та `_handle_door_event()` на загальний метод:
```gdscript
func _process_event_for_replication(event: Event) -> void:
	var handler = _event_handlers_registry.get(event.event_type)
	if handler:
		handler.handle(event)
```

4. Оновити `receive_validated_command()` для використання обробників:
```gdscript
# Замість:
if event_type == "turnwheel_interacted":
	_handle_turnwheel_event(event)
elif event_type == "door_interacted":
	_handle_door_event(event)

# Використати:
_process_event_for_replication(event)
```

5. Видалити старі методи `_handle_turnwheel_event()` та `_handle_door_event()`

6. Додати реєстрацію обробників в `_ready()`:
```gdscript
func _ready() -> void:
	_register_all_commands()
	_register_all_events()
	_register_all_event_handlers()

func _register_all_event_handlers() -> void:
	register_event_handler(TurnwheelEventHandler.new())
	register_event_handler(DoorEventHandler.new())
```

**Критерії готовності:**
- [x] CommandBus використовує реєстровані обробники
- [x] Старі методи `_handle_*_event()` видалені
- [x] Всі обробники реєструються в `_register_all_event_handlers()`
- [x] Тестування пройдено (синглплеєр + мультиплеєр)

**Оцінка часу:** 4-5 годин

---

### Етап 3: Строга типізація подій

**Мета:** Замінити runtime перевірки на compile-time перевірки

**Симптоми:**
- Використання `"property_name" in event` для перевірки властивостей
- Використання `event.property_name` без типізації
- Неможливість compile-time перевірок

**Рішення:**
1. Використовувати строгу типізацію для подій
2. Замінити `"property_name" in event` на прямі звернення
3. Використовувати `class_name` для типізації

**Кроки:**
1. Оновити `_handle_turnwheel_event()` для використання типізованих подій
2. Оновити `_handle_door_event()` для використання типізованих подій
3. Видалити всі `"property_name" in event` перевірки
4. Тестування

**Оцінка часу:** 2-3 години

---

### Етап 4: Покращення ResponseHandler

**Мета:** Виправити жорстко закодовані обробники в ResponseHandler

**Симптоми:**
- Match блок для обробки кожного ResponseCode
- Дублювання даних між `_log_levels` та `_code_messages`

**Рішення:**
1. Об'єднати `_log_levels` та `_code_messages` в одну структуру
2. Використати реєстрацію обробників замість match блоку

**Кроки:**
1. Створити структуру даних для ResponseCode (log_level + message)
2. Об'єднати `_log_levels` та `_code_messages`
3. Замінити match блок на реєстрацію обробників (опціонально)
4. Тестування

**Оцінка часу:** 2-3 години

---

### Етап 5: Покращення команд (runtime перевірки)

**Мета:** Замінити runtime перевірки на compile-time перевірки

**Симптоми:**
- Використання `"property_name" in object` для перевірки властивостей
- Runtime перевірки типів

**Рішення:**
1. Використовувати строгу типізацію
2. Замінити runtime перевірки на compile-time перевірки

**Кроки:**
1. Оновити всі команди для використання строгої типізації
2. Видалити `"property_name" in object` перевірки
3. Тестування

**Оцінка часу:** 3-4 години

---

### Етап 6: Покращення ID генераторів (опціонально)

**Мета:** Покращити генерацію ID для команд та подій

**Симптоми:**
- Простий ID генератор (може бути колізії)
- Використання timestamp + random

**Рішення:**
1. Використати UUID для генерації ID
2. Або залишити як є, якщо достатньо

**Кроки:**
1. Створити `uuid_generator.gd` (опціонально)
2. Оновити `_generate_id()` в Command та Event
3. Тестування

**Оцінка часу:** 1-2 години

---

## 📊 Загальний прогрес

**Завершено:** ✅ 2/6 етапів (33%)  
**Поточний статус:** Етап 1 та 2 завершені, готовий до Етапу 3

### Детальний прогрес:

**Етап 1: Реєстрація обробників для CommandBus** - ✅ 100% ЗАВЕРШЕНО
- ✅ Створено CommandRegistry клас
- ✅ Створено EventRegistry клас
- ✅ Модифіковано CommandBus для використання реєстрів
- ✅ Видалено величезні match блоки (30+ рядків кожен)
- ✅ Тестування пройдено (синглплеєр + мультиплеєр)

**Етап 2: Event Handler System** - ✅ 100% ЗАВЕРШЕНО
- ✅ Створено базовий клас EventHandler
- ✅ Створено TurnwheelEventHandler
- ✅ Створено DoorEventHandler
- ✅ Модифіковано CommandBus для використання обробників
- ✅ Видалено старі методи `_handle_turnwheel_event()` та `_handle_door_event()`
- ✅ Тестування пройдено (синглплеєр + мультиплеєр)

**Етап 3: Строга типізація подій** - ⏸️ 0% (готовий до виконання)

**Етап 4: Покращення ResponseHandler** - ⏸️ 0%

**Етап 5: Покращення команд (runtime перевірки)** - ⏸️ 0%

**Етап 6: Покращення ID генераторів** - ⏸️ 0% (опціонально)

---

## 🎯 Наступні кроки

1. **Почати з Етапу 1** - найкритичніший (CommandBus реєстрація)
2. **Продовжити з Етапу 2** - видалення жорстко закодованих обробників
3. **Етап 3-6** - покращення типізації та інших аспектів

---

## ⚠️ Важливі зауваження

- **Не ламати існуючий функціонал** - кожен етап має бути протестований
- **Поступовість** - робити по одному етапу за раз
- **Тестування** - після кожного етапу перевіряти в синглплеєрі та мультиплеєрі
- **Backward compatibility** - зберігати сумісність з існуючим кодом

---

## 📝 Нотатки

- Рефакторинг має бути поступовим та не ламати існуючий функціонал
- Кожен етап має бути незалежним та тестованим
- Пріоритет на SOLID принципах та строгій типізації

---

## 📊 Summary

### Поточний стан
- **31 файл** в системі команд/подій
- **Основні проблеми:**
  - CommandBus порушує Open/Closed Principle (величезні match блоки)
  - Runtime перевірки замість compile-time
  - Жорстко закодовані обробники подій
  - Відсутність строгої типізації в деяких місцях

### План рефакторингу
- **6 етапів** поступового покращення
- **Пріоритет:** Етап 1 (CommandBus) → Етап 2 (Event Handlers) → Етап 3-6 (покращення типізації)
- **Оцінка часу:** 15-20 годин загалом

### Очікувані результати
- ✅ Дотримання SOLID принципів
- ✅ Строга типізація (compile-time перевірки)
- ✅ Легкість додавання нових команд/подій без модифікації CommandBus
- ✅ Чистіший та підтримуваніший код
- ✅ Дотримання Godot конвенцій

