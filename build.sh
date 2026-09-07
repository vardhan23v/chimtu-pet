#!/bin/bash
# Builds Chimtu.app into ./dist using the Swift toolchain (no Xcode required).
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -E "error|Build complete" ; test "${PIPESTATUS[0]:-0}" = 0 || exit 1
APP=dist/Chimtu.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/frames"
cp .build/release/Chimtu "$APP/Contents/MacOS/Chimtu"
cp Resources/frames/*.png "$APP/Contents/Resources/frames/"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/Chimtu.icns "$APP/Contents/Resources/Chimtu.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"
