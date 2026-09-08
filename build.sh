#!/bin/bash
# Builds Chimtu.app into ./dist using the Swift toolchain (no Xcode required).
set -e
cd "$(dirname "$0")"
# Regenerate sprite frames if missing (they are build products, not tracked in git).
if [ -z "$(ls Resources/frames/*.png 2>/dev/null)" ]; then "${PYTHON:-/usr/bin/python3}" tools/render_sprites.py Resources/frames >/dev/null; fi
# Universal binary: build arm64 and x86_64 separately (no Xcode needed), then lipo.
FLAGS="-c release -Xswiftc -Osize -Xlinker -dead_strip"
swift build $FLAGS --triple arm64-apple-macosx13.0  --build-path .build-arm64 2>&1 | grep -E "error|Build complete" ; test "${PIPESTATUS[0]:-0}" = 0 || exit 1
swift build $FLAGS --triple x86_64-apple-macosx13.0 --build-path .build-x86   2>&1 | grep -E "error|Build complete" ; test "${PIPESTATUS[0]:-0}" = 0 || exit 1
mkdir -p .build && lipo -create .build-arm64/release/Chimtu .build-x86/release/Chimtu -output .build/Chimtu-universal
APP=dist/Chimtu.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/frames"
cp .build/Chimtu-universal "$APP/Contents/MacOS/Chimtu"
strip -x "$APP/Contents/MacOS/Chimtu"
cp Resources/frames/*.png "$APP/Contents/Resources/frames/"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/Chimtu.icns "$APP/Contents/Resources/Chimtu.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP ($(du -sh "$APP" | cut -f1), $(lipo -archs "$APP/Contents/MacOS/Chimtu"))"
# "./build.sh clean" also drops the 200 MB Swift build cache afterwards.
if [ "${1:-}" = "clean" ]; then rm -rf .build .build-arm64 .build-x86; fi
