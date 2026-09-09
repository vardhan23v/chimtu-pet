#!/bin/bash
# Builds Chimtu.app into ./dist using the Swift toolchain (no Xcode required).
set -e
cd "$(dirname "$0")"
PY="${PYTHON:-/usr/bin/python3}"
# Regenerate build products if missing: one frame set per skin, procedural sounds.
for skin in shiba cream; do
  if [ -z "$(ls Resources/frames/$skin/*.png 2>/dev/null)" ]; then "$PY" tools/render_sprites.py Resources/frames/$skin $skin >/dev/null; fi
done
if [ -z "$(ls Resources/sounds/*.wav 2>/dev/null)" ]; then "$PY" tools/render_sounds.py Resources/sounds >/dev/null; fi
# Version from the latest tag (v1.8.0 → 1.8.0), build number = commit count.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"; VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
# Universal binary: build arm64 and x86_64 separately (no Xcode needed), then lipo.
FLAGS="-c release -Xswiftc -Osize -Xlinker -dead_strip"
swift build $FLAGS --triple arm64-apple-macosx13.0  --build-path .build-arm64 2>&1 | grep -E "error|Build complete" ; test "${PIPESTATUS[0]:-0}" = 0 || exit 1
swift build $FLAGS --triple x86_64-apple-macosx13.0 --build-path .build-x86   2>&1 | grep -E "error|Build complete" ; test "${PIPESTATUS[0]:-0}" = 0 || exit 1
mkdir -p .build && lipo -create .build-arm64/release/Chimtu .build-x86/release/Chimtu -output .build/Chimtu-universal
APP=dist/Chimtu.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/frames" "$APP/Contents/Resources/sounds"
cp .build/Chimtu-universal "$APP/Contents/MacOS/Chimtu"
strip -x "$APP/Contents/MacOS/Chimtu"
cp -R Resources/frames/shiba Resources/frames/cream "$APP/Contents/Resources/frames/"
cp Resources/sounds/*.wav "$APP/Contents/Resources/sounds/"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp Resources/Chimtu.icns "$APP/Contents/Resources/Chimtu.icns"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --entitlements Chimtu.entitlements --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi
echo "built $APP ($(du -sh "$APP" | cut -f1), $(lipo -archs "$APP/Contents/MacOS/Chimtu"))"
# "./build.sh clean" also drops the 200 MB Swift build cache afterwards.
if [ "${1:-}" = "clean" ]; then rm -rf .build .build-arm64 .build-x86; fi
