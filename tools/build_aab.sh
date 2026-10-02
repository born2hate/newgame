#!/usr/bin/env bash
# Подписанный AAB для Google Play: build/DeepColony.aab
#
#   GODOT=/path/to/Godot_v4.3-stable_linux.x86_64 \
#   KEYSTORE=/path/to/deepcolony-upload.keystore KEYSTORE_PASS=... \
#   tools/build_aab.sh
#
# Нужны: шаблоны экспорта 4.3, JDK 17, Android SDK (platforms;android-36, build-tools;36.0.0,
# ndk;23.2.8568313) — пути в настройках редактора (export/android/*). Ключ в репозиторий не класть.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GODOT:?path to Godot 4.3}" "${KEYSTORE:?path to upload keystore}" "${KEYSTORE_PASS:?keystore password}"

# Импорт ресурсов: headless-импорт 4.3 иногда обрывается, повторяем, пока не останется ошибок
for i in 1 2 3 4 5 6 7 8; do
	if ! "$GODOT" --headless --path . --import 2>&1 | grep -q "Can't find file"; then break; fi
done

# Шаблон Android (android/ в .gitignore): ставится вместе с экспортом. Библиотекам плагинов
# (androidx.core 1.15, Billing 9) нужен compileSdk 35+, а в шаблоне 4.3 — 34.
if [ ! -f android/build/config.gradle ]; then
	"$GODOT" --headless --path . --install-android-build-template --export-release Android build/DeepColony.aab >/dev/null 2>&1 || true
fi
sed -i "s/compileSdk         : 34,/compileSdk         : 36,/; s/buildTools         : '34.0.0',/buildTools         : '36.0.0',/" android/build/config.gradle
grep -q suppressUnsupportedCompileSdk android/build/gradle.properties || echo "android.suppressUnsupportedCompileSdk=36" >> android/build/gradle.properties

mkdir -p build
rm -f build/DeepColony.aab
GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE" GODOT_ANDROID_KEYSTORE_RELEASE_USER=upload \
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$KEYSTORE_PASS" \
	"$GODOT" --headless --path . --export-release Android build/DeepColony.aab
# AdMob-плагин сам скачивает iOS-библиотеки в ios/ — для Android они не нужны
rm -rf ios
ls -la build/DeepColony.aab
