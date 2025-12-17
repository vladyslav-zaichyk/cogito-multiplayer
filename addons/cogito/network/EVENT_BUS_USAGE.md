# NetworkEventBus - Документація використання

## Огляд

`NetworkEventBus` - це централізована система подій для декаплінгу систем та підготовки до мультиплеєру. Вона дозволяє компонентам спілкуватися без прямих залежностей.

## Реєстрація

Event Bus автоматично реєструється як автолоад `NetworkEventBus` при завантаженні плагіна Cogito.

## Категорії подій

### Player Events
Події, пов'язані з гравцями:
- `player_registered(player_id: int, player_node: Node)` - гравець зареєстрований
- `player_unregistered(player_id: int)` - гравець дереєстрований
- `player_spawned(player_id: int, position: Vector3)` - гравець з'явився в світі
- `player_died(player_id: int)` - гравець помер
- `player_moved(player_id: int, position: Vector3, rotation: Vector3)` - гравець рухається
- `player_input(player_id: int, action: String, pressed: bool)` - гравець виконав дію

### Inventory Events
Події, пов'язані з інвентарем:
- `inventory_item_picked(player_id: int, item: InventoryItemPD, slot_data: InventorySlotPD)` - предмет піднято
- `inventory_item_dropped(player_id: int, item: InventoryItemPD, position: Vector3)` - предмет скинуто
- `inventory_changed(player_id: int, inventory: CogitoInventory)` - інвентар змінився
- `inventory_item_used(player_id: int, item: InventoryItemPD)` - предмет використано
- `item_equipped(player_id: int, item: InventoryItemPD, quickslot_index: int)` - предмет екіпіровано
- `item_unequipped(player_id: int, quickslot_index: int)` - предмет знято

### Quest Events
Події, пов'язані з квестами:
- `quest_started(player_id: int, quest: CogitoQuest)` - квест розпочато
- `quest_completed(player_id: int, quest: CogitoQuest)` - квест завершено
- `quest_updated(player_id: int, quest: CogitoQuest)` - квест оновлено
- `quest_failed(player_id: int, quest: CogitoQuest)` - квест провалено

### World Events
Події, пов'язані зі світом:
- `world_state_changed(key: String, value: Variant, old_value: Variant)` - світовий стан змінився
- `scene_changed(scene_path: String, scene_name: String)` - сцена змінилася
- `scene_changing(from_scene: String, to_scene: String)` - сцена змінюється

### Interaction Events
Події, пов'язані з взаємодією:
- `interaction_started(player_id: int, target: Node, interaction_type: String)` - взаємодія розпочата
- `interaction_completed(player_id: int, target: Node, interaction_type: String)` - взаємодія завершена
- `interaction_cancelled(player_id: int, target: Node)` - взаємодія скасована

### Attribute Events
Події, пов'язані з атрибутами гравця:
- `attribute_changed(player_id: int, attribute_name: String, current_value: float, max_value: float)` - атрибут змінився
- `attribute_reached_zero(player_id: int, attribute_name: String)` - атрибут досяг нуля

### Network Events (для майбутнього мультиплеєру)
- `network_connected(peer_id: int)` - підключення до мережі
- `network_disconnected(peer_id: int)` - відключення від мережі
- `network_error(error: String)` - помилка мережі

## Приклади використання

### Підписка на події

```gdscript
func _ready() -> void:
    # Підписка на подію реєстрації гравця
    NetworkEventBus.player_registered.connect(_on_player_registered)
    
    # Підписка на подію зміни інвентаря
    NetworkEventBus.inventory_changed.connect(_on_inventory_changed)


func _on_player_registered(player_id: int, player_node: Node) -> void:
    print("Player %d registered: %s" % [player_id, player_node.name])


func _on_inventory_changed(player_id: int, inventory: CogitoInventory) -> void:
    print("Inventory changed for player %d" % player_id)
```

### Емісія подій

```gdscript
# Емісія події через сигнал
NetworkEventBus.player_registered.emit(player_id, player_node)

# Або через зручні методи
NetworkEventBus.emit_player_registered(player_id, player_node)
NetworkEventBus.emit_inventory_changed(player_id, inventory)
NetworkEventBus.emit_world_state_changed("key", value, old_value)
```

### Відписка від подій

```gdscript
func _exit_tree() -> void:
    NetworkEventBus.player_registered.disconnect(_on_player_registered)
    NetworkEventBus.inventory_changed.disconnect(_on_inventory_changed)
```

## Логування подій

Для увімкнення логування подій (корисно для дебагу):

```gdscript
NetworkEventBus.enable_event_logging = true
```

Це виведе в консоль інформацію про всі емітовані події.

## Переваги використання Event Bus

1. **Декаплінг систем** - компоненти не залежать один від одного напряму
2. **Підготовка до мультиплеєру** - події можна легко синхронізувати між клієнтами
3. **Легке тестування** - можна легко підписуватися на події для тестування
4. **Централізоване логування** - всі події можна логувати в одному місці
5. **Гнучкість** - легко додавати нові події без зміни існуючого коду

## Міграція зі старих систем

Замість прямого доступу до синглтонів:
```gdscript
# Старий спосіб
CogitoSceneManager._current_player_node.some_method()

# Новий спосіб через Event Bus
NetworkEventBus.player_registered.connect(_on_player_registered)
```

## Майбутні покращення

- [ ] Додати підтримку фільтрів подій
- [ ] Додати підтримку відкладених подій
- [ ] Додати підтримку приоритетів подій
- [ ] Додати підтримку синхронізації подій в мультиплеєрі

