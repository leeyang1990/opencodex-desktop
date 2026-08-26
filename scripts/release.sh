#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST_PATH="$PROJECT_DIR/Info.plist"
APP_PATH="$PROJECT_DIR/dist/OpenCodex Desktop.app"
RELEASE_DIR="$PROJECT_DIR/dist/release"
ALLOW_DIRTY=false
SKIP_TESTS=false
REQUESTED_VERSION=""

usage() {
  cat <<'EOF'
Usage: ./scripts/release.sh [options] [version]

Build and package an ad-hoc-signed Apple Silicon macOS release.

Arguments:
  version          Expected CFBundleShortVersionString, for example 0.6.0.
                   Defaults to the value in Info.plist.

Options:
  --allow-dirty    Allow packaging from a working tree with uncommitted changes.
  --skip-tests     Skip swift test (intended only when tests already ran in CI).
  -h, --help       Show this help.

Artifacts are written to dist/release/.
EOF
}

fail() {
  echo "release: $*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --allow-dirty)
      ALLOW_DIRTY=true
      ;;
    --skip-tests)
      SKIP_TESTS=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      fail "unknown option: $1"
      ;;
    *)
      [[ -z "$REQUESTED_VERSION" ]] || fail "only one version argument is allowed"
      REQUESTED_VERSION="$1"
      ;;
  esac
  shift
done

for command in codesign ditto git hdiutil lipo plutil shasum sips swift; do
  command -v "$command" >/dev/null || fail "required command not found: $command"
done

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required"
[[ -f "$PLIST_PATH" ]] || fail "missing Info.plist"
[[ -x "$SCRIPT_DIR/build-app.sh" ]] || fail "scripts/build-app.sh is not executable"
[[ -x "$SCRIPT_DIR/check-source-quality.sh" ]] || fail "scripts/check-source-quality.sh is not executable"

VERSION="$(plutil -extract CFBundleShortVersionString raw "$PLIST_PATH")"
BUILD_NUMBER="$(plutil -extract CFBundleVersion raw "$PLIST_PATH")"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$PLIST_PATH")"
MINIMUM_MACOS="$(plutil -extract LSMinimumSystemVersion raw "$PLIST_PATH")"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] \
  || fail "Info.plist contains an invalid release version: $VERSION"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] \
  || fail "Info.plist contains an invalid build number: $BUILD_NUMBER"

if [[ -n "$REQUESTED_VERSION" && "$REQUESTED_VERSION" != "$VERSION" ]]; then
  fail "requested version $REQUESTED_VERSION does not match Info.plist version $VERSION"
fi

if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  EXPECTED_TAG="v$VERSION"
  [[ "${GITHUB_REF_NAME:-}" == "$EXPECTED_TAG" ]] \
    || fail "GitHub tag ${GITHUB_REF_NAME:-<unset>} does not match $EXPECTED_TAG"
fi

cd "$PROJECT_DIR"
if [[ "$ALLOW_DIRTY" != true && -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  fail "working tree is dirty; commit changes or pass --allow-dirty for a local test build"
fi

echo "==> Releasing OpenCodex Desktop $VERSION ($BUILD_NUMBER)"
echo "==> Checking source quality"
"$SCRIPT_DIR/check-source-quality.sh"
if [[ "$SKIP_TESTS" != true ]]; then
  echo "==> Running tests"
  swift test
fi

echo "==> Building Apple Silicon app"
"$SCRIPT_DIR/build-app.sh"

EXECUTABLE="$APP_PATH/Contents/MacOS/OpenCodexDesktop"
[[ -d "$APP_PATH" ]] || fail "build did not produce $APP_PATH"
[[ -x "$EXECUTABLE" ]] || fail "app executable is missing or not executable"

APP_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")"
APP_BUILD="$(plutil -extract CFBundleVersion raw "$APP_PATH/Contents/Info.plist")"
[[ "$APP_VERSION" == "$VERSION" && "$APP_BUILD" == "$BUILD_NUMBER" ]] \
  || fail "built app version does not match Info.plist"

BUILT_ICON_LAYER="$PROJECT_DIR/.build/AppIcon.iconset/icon_512x512@2x.png"
[[ -f "$BUILT_ICON_LAYER" ]] || fail "build did not produce the 1024px app icon layer"
BUILT_ICON_ALPHA="$(sips -g hasAlpha "$BUILT_ICON_LAYER" | awk '/hasAlpha/ {print $2}')"
[[ "$BUILT_ICON_ALPHA" == "no" ]] \
  || fail "built app icon contains transparency; release packaging stopped"

ARCHS="$(lipo -archs "$EXECUTABLE")"
[[ "$ARCHS" == "arm64" ]] \
  || fail "built executable must contain only arm64 (found: $ARCHS)"

echo "==> Verifying ad-hoc signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if find "$APP_PATH" -type d \( -name vendor -o -name node_modules -o -name Core -o -name Logs \) -print -quit | grep -q .; then
  fail "app bundle contains a forbidden runtime or source directory"
fi
if find "$APP_PATH" -type f \( -name config.json -o -name admin-api-token -o -name '*.log' \) -print -quit | grep -q .; then
  fail "app bundle contains configuration, credentials, or logs"
fi

ARTIFACT_BASENAME="OpenCodex-Desktop-v${VERSION}-macOS-arm64"
ZIP_NAME="$ARTIFACT_BASENAME.zip"
DMG_NAME="$ARTIFACT_BASENAME.dmg"
ZIP_CHECKSUM_NAME="$ZIP_NAME.sha256"
DMG_CHECKSUM_NAME="$DMG_NAME.sha256"
DMG_STAGING="$PROJECT_DIR/.build/release-dmg-staging"

[[ "$RELEASE_DIR" == "$PROJECT_DIR/dist/release" ]] || fail "unexpected release directory"
[[ "$DMG_STAGING" == "$PROJECT_DIR/.build/release-dmg-staging" ]] || fail "unexpected DMG staging directory"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "==> Creating $ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$RELEASE_DIR/$ZIP_NAME"

echo "==> Creating $DMG_NAME"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
ditto "$APP_PATH" "$DMG_STAGING/OpenCodex Desktop.app"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
  -quiet \
  -volname "OpenCodex Desktop" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$RELEASE_DIR/$DMG_NAME"
hdiutil verify "$RELEASE_DIR/$DMG_NAME" >/dev/null
rm -rf "$DMG_STAGING"

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$ZIP_NAME" > "$ZIP_CHECKSUM_NAME"
  shasum -a 256 "$DMG_NAME" > "$DMG_CHECKSUM_NAME"
)

ZIP_SIZE="$(du -h "$RELEASE_DIR/$ZIP_NAME" | awk '{print $1}')"
DMG_SIZE="$(du -h "$RELEASE_DIR/$DMG_NAME" | awk '{print $1}')"
COMMIT="$(git rev-parse --short=12 HEAD)"

cat <<EOF

Release package ready:
  Version:      $VERSION ($BUILD_NUMBER)
  Bundle ID:    $BUNDLE_ID
  Minimum macOS:$MINIMUM_MACOS
  Architectures:$ARCHS
  Signing:      ad-hoc (not notarized)
  Commit:       $COMMIT
  ZIP:          dist/release/$ZIP_NAME ($ZIP_SIZE)
  ZIP checksum: dist/release/$ZIP_CHECKSUM_NAME
  DMG:          dist/release/$DMG_NAME ($DMG_SIZE)
  DMG checksum: dist/release/$DMG_CHECKSUM_NAME

Users may need to right-click Open on first launch. If Gatekeeper still blocks it:
  xattr -dr com.apple.quarantine "/Applications/OpenCodex Desktop.app"
EOF
