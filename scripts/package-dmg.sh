#!/usr/bin/env bash
# Builds ScribeAI as a Universal 2 Release app, ad-hoc signs it, and packages it
# into dist/ScribeAI-macOS.dmg with a SHA-256 checksum alongside.
#
# Used by .github/workflows/release.yml and runnable locally:
#
#   scripts/package-dmg.sh            # version from the project (MARKETING_VERSION)
#   scripts/package-dmg.sh 1.2.0      # override the version shown in Finder/About
#
# Requires Xcode 26+ and create-dmg (`brew install create-dmg`).
set -euo pipefail

APP_NAME="ScribeAI"
VERSION="${1:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
STAGING="$BUILD_DIR/dmg-staging"
DIST="$ROOT/dist"
APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
DMG="$DIST/$APP_NAME-macOS.dmg"

command -v create-dmg >/dev/null || { echo "create-dmg not found: brew install create-dmg" >&2; exit 1; }

echo "==> Building $APP_NAME (arm64 + x86_64)"
build_settings=(ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual)
[[ -n "$VERSION" ]] && build_settings+=(MARKETING_VERSION="$VERSION")
rm -rf "$DERIVED_DATA"
xcodebuild \
  -project "$ROOT/ScribeAI.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  "${build_settings[@]}" \
  build

echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"

# Apple Silicon refuses to launch unsigned code (SIGKILL, Code Signature Invalid),
# so the bundle needs at least an ad-hoc signature.
echo "==> Ad-hoc signing app"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# create-dmg copies the *contents* of its source folder, so stage the app in one.
echo "==> Creating DMG"
rm -rf "$STAGING" "$DMG" "$DMG.sha256"
mkdir -p "$STAGING" "$DIST"
ditto "$APP" "$STAGING/$APP_NAME.app"
create-dmg \
  --volname "$APP_NAME Installer" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 175 120 \
  --app-drop-link 425 120 \
  --hide-extension "$APP_NAME.app" \
  --no-internet-enable \
  "$DMG" \
  "$STAGING"

# Leave the DMG unsigned: macOS checks a signed disk image when it's opened and
# blocks an ad-hoc signature, whereas an unsigned one opens and only the app is
# checked, where Privacy & Security offers Open Anyway.
hdiutil verify "$DMG"

(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

echo "==> Done"
echo "    $DMG"
echo "    $(cat "$DMG.sha256")"
