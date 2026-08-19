#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$PROJECT_DIR/dist/OpenCodex Desktop.app"
CONTENTS_PATH="$APP_PATH/Contents"
ICONSET_PATH="$PROJECT_DIR/.build/AppIcon.iconset"
SOURCE_ICON="$PROJECT_DIR/Assets/AppIcon-Source.png"

if [[ "$APP_PATH" != "$PROJECT_DIR/dist/OpenCodex Desktop.app" ]]; then
  echo "Unexpected app output path" >&2
  exit 1
fi
if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Missing app icon source: $SOURCE_ICON" >&2
  exit 1
fi

cd "$PROJECT_DIR"
swift build -c release --arch arm64
BIN_PATH="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf "$APP_PATH" "$ICONSET_PATH"
mkdir -p "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources" "$ICONSET_PATH"
cp "$BIN_PATH/OpenCodexDesktop" "$CONTENTS_PATH/MacOS/OpenCodexDesktop"
cp "Info.plist" "$CONTENTS_PATH/Info.plist"
cp "LICENSE" "$CONTENTS_PATH/Resources/LauncherLicense.txt"
cp "THIRD_PARTY_NOTICES.md" "$CONTENTS_PATH/Resources/ThirdPartyNotices.md"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SOURCE_ICON" --out "$ICONSET_PATH/icon_${size}x${size}.png" >/dev/null
done
for size in 16 32 128 256; do
  double=$((size * 2))
  sips -z "$double" "$double" "$SOURCE_ICON" --out "$ICONSET_PATH/icon_${size}x${size}@2x.png" >/dev/null
done
sips -z 1024 1024 "$SOURCE_ICON" --out "$ICONSET_PATH/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_PATH" -o "$CONTENTS_PATH/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_PATH"
echo "$APP_PATH"
