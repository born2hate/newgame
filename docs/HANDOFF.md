# Передача работы: сборка релиза Deep Colony

Состояние на 2026-10-02 (ветка `claude/kind-noether-3q5ia8`).

## Готово
- Игра 0.14 (Godot 4.3, gl_compatibility), 10 языков, тесты: `tests/run_tests.gd`, автотест UI: `-- --selftest`.
- Play Console: приложение `com.deepcolony.game` создано, имя пакета зарегистрировано
  (Android developer verification) с ключом загрузки, SHA-256
  `9E:C0:D9:2D:53:DC:57:DA:4B:DF:67:CD:F4:CE:0F:E2:B4:D5:E2:DB:51:6C:01:95:24:99:E5:7D:54:B3:1F:C4`.
- Все анкеты (доступ, реклама, рейтинг IARC, аудитория 13+, Data safety, категория) заполнены.
- Страница магазина на 10 языках с картинками загружена через `tools/play_publish.py`.
- AdMob: App ID и блок rewarded прописаны в `scripts/ads.gd`.

## Сделано 2026-10-02
- Плагины в `addons/`: Google Play Billing 3.3.0 (`addons/GodotGooglePlayBilling`) и AdMob v4.3.1
  с Android-библиотеками для Godot 4.3 (`addons/admob/android/bin`), App ID в `addons/admob/android/config.gd`.
  `scripts/store.gd` переведён на API Billing 3.x (initPlugin, on_purchase_updated, queryPurchases(type, false)).
- Пресет: Gradle build, AAB, version code 12, minSdk 24 (требует AdMob), targetSdk 36.
- Сборка: `tools/build_aab.sh` (ставит шаблон, поднимает compileSdk до 36, подписывает ключом upload).
- **0.14 (12) загружена во внутреннее тестирование** (`play_publish.py bundle`), статус completed.

## 0.15 (13)
- Окно согласия GDPR (Google UMP) перед инициализацией AdMob, кнопка «Privacy settings» в настройках
  (видна только там, где согласие требуется). В AdMob → Privacy & messaging должно быть создано
  и опубликовано сообщение GDPR, иначе окно не появится.
- AAB 13 загружен в библиотеку Play (без трека): 12 на первой проверке Google в Alpha/Internal.
  После одобрения: Internal/Production → Create release → Add from library → 13.

## Осталось
1. ~~Товары~~: платёжный профиль создан, 15 товаров созданы и активны (`play_publish.py products`).
2. Internal testing → Testers: добавить свой email, установить по ссылке, проверить покупку и рекламу.
3. Пользователь отмечает ИИ-картинки в Main store listing → AI asset declaration.
4. Ключи и JSON сервисного аккаунта в репозиторий не класть.

## Инструменты сессии
- Godot 4.3 headless + export templates, JDK 17, Android SDK (platforms 36, build-tools 36, NDK 23.2) скачивались в scratchpad;
  в новом окружении их нужно поставить заново.
- Экономика: `tools/economy_sim.gd -- free 30 [s=8x15]`.
