# Network System - Підготовка до мультиплеєру

## Автолоади

Ця система використовує два автолоади:

1. **NetworkEventBus** - централізована система подій
2. **PlayerManager** - менеджер для управління гравцями

## Важливо!

**НЕ використовуйте `class_name` для автолоадів!**

Автолоади реєструються через:
- `cogito_plugin.gd` (для автоматичної реєстрації)
- `project.godot` (вручну, якщо потрібно)

Автолоади доступні глобально після завантаження проекту.

## Використання

### NetworkEventBus
```gdscript
# Підписка на події
NetworkEventBus.player_registered.connect(_on_player_registered)

# Емісія подій
NetworkEventBus.emit_player_registered(player_id, player_node)
```

### PlayerManager
```gdscript
# Реєстрація гравця
var player_id = PlayerManager.register_player(self, true)  # true = is_local_player

# Отримання гравця
var local_player = PlayerManager.get_local_player()
var player = PlayerManager.get_player(player_id)

# Дереєстрація
PlayerManager.unregister_player(player_id)
```

## Вирішення помилок

Якщо виникає помилка "Cannot call non-static function on the class":
1. Переконайтеся, що `class_name` прибрано з файлу автолоаду
2. Переконайтеся, що автолоад додано в `project.godot`
3. Перезапустіть Godot Editor
4. Перевірте порядок завантаження автолоадів

Якщо виникає помилка "name is not unique":
1. Перевірте, чи немає дублікатів в `project.godot`
2. Перевірте, чи правильно зареєстровано в `cogito_plugin.gd`
3. Видаліть стару реєстрацію, якщо вона є

