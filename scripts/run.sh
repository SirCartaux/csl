#!/usr/bin/env bash
# Builds release and opens the app.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh release
open build/CSL.app
