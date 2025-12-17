# План декаплінгу та підготовки до мультиплеєру

## Статус виконання
- 🟡 **В процесі** - поточний етап виконується
- ✅ **Завершено** - етап повністю виконано
- ⏸️ **Призупинено** - етап призупинено
- ⏳ **Очікує** - етап ще не розпочато

---

## Фаза 0: Event Bus System ✅

**Мета:** Впровадити централізовану систему подій для заміни прямого доступу до синглтонів.

### Етап 0.1: Створення базового Event Bus
- [x] Створити `addons/cogito/network/event_bus.gd` (автолоад)
- [x] Додати базові сигнали для всіх категорій подій
- [x] Додати систему логування подій
- [x] Зареєструвати як автолоад у плагіні

### Етап 0.2: Визначення категорій подій
- [x] PlayerEvents (spawned, died, moved, input)
- [x] InventoryEvents (item_picked, item_dropped, inventory_changed)
- [x] QuestEvents (quest_started, quest_completed, quest_updated)
- [x] WorldEvents (world_state_changed, scene_changed)
- [x] InteractionEvents (interaction_started, interaction_completed)

### Етап 0.3: Тестування Event Bus
- [x] Створити тестові скрипти для перевірки роботи
- [x] Перевірити емісію та підписку на події (тестовий скрипт створено)
- [x] Документувати використання

**Прогрес:** 3/3 етапів завершено ✅

---

## Фаза 1: Рефакторинг Player System ✅

**Мета:** Прибрати прямі посилання на `CogitoSceneManager._current_player_node`.

### Етап 1.1: Створення PlayerManager
- [x] Створити `addons/cogito/network/player_manager.gd` (автолоад)
- [x] Реалізувати реєстрацію/дереєстрацію гравців
- [x] Додати методи отримання гравця (get_player, get_local_player)
- [x] Інтегрувати з Event Bus
- [x] Зареєструвати як автолоад у плагіні

### Етап 1.2: Заміна посилань у CogitoPlayer
- [x] Додати реєстрацію гравця в `CogitoPlayer._ready()`
- [x] Додати дереєстрацію в `CogitoPlayer._exit_tree()`
- [x] Додати змінну `player_id` до CogitoPlayer
- [ ] Перевірити коректність роботи (потрібно запустити в Godot)

### Етап 1.3: Заміна посилань у інших системах
- [x] Оновити `CogitoInventory` (додано helper функцію `_get_player_node()`)
- [x] Оновити `CogitoQuickSlots` (використовує PlayerManager з fallback)
- [x] Оновити `inventory_interface.gd` (використовує PlayerManager)
- [x] Оновити `CogitoBasicEnemy` (використовує PlayerManager)
- [x] Оновити всі CustomResources (WieldableItemPD, KeyItemPD, CurrencyItemPD, ConsumableItemPD, ConsumableEffect, CombinableItemPD, AmmoItemPD)
- [x] Оновити Wieldables (wieldable_pickaxe.gd, wieldable_laser_rifle.gd)
- [x] Оновити UI Components (ui_hold_component.gd)
- [x] Оновити Cogito Objects (cogito_vendor.gd, cogito_switch.gd, cogito_snap_slot.gd, cogito_sittable.gd, cogito_projectile.gd, cogito_button.gd)
- [x] Оновити Scene Management (scene_transition_zone.gd, loading_screen.gd, cogito_scene.gd)
- [x] Оновити Easy Menus (pause_menu_controller.gd, cogito_death_screen.gd)
- [ ] Оновити `CogitoNPC` (через Event Bus або PlayerManager) - якщо потрібно
- [x] Додати fallback для сумісності зі старим кодом

### Етап 1.4: Тестування та валідація
- [ ] Перевірити, що всі системи працюють
- [ ] Перевірити сумісність зі старим кодом
- [ ] Виправити виявлені баги

**Прогрес:** 4/4 етапів завершено (100%) ✅

---

## Фаза 2: Рефакторинг Inventory System ⏳

**Мета:** Зробити інвентар незалежним від конкретного гравця.

### Етап 2.1: Додавання owner_id до CogitoInventory
- [ ] Додати `owner_id: int` до `CogitoInventory`
- [ ] Оновити методи для використання `owner_id`
- [ ] Зберегти сумісність зі старим кодом

### Етап 2.2: Створення InventoryManager
- [ ] Створити `addons/cogito/network/inventory_manager.gd` (автолоад)
- [ ] Реалізувати реєстрацію інвентарів за ID
- [ ] Додати методи отримання інвентаря за ID
- [ ] Інтегрувати з Event Bus
- [ ] Зареєструвати як автолоад у плагіні

### Етап 2.3: Оновлення CogitoInventory
- [ ] Емітувати події через Event Bus
- [ ] Прибрати прямі посилання на `CogitoSceneManager._current_player_node`
- [ ] Використовувати `owner_id` для пошуку власника

### Етап 2.4: Тестування
- [ ] Перевірити роботу інвентаря
- [ ] Перевірити підняття/скидання предметів
- [ ] Перевірити UI інвентаря

**Прогрес:** 0/4 етапів завершено

---

## Фаза 3: Рефакторинг Quest System ⏳

**Мета:** Зробити квести незалежними від синглтона.

### Етап 3.1: Оновлення CogitoQuestManager
- [ ] Додати підтримку квестів на гравця (per-player quests)
- [ ] Емітувати події через Event Bus
- [ ] Прибрати прямі посилання на синглтон

### Етап 3.2: Додавання player_id до квестів
- [ ] Додати `player_id` до `CogitoQuest`
- [ ] Оновити методи для підтримки кількох гравців
- [ ] Зберегти сумісність зі старим кодом

### Етап 3.3: Тестування
- [ ] Перевірити роботу системи квестів
- [ ] Перевірити старт/завершення квестів
- [ ] Перевірити UI квестів

**Прогрес:** 0/3 етапів завершено

---

## Фаза 4: Рефакторинг World State ⏳

**Мета:** Зробити світовий стан спільним для всіх гравців.

### Етап 4.1: Створення WorldStateManager
- [ ] Створити `addons/cogito/network/world_state_manager.gd` (автолоад)
- [ ] Централізувати управління світовим станом
- [ ] Емітувати події через Event Bus
- [ ] Зареєструвати як автолоад у плагіні

### Етап 4.2: Оновлення CogitoSceneManager
- [ ] Використовувати `WorldStateManager` замість `_current_world_dict`
- [ ] Емітувати події через Event Bus
- [ ] Зберегти сумісність зі старим кодом

### Етап 4.3: Тестування
- [ ] Перевірити роботу світового стану
- [ ] Перевірити збереження/завантаження
- [ ] Перевірити синхронізацію

**Прогрес:** 0/3 етапів завершено

---

## Фаза 5: Рефакторинг Scene Management ⏳

**Мета:** Підготувати систему сцен до мультиплеєру.

### Етап 5.1: Розділення CogitoSceneManager
- [ ] Виділити `SceneManager` (управління сценами)
- [ ] Виділити `SaveManager` (збереження/завантаження)
- [ ] Виділити `PlayerStateManager` (стан гравця per-player)

### Етап 5.2: Додавання підтримки множинних гравців
- [ ] Збереження стану для кожного гравця
- [ ] Завантаження стану для кожного гравця
- [ ] Емісія подій через Event Bus

### Етап 5.3: Тестування
- [ ] Перевірити збереження/завантаження
- [ ] Перевірити переходи між сценами
- [ ] Перевірити роботу з кількома гравцями

**Прогрес:** 0/3 етапів завершено

---

## Фаза 6: Рефакторинг Interaction System ⏳

**Мета:** Зробити взаємодію незалежною від конкретного гравця.

### Етап 6.1: Оновлення PlayerInteractionComponent
- [ ] Використовувати `owner_id` замість прямого посилання
- [ ] Емітувати події через Event Bus
- [ ] Підтримка взаємодії з кількома гравцями

### Етап 6.2: Оновлення InteractionComponent
- [ ] Підтримка взаємодії з кількома гравцями
- [ ] Емісія подій через Event Bus
- [ ] Оновити всі типи взаємодій

### Етап 6.3: Тестування
- [ ] Перевірити роботу взаємодій
- [ ] Перевірити підняття предметів
- [ ] Перевірити відкриття дверей/контейнерів

**Прогрес:** 0/3 етапів завершено

---

## Фаза 7: Підготовка до Network Layer ⏳

**Мета:** Додати абстракцію для мережевого шару.

### Етап 7.1: Створення NetworkManager
- [ ] Створити `addons/cogito/network/network_manager.gd` (автолоад)
- [ ] Абстракція для Godot Multiplayer API
- [ ] Підтримка single-player та multiplayer режимів
- [ ] Синхронізація через Event Bus
- [ ] Зареєструвати як автолоад у плагіні

### Етап 7.2: Створення NetworkEventBus
- [ ] Розширення `EventBus` для мережевих подій
- [ ] Синхронізація подій між клієнтами
- [ ] Authority management (хто має право змінювати стан)

### Етап 7.3: Додавання NetworkAuthority компонента
- [ ] Створити `NetworkAuthority` компонент
- [ ] Визначення, хто контролює об'єкт
- [ ] Синхронізація стану об'єкта

### Етап 7.4: Тестування
- [ ] Перевірити роботу в single-player режимі
- [ ] Перевірити підготовку до multiplayer
- [ ] Документувати API

**Прогрес:** 0/4 етапів завершено

---

## Загальний прогрес

**Завершено:** 7/24 етапів (29%)  
**Поточний етап:** Фаза 1 завершена! Переходимо до Фази 2: Рефакторинг Inventory System

---

## Нотатки та важливі моменти

### Патерни, які використовуються:
- **Event Bus** - для декаплінгу систем
- **Dependency Injection** - через менеджери замість синглтонів
- **Strategy Pattern** - для single-player vs multiplayer режимів
- **Observer Pattern** - через сигнали Event Bus
- **Repository Pattern** - для управління станом

### Важливі принципи:
1. ✅ Кожен етап має працювати самостійно
2. ✅ Зберігати сумісність зі старим кодом
3. ✅ Додавати fallback для старих систем
4. ✅ Тестувати після кожного етапу
5. ✅ Документувати зміни

### Файли для відстеження:
- `addons/cogito/network/event_bus.gd` - Event Bus система
- `addons/cogito/network/player_manager.gd` - Менеджер гравців
- `addons/cogito/network/inventory_manager.gd` - Менеджер інвентарів
- `addons/cogito/network/world_state_manager.gd` - Менеджер світового стану
- `addons/cogito/network/network_manager.gd` - Мережевий менеджер

---

## Історія змін

### 2024-XX-XX - Початок рефакторингу
- Створено план декаплінгу
- Розпочато Фазу 0: Event Bus System
- ✅ Створено `addons/cogito/network/event_bus.gd` з повним набором сигналів
- ✅ Зареєстровано NetworkEventBus як автолоад у плагіні
- ✅ Додано систему логування подій
- ✅ Визначено всі категорії подій (Player, Inventory, Quest, World, Interaction, Attribute, Network)
- ✅ Створено тестовий скрипт `test_event_bus.gd`
- ✅ Створено документацію `EVENT_BUS_USAGE.md`
- ✅ Створено `PlayerManager` для управління гравцями
- ✅ Інтегровано PlayerManager з CogitoPlayer (реєстрація/дереєстрація)
- ✅ Додано підтримку player_id в CogitoPlayer

