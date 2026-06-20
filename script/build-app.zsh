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

# Sparkle auto-update wiring. The feed + public EdDSA key are baked into every
# build (needed even for a manual "Check for Updates"); only the *automatic*
# background checks are gated off in local/ad-hoc builds.
SPARKLE_FEED_URL="https://github.com/kargnas/mac-optimizing-looper/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_ED_KEY="jdJ6yRwGirTFP1hx2b7NxhzoHPpkUdwak4+HDYNbhhs="
# CI release sets SPARKLE_AUTO=1. Default 0 so a fixed-low-version dev/ad-hoc bundle
# does NOT silently auto-replace itself with the latest release on every quit.
SPARKLE_AUTO="${SPARKLE_AUTO:-0}"

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
BIN_PATH="$(swift build -c release --show-bin-path)"
BUILD_BINARY="$BIN_PATH/$APP_NAME"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_MACOS/$APP_NAME"
chmod +x "$APP_MACOS/$APP_NAME"

# SwiftPM links @rpath/Sparkle.framework but never embeds it. Copy it in and add the
# rpath so the binary resolves the framework from inside the bundle at runtime.
ditto "$BIN_PATH/Sparkle.framework" "$APP_FRAMEWORKS/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_MACOS/$APP_NAME"

# The formatter/guide scripts are loaded from the bundle Resources at runtime.
for s in mac-optimizing-looper-response-guide.sh mac-optimizing-looper-format-json.sh; do
  cp "$ROOT_DIR/script/$s" "$APP_RESOURCES/$s"
  chmod +x "$APP_RESOURCES/$s"
done

# Auto-check keys only in release builds (SPARKLE_AUTO=1); absent ones default to
# off in Sparkle, so a local ad-hoc bundle never background-updates itself.
if [[ "$SPARKLE_AUTO" == "1" ]]; then
  SPARKLE_AUTO_PLIST='  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <true/>'
else
  SPARKLE_AUTO_PLIST='  <key>SUEnableAutomaticChecks</key>
  <false/>'
fi

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
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
$SPARKLE_AUTO_PLIST
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

# Sign INSIDE-OUT: every nested executable first, the framework, then the app last.
# Never use --deep to sign (it strips Downloader.xpc's sandbox entitlement and breaks
# notarization); --deep is only safe for the final --verify pass.
SPARKLE_B="$APP_FRAMEWORKS/Sparkle.framework/Versions/B"
/usr/bin/codesign "${sign_args[@]}" "$SPARKLE_B/Autoupdate"
/usr/bin/codesign "${sign_args[@]}" "$SPARKLE_B/Updater.app"
# Downloader.xpc ships a sandbox entitlement that must survive re-signing.
/usr/bin/codesign "${sign_args[@]}" --preserve-metadata=entitlements "$SPARKLE_B/XPCServices/Downloader.xpc"
/usr/bin/codesign "${sign_args[@]}" "$SPARKLE_B/XPCServices/Installer.xpc"
/usr/bin/codesign "${sign_args[@]}" "$APP_FRAMEWORKS/Sparkle.framework"
/usr/bin/codesign "${sign_args[@]}" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

echo "Built $APP_BUNDLE — version $APP_VERSION, identity '$CODE_SIGN_IDENTITY', hardened=$HARDENED_RUNTIME, sparkle_auto=$SPARKLE_AUTO"
