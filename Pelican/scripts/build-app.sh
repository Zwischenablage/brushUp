#!/usr/bin/env bash
# Builds an optimised arm64 Pelican.app into ./build and ad-hoc signs it.
#   ./scripts/build-app.sh            # build/Pelican.app
#   ./scripts/build-app.sh --install  # also copy to /Applications
set -euo pipefail

cd "$(dirname "$0")/.."
ARCH="${ARCH:-arm64}"
CONFIG=release
APP="build/Pelican.app"

swift build -c "$CONFIG" --arch "$ARCH"
BIN_DIR="$(swift build -c "$CONFIG" --arch "$ARCH" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Pelican" "$APP/Contents/MacOS/Pelican"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi

# Ad-hoc signature. For Full Disk Access to stick across rebuilds, sign with a stable
# identity instead:  SIGN_IDENTITY="Apple Development: you@example.com" ./scripts/build-app.sh
codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"

echo "Built $(pwd)/$APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Pelican.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Pelican.app"
fi
