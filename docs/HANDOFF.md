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

## Осталось
1. Поставить плагины (нужна сеть: dl.google.com, github.com, objects.githubusercontent.com):
   - Google Play Billing для Godot 4 (godot-sdk-integrations/godot-google-play-billing);
   - AdMob (poing-studios/godot-admob-plugin), App ID `ca-app-pub-3660062326800102~1427937123`.
   Код (`scripts/store.gd`, `scripts/ads.gd`) находит плагины сам.
2. Android build template, Use Gradle Build = On, формат AAB, version code ≥ 12.
3. Подписать ключом загрузки (`deepcolony-upload.keystore`, alias `upload`) — пользователь пришлёт
   файл и пароль. **Ключи и JSON сервисного аккаунта в репозиторий не класть.**
4. `PLAY_KEY=<json> python3 tools/play_publish.py ...`: загрузить AAB во внутреннее тестирование
   (дописать команду upload_bundle + tracks), создать 15 товаров из `docs/store/play_console_answers.md`
   (ID должны совпадать с `scripts/store.gd`).
5. Пользователь отмечает ИИ-картинки в Main store listing → AI asset declaration.

## Инструменты сессии
- Godot 4.3 headless + export templates, Android SDK (build-tools 34) скачивались в scratchpad;
  в новом окружении их нужно поставить заново.
- Экономика: `tools/economy_sim.gd -- free 30 [s=8x15]`.
