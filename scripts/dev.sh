#!/usr/bin/env bash
# Builds and launches CSL attached to the terminal, with debug timing logs.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh debug
exec env CSL_DEBUG=1 ./build/CSL.app/Contents/MacOS/CSL "$@"
