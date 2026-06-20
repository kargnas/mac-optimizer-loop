#!/usr/bin/env zsh
# Release packager — builds a distributable dist/MacOptimizingLooper.app.
#
# Local default = ad-hoc sign ("-"): fine for testing on THIS Mac, but Gatekeeper
# blocks it on any other Mac. CI (.github/workflows/build-release.yml) sets
#   CODE_SIGN_IDENTITY="Developer ID Application"  HARDENED_RUNTIME=1
# to produce a notarizable bundle. Kept separate from build_and_run.sh because
# that script targets the fast local dev loop (debug build, no version stamping).
set -euo pipefail

APP_NAME="MacOptimizingLooper"
BUNDLE_ID="as.kargn.MacOptimizingLooper"
MIN_SYSTEM_VERSION="13.0"
APP_VERSION="${APP_VERSION:-0.0.0}"             # CFBundleShortVersionString / CFBundleVersion
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"   # "-" == ad-hoc
HARDENED_RUNTIME="${HARDENED_RUNTIME:-0}"       # "1" adds --options runtime (required by notarization)

ROOT_DIR="${0:A:h}/.."
ROOT_DIR="${ROOT_DIR:A}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"

cd "$ROOT_DIR"

# Release build so the shipped binary is optimized, unlike the debug build_and_run loop.
swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_MACOS/$APP_NAME"
chmod +x "$APP_MACOS/$APP_NAME"

# The formatter/guide scripts are loaded from the bundle Resources at runtime.
for s in mac-optimizing-looper-response-guide.sh mac-optimizing-looper-format-json.sh; do
  cp "$ROOT_DIR/script/$s" "$APP_RESOURCES/$s"
  chmod +x "$APP_RESOURCES/$s"
done

cat >"$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

sign_args=(--force --sign "$CODE_SIGN_IDENTITY")
if [[ "$HARDENED_RUNTIME" == "1" ]]; then
  # Hardened runtime + secure timestamp are mandatory for notarization. The app
  # only spawns signed system tools (zsh, claude, osascript), so no extra
  # entitlements are needed.
  sign_args+=(--options runtime --timestamp)
fi
/usr/bin/codesign "${sign_args[@]}" "$APP_BUNDLE"

echo "Built $APP_BUNDLE — version $APP_VERSION, identity '$CODE_SIGN_IDENTITY', hardened=$HARDENED_RUNTIME"
