#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/macos/Mint Bookshelf.app"
DMG="${DMG_PATH:-$ROOT/build/MintBookshelf.dmg}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

if [[ ! -d "$APP" ]]; then
  echo "missing $APP; run 'make package'" >&2
  exit 1
fi

cp -R "$APP" "$STAGE/Mint Bookshelf.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$(dirname "$DMG")"
hdiutil create -volname "Mint Bookshelf" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "created $DMG"
