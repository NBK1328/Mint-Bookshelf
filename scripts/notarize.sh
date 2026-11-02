#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/macos/KindleManager.app"
IDENTITY="${CODESIGN_IDENTITY:--}"

if [[ "$IDENTITY" == "-" ]]; then
  echo "set CODESIGN_IDENTITY to a Developer ID Application certificate" >&2
  exit 1
fi
if [[ -z "${APPLE_ID:-}" || -z "${TEAM_ID:-}" || -z "${APP_PASSWORD:-}" ]]; then
  echo "set APPLE_ID, TEAM_ID and APP_PASSWORD for notarytool" >&2
  exit 1
fi
if [[ ! -d "$APP" ]]; then
  echo "missing $APP; run 'make package'" >&2
  exit 1
fi

codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
ZIP="$ROOT/build/KindleManager-notarize.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=4 "$APP"
echo "notarized $APP"
