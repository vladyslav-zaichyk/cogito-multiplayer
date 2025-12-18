# 🎯 ViewModel / WorldModel Architecture Plan

## Проблема
Поточна реалізація синхронізації wieldables має фундаментальну архітектурну проблему:
- **ViewModel** (те, що бачить локальний гравець) синхронізується напряму
- Це призводить до проблем з орієнтацією, рухом, анімаціями
- Неможливо правильно синхронізувати FPS-камеру та присідання
- Wieldable "літає" в повітрі або має неправильну орієнтацію для віддалених гравців

## Рішення: Розділення ViewModel та WorldModel

### Архітектура (як в CS2, Valorant, CoD)

**A. Local View (ViewModel / First Person)**
- Руки та зброя високої деталізації, "приклеєні" до камери
- Можуть мати спотворену перспективу (FOV hack)
- **НІКОЛИ не синхронізується** - існує тільки локально
- Використовує існуючу систему `wieldable_container` під `Head/Eyes/Camera`

**B. World View (WorldModel / Third Person)**
- Спрощена модель зброї (Low Poly), прикріплена до кістки руки або капсули
- Синхронізується тільки **ID предмета** ("Гравець X тримає предмет Y")
- Автоматично рухається з моделлю гравця (капсулою)
- Не потребує синхронізації Transform - все через ієрархію сцени

---

## Фаза 1: Підготовка ресурсів (Data Layer)

### 1.1 Розширення WieldableItemPD
- [ ] Додати поле `world_model_scene: PackedScene` до `WieldableItemPD`
- [ ] Для MVP: використовувати ту саму сцену, що і `dropped_pickup_scene`, але без колізії
- [ ] Створити окремі спрощені моделі для WorldModel (опціонально, для майбутнього)
- [ ] Додати fallback: якщо `world_model_scene` не встановлено, використовувати `dropped_pickup_scene`

**Файл:** `addons/cogito/inventory_pd/CustomResources/WieldableItemPD.gd`

### 1.2 Оновлення синхронізації
- [ ] Змінити `NetworkWieldableSync` - синхронізувати тільки `item_id` (String/Int)
- [ ] Видалити синхронізацію Transform/Position для wieldables
- [ ] Оновити RPC `sync_wieldable_change` - передавати тільки ID, не дані про об'єкт
- [ ] Оновити `_serialize_wieldable` - повертати тільки ID/name, не resource_path

**Файл:** `addons/cogito/network/network_wieldable_sync.gd`

### 1.3 Оновлення PlayerData
- [ ] Додати поле `current_wielded_item_id: String` до `PlayerData`
- [ ] Синхронізувати це поле через існуючу систему `sync_player_data`
- [ ] Оновити `PlayerManager` для відстеження змін `current_wielded_item_id`

**Файли:** 
- `addons/cogito/network/player_data.gd`
- `addons/cogito/network/player_manager.gd`

---

## Фаза 2: Створення WorldModel системи (Visual Layer)

### 2.1 PlayerVisualRepresentation - Hand Socket
- [ ] Додати `Node3D` (або `Marker3D`) до `PlayerVisualRepresentation`
- [ ] Назвати `RightHandSocket` або `HandHolder`
- [ ] Розмістити трохи вперед і вправо від центру капсули
- [ ] Для майбутнього: замінити на `BoneAttachment3D` коли буде модель з кістками
- [ ] Встановити правильну орієнтацію (можливо, потрібен поворот на 180°)

**Файл:** `addons/cogito/network/player_visual_representation.gd`

**Примітка:** Можна додати через код в `_ready()`, або через сцену `cogito_player.tscn`

### 2.2 WorldModel Manager компонент
- [ ] Створити `WorldModelWieldableSync` компонент
- [ ] Підписатися на зміну `current_wielded_item_id` в `PlayerData`
- [ ] Логіка:
  - Якщо ID змінився (наприклад, з "empty" на "pistol"):
    - Видалити все з `RightHandSocket`
    - Завантажити `world_model_scene` для нового ID
    - Зробити `instantiate()` і додати як child до `RightHandSocket`
    - Вимкнути фізику/колізію для WorldModel (якщо використовується pickup сцена)
    - Встановити правильну орієнтацію (можливо, потрібен поворот)
- [ ] Обробка помилок: якщо сцена не знайдена, використати fallback

**Новий файл:** `addons/cogito/network/world_model_wieldable_sync.gd`

### 2.3 Інтеграція з PlayerVisualRepresentation
- [ ] Додати `WorldModelWieldableSync` до `PlayerVisualRepresentation`
- [ ] Переконатися, що компонент працює тільки для віддалених гравців
- [ ] Локальний гравець використовує ViewModel (існуюча система)
- [ ] Додати компонент динамічно в `_ready()` або через сцену

**Файл:** `addons/cogito/network/player_visual_representation.gd`

---

## Фаза 3: Очищення поточної реалізації

### 3.1 Видалення старої синхронізації
- [ ] Видалити синхронізацію Transform з `NetworkWieldableSync`
- [ ] Видалити спавн wieldable в `wieldable_container` для віддалених гравців
- [ ] Залишити тільки синхронізацію ID
- [ ] Видалити виклики `equip()` для віддалених гравців
- [ ] Видалити seek до кінця анімації

**Файл:** `addons/cogito/network/network_wieldable_sync.gd`

### 3.2 Оновлення PlayerInteractionComponent
- [ ] Переконатися, що `equip_wieldable()` працює тільки для локального гравця
- [ ] Оновити `update_wieldable_data()` - оновлювати `PlayerData.current_wielded_item_id`
- [ ] Видалити залежність від синхронізації Transform

**Файл:** `addons/cogito/Components/player_interaction_component.gd`

### 3.3 Тестування
- [ ] Перевірити, що локальний гравець бачить ViewModel (як зараз)
- [ ] Перевірити, що віддалені гравці бачать WorldModel в правильній позиції
- [ ] Перевірити синхронізацію присідання (WorldModel має рухатися з капсулою)
- [ ] Перевірити синхронізацію поворотів (WorldModel має повертатися з капсулою)
- [ ] Перевірити екіпірування/зняття зброї

---

## Фаза 4: Покращення (Post-MVP)

### 4.1 Анімації (опціонально)
- [ ] Додати Generic Pose анімацію "Тримаю щось двома руками"
- [ ] Використати SkeletonIK3D для автоматичного позиціонування рук
- [ ] Одна анімація працює для всіх предметів

### 4.2 Оптимізація
- [ ] Створити окремі Low Poly моделі для WorldModel
- [ ] LOD система для віддалених гравців
- [ ] Кешування завантажених сцен

### 4.3 Додаткові покращення
- [ ] Синхронізація стану зброї (наприклад, чи увімкнено ліхтарик)
- [ ] Синхронізація анімацій використання (постріл, перезарядка)
- [ ] Проджектайли через MultiplayerSpawner

---

## Технічні деталі

### Структура компонентів:
```
CogitoPlayer (локальний гравець)
├── Body/Neck/Head/Wieldables (ViewModel - не синхронізується)
│   └── [Wieldable instance для локального гравця]
└── NetworkWieldableSync (синхронізує тільки ID)

CogitoPlayer (віддалений гравець)
├── PlayerVisualRepresentation
│   ├── RightHandSocket (Node3D/Marker3D)
│   │   └── [WorldModel wieldable instance]
│   └── WorldModelWieldableSync (компонент)
└── NetworkWieldableSync (отримує ID, не спавнить wieldable)
```

### Data Flow:
1. Локальний гравець екіпірує зброю → `PlayerData.current_wielded_item_id` оновлюється
2. `NetworkWieldableSync` синхронізує тільки ID через RPC
3. Всі клієнти отримують ID
4. `WorldModelWieldableSync` на кожному клієнті бачить зміну ID
5. Компонент завантажує та спавнить WorldModel в `RightHandSocket`
6. WorldModel автоматично рухається з капсулою (через ієрархію сцени)

### Переваги:
- ✅ Чиста архітектура (Data Layer окремо від Visual Layer)
- ✅ Не потрібно синхронізувати Transform
- ✅ Автоматично працює з присіданням та рухом
- ✅ Автоматично працює з поворотами (через ієрархію сцени)
- ✅ Легко замінити на BoneAttachment3D в майбутньому
- ✅ Не потрібно переписувати код при додаванні моделі з кістками
- ✅ Менше мережевого трафіку (тільки ID, не Transform)

### Потенційні проблеми:
- ⚠️ Можливо, потрібна ручна корекція орієнтації для WorldModel
- ⚠️ Потрібно переконатися, що `world_model_scene` правильно налаштована
- ⚠️ Можливо, потрібно вимкнути анімації для WorldModel

---

## Пріоритет
**🔴 Високий** - Це фундаментальна архітектурна зміна, яка вирішить поточні проблеми з wieldables sync.

## Залежності
- Phase 2.2 Wieldables Sync (поточна реалізація) - потрібно замінити
- PlayerVisualRepresentation - потрібно розширити
- WieldableItemPD - потрібно додати поле `world_model_scene`
- PlayerData - потрібно додати поле `current_wielded_item_id`

## Оцінка часу
- **Фаза 1:** 2-3 години (розширення ресурсів, оновлення синхронізації)
- **Фаза 2:** 3-4 години (створення WorldModel системи)
- **Фаза 3:** 1-2 години (очищення, тестування)
- **Всього:** ~6-9 годин для MVP реалізації

---

## Посилання на проблеми
- `WIELDABLES_SYNC_BUGS.md` - список багів поточної реалізації
- `MULTIPLAYER_IMPLEMENTATION_PLAN.md` - Phase 2.2 Wieldables Sync

