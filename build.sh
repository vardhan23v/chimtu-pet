#!/bin/bash
# Builds Chimtu.app into ./dist using the Swift toolchain (no Xcode required).
set -e
cd "$(dirname "$0")"
# Regenerate sprite frames if missing (they are build products, not tracked in git).
if [ -z "$(ls Resources/frames/*.png 2>/dev/null)" ]; then /usr/bin/python3 tools/render_sprites.py Resources/frames >/dev/null; fi
swift build -c release -Xswiftc -Osize -Xlinker -dead_strip 2>&1 | grep -E "error|Build complete" ; test "${PIPESTATUS[0]:-0}" = 0 || exit 1
APP=dist/Chimtu.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/frames"
cp .build/release/Chimtu "$APP/Contents/MacOS/Chimtu"
strip -x "$APP/Contents/MacOS/Chimtu"
cp Resources/frames/*.png "$APP/Contents/Resources/frames/"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/Chimtu.icns "$APP/Contents/Resources/Chimtu.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP ($(du -sh "$APP" | cut -f1))"
# "./build.sh clean" also drops the 200 MB Swift build cache afterwards.
if [ "${1:-}" = "clean" ]; then rm -rf .build; fi
