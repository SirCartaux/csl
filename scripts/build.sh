#!/usr/bin/env bash
# Builds CSL and assembles a runnable .app bundle in build/CSL.app
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
ARCHITECTURES="${2:-native}"
if [[ "$ARCHITECTURES" == "universal" ]]; then
  swift build -c "$CONFIG" --arch arm64
  ARM_BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/CSL"
  swift build -c "$CONFIG" --arch x86_64
  INTEL_BIN="$(swift build -c "$CONFIG" --arch x86_64 --show-bin-path)/CSL"
  mkdir -p build/universal
  lipo -create "$ARM_BIN" "$INTEL_BIN" -output build/universal/CSL
  BIN="build/universal/CSL"
else
  BIN="$(swift build -c "$CONFIG" --show-bin-path)/CSL"
  swift build -c "$CONFIG"
fi

APP="build/CSL.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"

cp "$BIN" "$APP/Contents/MacOS/CSL"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Fonts/*.ttf "$APP/Contents/Resources/Fonts/"
cp Resources/Fonts/OFL.txt "$APP/Contents/Resources/Silkscreen-OFL.txt"
cp Resources/CSL.icns "$APP/Contents/Resources/CSL.icns"

# Ad-hoc signing is enough for local use and keeps TCC/login-item APIs happy.
codesign --force --sign - --identifier com.henri.CSL "$APP" >/dev/null 2>&1 || \
  echo "warning: codesign failed (app still runs)"

echo "built $APP"
