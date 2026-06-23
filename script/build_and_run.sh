#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MacOptimizingLooper"
BUNDLE_ID="as.kargn.MacOptimizingLooper"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESPONSE_GUIDE_SCRIPT="$ROOT_DIR/script/mac-optimizing-looper-response-guide.sh"
RESPONSE_FORMAT_SCRIPT="$ROOT_DIR/script/mac-optimizing-looper-format-json.sh"
# Scan skill ships inside the bundle (MacOptimizerScript reads Bundle.main, never $HOME).
MAC_OPTIMIZER_SCRIPT_SRC="$ROOT_DIR/.agents/skills/mac-optimizer/mac-optimize.sh"
CORE_BUNDLE="MacOptimizingLooper_MacOptimizingLooperCore.bundle"

cd "$ROOT_DIR"

while read -r existing_pid; do
  [ -n "$existing_pid" ] || continue
  pkill -TERM -P "$existing_pid" >/dev/null 2>&1 || true
done < <(pgrep -x "$APP_NAME" || true)
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BIN_PATH="$(swift build --show-bin-path)"
BUILD_BINARY="$BIN_PATH/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
mkdir -p "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [[ -d "$BIN_PATH/$CORE_BUNDLE" ]]; then
  cp -R "$BIN_PATH/$CORE_BUNDLE" "$APP_RESOURCES/$CORE_BUNDLE"
else
  echo "ERROR: localized resource bundle not found at $BIN_PATH/$CORE_BUNDLE" >&2
  exit 1
fi
if [[ -d "$BIN_PATH/Sparkle.framework" ]]; then
  cp -R "$BIN_PATH/Sparkle.framework" "$APP_FRAMEWORKS/Sparkle.framework"
  if ! otool -l "$APP_BINARY" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
  fi
else
  echo "ERROR: Sparkle.framework not found at $BIN_PATH/Sparkle.framework" >&2
  exit 1
fi
cp "$RESPONSE_GUIDE_SCRIPT" "$APP_RESOURCES/mac-optimizing-looper-response-guide.sh"
chmod +x "$APP_RESOURCES/mac-optimizing-looper-response-guide.sh"
cp "$RESPONSE_FORMAT_SCRIPT" "$APP_RESOURCES/mac-optimizing-looper-format-json.sh"
chmod +x "$APP_RESOURCES/mac-optimizing-looper-format-json.sh"
cp "$MAC_OPTIMIZER_SCRIPT_SRC" "$APP_RESOURCES/mac-optimize.sh"
chmod +x "$APP_RESOURCES/mac-optimize.sh"

cat >"$INFO_PLIST" <<PLIST
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

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
