#!/bin/sh
# Builds Chimtu.app into ./dist using the Swift toolchain (no Xcode required).
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | tail -3
APP=dist/Chimtu.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/frames"
cp .build/release/Chimtu "$APP/Contents/MacOS/Chimtu"
cp Resources/frames/*.png "$APP/Contents/Resources/frames/"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"
