#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building ZoomCast ($MODE)..."
if [ "$MODE" = "release" ]; then
  swift build -c release --product ZoomCast
  BIN_PATH="$(swift build -c release --show-bin-path)/ZoomCast"
else
  swift build --product ZoomCast
  BIN_PATH="$(swift build --show-bin-path)/ZoomCast"
fi

APP_DIR="$ROOT/build/ZoomCast.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/ZoomCast"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Generate AppIcon.icns from Resources/AppIcon.svg using qlmanage/rsvg/sips
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

BASE_PNG="$ROOT/build/icon_1024.png"
if command -v rsvg-convert >/dev/null 2>&1; then
  rsvg-convert -w 1024 -h 1024 "$ROOT/Resources/AppIcon.svg" -o "$BASE_PNG"
else
  qlmanage -t -s 1024 -o "$ROOT/build" "$ROOT/Resources/AppIcon.svg" >/dev/null 2>&1
  mv "$ROOT/build/AppIcon.svg.png" "$BASE_PNG"
fi

for sz in 16 32 128 256 512; do
  sips -z "$sz" "$sz" "$BASE_PNG" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  dbl=$((sz * 2))
  sips -z "$dbl" "$dbl" "$BASE_PNG" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" "$BASE_PNG"

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --strict "$APP_DIR"

echo "Built and signed: $APP_DIR ($(du -sh "$APP_DIR" | awk '{print $1}'))"
