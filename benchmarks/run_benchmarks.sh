#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building ZoomCastBench (release)..."
swift build -c release --product ZoomCastBench
BIN_PATH="$(swift build -c release --show-bin-path)/ZoomCastBench"

echo "Running release benchmark with /usr/bin/time -l..."
/usr/bin/time -l "$BIN_PATH"
