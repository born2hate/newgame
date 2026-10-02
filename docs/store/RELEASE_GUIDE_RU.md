# Как выпустить Deep Colony в Google Play

Что уже готово в репозитории:
- игра, переводы на 10 языков, иконка;
- тексты страницы магазина: `docs/store/listing/*.md`;
- скриншоты 1080×1920 на 10 языках: `docs/store/screenshots/<язык>/`;
- обложка 1024×500: `docs/store/feature_graphic.png`;
- политика конфиденциальности: `docs/store/privacy_policy.html`;
- ответы для анкет: `docs/store/play_console_answers.md`;
- код покупок (Google Play Billing) и рекламы (AdMob) — включается сам, когда в сборке есть плагины. Без них игра работает в тестовом режиме (покупки бесплатны).

## 1. Подготовить компьютер (один раз)
1. Установи **Godot 4.3** и в нём *Editor → Manage Export Templates → Download*.
2. Установи **Android Studio** (с ним придут Android SDK и JDK 17).
3. В Godot: *Editor Settings → Export → Android*: путь к SDK (`~/Android/Sdk`) и к Java (JDK 17 из Android Studio).
4. *Project → Install Android Build Template* (появится папка `android/`).

## 2. Плагины
1. **Покупки**: [godot-google-play-billing](https://github.com/godot-sdk-integrations/godot-google-play-billing) для Godot 4 — скопировать в `android/plugins` (или `addons/`, как написано в README плагина), включить в *Project → Export → Android → Plugins*.
2. **Реклама**: [godot-admob-plugin (poing-studios)](https://github.com/poing-studios/godot-admob-plugin) — через AssetLib или вручную в `addons/admob`, включить плагин в *Project Settings → Plugins*, скачать Android-библиотеку плагина по его инструкции.
3. В AdMob создай приложение и **блок рекламы с вознаграждением**. ID уже прописаны в `scripts/ads.gd` (App ID `ca-app-pub-3660062326800102~1427937123` указать в настройках плагина).

Код уже ищет оба плагина сам: если они на месте, тестовый режим выключается.

## 3. Ключ подписи (один раз, хранить!)
```
keytool -genkey -v -keystore deepcolony-upload.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000
```
Файл и пароль сохрани в надёжном месте — без них нельзя выпустить обновление.
В *Project → Export → Android*: Release keystore = этот файл, user = `upload`, пароли.

## 4. Сборка AAB
В пресете Android:
- **Use Gradle Build: On**, **Export Format: AAB**;
- package: `com.deepcolony.game` (можно свой, но потом не менять);
- **Version Code** увеличивать на 1 с каждым выпуском, Version Name — `1.0`.
*Export Project → Release* → получится `DeepColony.aab`.

## 5. Play Console
1. *Create app*: название **Deep Colony: Underwater Base**, Game, Free.
2. *Store listing*: тексты из `docs/store/listing/`, обложка, иконка 512×512, скриншоты. Языки добавляются в *Store listing → Manage translations*.
3. *App content*: политика, реклама, аудитория, Data safety, рейтинг — по `play_console_answers.md`.
4. *Monetize → In-app products*: создай товары с ID из таблицы и активируй.
5. *Testing → Internal testing*: загрузи AAB, добавь себя тестером, установи по ссылке, проверь покупку (Google не списывает деньги с лицензионных тестеров: *Settings → License testing*).
6. Для новых личных аккаунтов: **закрытый тест — 12 тестеров 14 дней**, потом откроется *Production*.
7. *Production → Create release* → загрузить тот же AAB → отправить на проверку (обычно 1–7 дней).

## 6. После выпуска
- Смотри *Statistics* и *Financial reports*.
- Для обновления: поднять Version Code, собрать AAB, загрузить в новый релиз.
