#!/usr/bin/env bash
# Builds CSL and assembles a runnable .app bundle in build/CSL.app
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
swift build -c "$CONFIG"

APP="build/CSL.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"

cp "$BIN_DIR/CSL" "$APP/Contents/MacOS/CSL"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Fonts/*.ttf "$APP/Contents/Resources/Fonts/"
cp Resources/Fonts/OFL.txt "$APP/Contents/Resources/Silkscreen-OFL.txt"
cp Resources/CSL.icns "$APP/Contents/Resources/CSL.icns"

# Ad-hoc signing is enough for local use and keeps TCC/login-item APIs happy.
codesign --force --sign - --identifier com.henri.CSL "$APP" >/dev/null 2>&1 || \
  echo "warning: codesign failed (app still runs)"

echo "built $APP"
