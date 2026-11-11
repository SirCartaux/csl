#!/bin/bash
# Render production views in a disposable checkout with isolated settings.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/docs/readme}"
mkdir -p "$OUT" "$ROOT/build"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d "$ROOT/build/readme-render.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/project"
# Only tracked build inputs plus the snapshot fixture; no personal app data.
for PART in Package.swift Sources Resources Tests; do
  ditto "$ROOT/$PART" "$WORK/project/$PART"
done
mkdir -p "$WORK/project/Tests/CSLTests"
cp "$ROOT/Tools/readme/ReadmeSnapshotTests.swift.template" "$WORK/project/Tests/CSLTests/ReadmeSnapshotTests.swift"
cd "$WORK/project"
export CSL_README_MEDIA_DIR="$OUT"
export CSL_DATA_DIR="$WORK/csl-data" CEP_DATA_DIR="$WORK/cep-data"
export CEP_EMOJI_PATH="$ROOT/Resources/emoji.json"
export CSL_NO_PIXEL_ANIMATION=1 CEP_NO_ANIMATION=1
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/readme-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/readme-swift-cache"
swift test --disable-sandbox --scratch-path "$ROOT/.build/readme-render" \
  --cache-path "$ROOT/.build/readme-cache" --config-path "$WORK/config" \
  --security-path "$WORK/security" --manifest-cache local -debug-info-format none \
  --filter ReadmeSnapshotTests
printf '\nNative screenshots written to %s\n' "$OUT"
