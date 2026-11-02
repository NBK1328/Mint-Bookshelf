#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/macos/KindleManager.app"
BIN="$ROOT/macos/.build/out/Products/Debug/KindleManager"
DYLIB="$ROOT/build/libkindlecore.dylib"
IDENTITY="${CODESIGN_IDENTITY:--}"

if [[ ! -f "$DYLIB" ]]; then
  echo "missing $DYLIB; run 'make build-core' or use 'make package'" >&2
  exit 1
fi
if [[ ! -f "$BIN" ]]; then
  echo "missing $BIN; run 'make build-macos' or use 'make package'" >&2
  exit 1
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/macos/Assets/AppIcon.icns" ]]; then
  cp "$ROOT/macos/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
cp "$BIN" "$APP/Contents/MacOS/KindleManager"
install_name_tool -change libkindlecore.dylib @rpath/libkindlecore.dylib \
  "$APP/Contents/MacOS/KindleManager"
cp "$DYLIB" "$APP/Contents/Frameworks/libkindlecore.dylib"

if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
plutil -lint "$APP/Contents/Info.plist"
file "$APP/Contents/MacOS/KindleManager" "$APP/Contents/Frameworks/libkindlecore.dylib"
lipo -archs "$APP/Contents/MacOS/KindleManager" | grep -q arm64
lipo -archs "$APP/Contents/Frameworks/libkindlecore.dylib" | grep -q arm64
otool -L "$APP/Contents/MacOS/KindleManager" | grep -E 'KindleManager|libkindlecore' || true

min_os="$(otool -l "$APP/Contents/Frameworks/libkindlecore.dylib" | awk '/LC_BUILD_VERSION/{found=1} found && /minos/{print $2; exit}')"
if [[ -n "$min_os" && "$min_os" != "14.0" ]]; then
  echo "warning: dylib minimum macOS is $min_os (app target is 14.0); build release artifacts on the oldest supported macOS" >&2
fi

echo "packaged $APP"
