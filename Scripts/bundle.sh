#!/bin/bash
# Builds Cyclop.app without Xcode: SwiftPM produces the binary, this script
# assembles the bundle around it and signs it (a keychain identity if present,
# otherwise ad-hoc — see the signing step).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/CAVO Notch.app"
VERSION="$(sed -n 's/^VERSION=//p' "$ROOT/Scripts/version" 2>/dev/null || echo 0.1.0)"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/Cyclop"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CAVO Notch"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>CAVO Notch</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>ru</string></array>
    <key>CFBundleDisplayName</key><string>CAVO Notch</string>
    <key>CFBundleIdentifier</key><string>one.cavo.notch</string>
    <key>CFBundleExecutable</key><string>CAVO Notch</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>NSAppleEventsUsageDescription</key>
    <string>CAVO Notch reads the current track and controls playback in Apple Music and Spotify.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>CAVO Notch shows your next meetings and a button to join the call.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>CAVO Notch shows your next meetings and a button to join the call.</string>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Таблицы строк кладутся прямо в бандл, а не через ресурсы SwiftPM: бандл здесь
# собирается вручную, и .lproj рядом с исполняемым файлом — то, где их ищет сама
# macOS. Язык она выбирает потом сама, по списку предпочитаемых у пользователя.
echo "==> локализации"
for lproj in "$ROOT"/Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "$APP/Contents/Resources/"
    echo "    $(basename "$lproj")"
done

# Now Playing helper. Built here rather than by SwiftPM because it is not linked
# into the app: it is loaded into /usr/bin/perl at runtime. See helper.m.
echo "==> building Now Playing helper"
clang -dynamiclib -fobjc-arc -O2 \
    -mmacosx-version-min=15.0 \
    -framework Foundation \
    -o "$APP/Contents/Resources/libcyclopmedia.dylib" \
    "$ROOT/Sources/CyclopMediaHelper/helper.m"

echo "==> signing"
# Расширенные атрибуты снимаются первыми. iCloud вешает на файлы
# com.apple.FinderInfo, а codesign отказывается подписывать что-либо с ним —
# «resource fork, Finder information, or similar detritus not allowed». Папка
# «Рабочий стол» синхронизируется с iCloud у многих по умолчанию, так что клон
# репозитория там перестает подписываться, стоило его туда перенести.
xattr -cr "$APP"

# Ошибка не глушится и не понижается до предупреждения. Раньше отказ печатал
# мягкую строку и возвращал ноль: скрипт доходил до «done», а в build лежал
# бандл, про который codesign говорит «code object is not signed at all».
# Заметить это можно было только по возвращающимся запросам TCC — то есть у
# того, кто уже поставил приложение.
# Стабильное удостоверение вместо ad-hoc, если оно есть в связке. У ad-hoc
# подписи «личность» приложения — это хеш кода, поэтому она меняется на каждой
# пересборке, и macOS каждый раз спрашивает разрешения заново (TCC привязывает
# грант к designated requirement). Самоподписанный сертификат даёт DR вида
# «identifier + certificate leaf», не зависящий от хеша, — грант переживает
# пересборки. На чужой машине и в CI сертификата нет: тихий откат на ad-hoc,
# сборка не ломается. Настоящий Developer ID, когда появится, задаётся тем же
# CODESIGN_ID и подписывается уже нотаризуемо.
SIGN_ID="${CODESIGN_ID:-CAVO Notch Self-Signed}"
if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
    echo "    подпись удостоверением: $SIGN_ID"
else
    SIGN_ID="-"
    echo "    удостоверение не найдено — ad-hoc"
fi
codesign --force --deep --sign "$SIGN_ID" "$APP" || {
    echo "!!! codesign не смог подписать бандл — см. вывод выше" >&2
    exit 1
}
codesign --verify --strict "$APP" || {
    echo "!!! подпись не прошла проверку" >&2
    exit 1
}

echo "==> done: $APP"
