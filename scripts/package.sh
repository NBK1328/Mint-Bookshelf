#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/macos/Mint Bookshelf.app"
DYLIB="$ROOT/build/libkindlecore.dylib"
IDENTITY="${CODESIGN_IDENTITY:--}"

if [[ ! -f "$DYLIB" ]]; then
  echo "missing $DYLIB; run 'make build-core' or use 'make package'" >&2
  exit 1
fi

DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
BIN_DIR="$(cd "$ROOT/macos" && DEVELOPER_DIR="$DEVELOPER_DIR" swift build --show-bin-path)"
BIN="$BIN_DIR/MintBookshelf"
if [[ ! -f "$BIN" ]]; then
  echo "missing $BIN; run 'make build-macos' or use 'make package'" >&2
  exit 1
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/macos/Assets/AppIcon.icns" ]]; then
  cp "$ROOT/macos/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
cp "$BIN" "$APP/Contents/MacOS/MintBookshelf"
install_name_tool -change libkindlecore.dylib @rpath/libkindlecore.dylib \
  "$APP/Contents/MacOS/MintBookshelf"
cp "$DYLIB" "$APP/Contents/Frameworks/libkindlecore.dylib"

# Bundle the MTP libraries so the app does not depend on Homebrew being installed.
LIBMTp_SRC="$(otool -L "$DYLIB" | awk '/libmtp.*\.dylib/ { print $1; exit }')"
LIBUSB_SRC="$(otool -L "$DYLIB" | awk '/libusb.*\.dylib/ { print $1; exit }')"
LIBMTp_NAME="$(basename "$LIBMTp_SRC")"
LIBUSB_NAME="$(basename "$LIBUSB_SRC")"

if [[ ! -f "$LIBMTp_SRC" || ! -f "$LIBUSB_SRC" ]]; then
  echo "missing libmtp or libusb dylib; install libmtp and libusb" >&2
  exit 1
fi

rm -f "$APP/Contents/Frameworks/$LIBMTp_NAME" "$APP/Contents/Frameworks/$LIBUSB_NAME"
cp -L "$LIBMTp_SRC" "$APP/Contents/Frameworks/$LIBMTp_NAME"
cp -L "$LIBUSB_SRC" "$APP/Contents/Frameworks/$LIBUSB_NAME"

install_name_tool -id "@rpath/$LIBMTp_NAME" "$APP/Contents/Frameworks/$LIBMTp_NAME"
install_name_tool -id "@rpath/$LIBUSB_NAME" "$APP/Contents/Frameworks/$LIBUSB_NAME"
install_name_tool -change "$LIBUSB_SRC" "@rpath/$LIBUSB_NAME" "$APP/Contents/Frameworks/$LIBMTp_NAME"
install_name_tool -change "$LIBMTp_SRC" "@rpath/$LIBMTp_NAME" "$APP/Contents/Frameworks/libkindlecore.dylib"
install_name_tool -change "$LIBUSB_SRC" "@rpath/$LIBUSB_NAME" "$APP/Contents/Frameworks/libkindlecore.dylib"

if otool -L "$APP/Contents/Frameworks/libkindlecore.dylib" "$APP/Contents/Frameworks/$LIBMTp_NAME" "$APP/Contents/Frameworks/$LIBUSB_NAME" | grep -E '/opt/homebrew|/usr/local'; then
  echo "bundled dylib still references Homebrew paths" >&2
  exit 1
fi

if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
plutil -lint "$APP/Contents/Info.plist"
file "$APP/Contents/MacOS/MintBookshelf" "$APP/Contents/Frameworks/libkindlecore.dylib"
lipo -archs "$APP/Contents/MacOS/MintBookshelf" | grep -q arm64
lipo -archs "$APP/Contents/Frameworks/libkindlecore.dylib" | grep -q arm64
otool -L "$APP/Contents/MacOS/MintBookshelf" | grep -E 'MintBookshelf|libkindlecore' || true

min_os="$(otool -l "$APP/Contents/Frameworks/libkindlecore.dylib" | awk '/LC_BUILD_VERSION/{found=1} found && /minos/{print $2; exit}')"
if [[ -n "$min_os" && "$min_os" != "14.0" ]]; then
  echo "warning: dylib minimum macOS is $min_os (app target is 14.0); build release artifacts on the oldest supported macOS" >&2
fi

echo "packaged $APP"
