#!/usr/bin/env bash
# Builds CSL and assembles a runnable .app bundle in build/CSL.app
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
ARCHITECTURES="${2:-native}"
if [[ "$ARCHITECTURES" == "universal" ]]; then
  ARM_SCRATCH=".build/arm64"
  INTEL_SCRATCH=".build/x86_64"
  swift build -c "$CONFIG" --arch arm64 --scratch-path "$ARM_SCRATCH"
  ARM_BIN="$(swift build -c "$CONFIG" --arch arm64 --scratch-path "$ARM_SCRATCH" --show-bin-path)/CSL"
  swift build -c "$CONFIG" --arch x86_64 --scratch-path "$INTEL_SCRATCH"
  INTEL_BIN="$(swift build -c "$CONFIG" --arch x86_64 --scratch-path "$INTEL_SCRATCH" --show-bin-path)/CSL"
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
cp Resources/emoji.json "$APP/Contents/Resources/emoji.json"

# A stable Apple Development signature keeps TCC permissions (Accessibility /
# Input Monitoring for the embedded character picker) across rebuilds.
IDENTITY="${CSL_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}"
if [[ -n "${IDENTITY}" ]]; then
  codesign --force --sign "$IDENTITY" --identifier com.henri.CSL --timestamp=none "$APP" >/dev/null 2>&1 || {
    echo "warning: signing with '$IDENTITY' failed, falling back to ad-hoc"
    codesign --force --sign - --identifier com.henri.CSL "$APP" >/dev/null 2>&1 || true
  }
else
  codesign --force --sign - --identifier com.henri.CSL "$APP" >/dev/null 2>&1 || \
    echo "warning: codesign failed (app still runs)"
fi

echo "built $APP"
