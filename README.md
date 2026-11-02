# Kindle Manager

Native macOS app for browsing a local e-book library and managing files on a
Kindle over USB (MTP).

Status: working prototype. Verified on a physical Kindle Scribe (MTP, one
storage). The app browses the device tree, uploads/downloads files, creates
folders, moves/copies objects, renames files and deletes from the device with
confirmation. MTP transfers expose byte-level progress and cancellation, and
conversion activity is shown inline with progress and cancel.

## Architecture

- SwiftUI front end (Swift 6, macOS 14+)
- Go core compiled to `libkindlecore.dylib`, called through a C ABI with JSON
- libmtp/libusb for device access, SQLite for the local library, optional
  Calibre CLI for conversion

## Features

- Minimal top icon bar: Library, Kindle, Files, Convert
- Library flow: choose a book folder, then browse a minimal list or cover grid
- Kindle section with reconstructed folder tree and device selector
- File and folder upload/download, move, copy, rename and delete through context menus
- Finder-compatible copy/cut/paste, drag-in and drag-out
- Local Finder-style browser with background listing, breadcrumbs and search
- Byte-level MTP transfer progress with cancellation
- Conversion form with inline activity/progress/cancel
- Library search/sort, covers and a book details panel
- Empty-area context menus on both file lists; no redundant action bars
- Light and dark themes with a top-bar toggle
- English, Russian, Spanish, Portuguese, Chinese and French UI with per-language dictionaries
- Freely resizable window with a drag-friendly titlebar

## Localization

Supported languages: English, Russian, Spanish, Portuguese, Simplified Chinese
and French. The language is selected in the top-right menu and remembered
between launches; by default it follows the system locale.

Localization is intentionally easy to extend:

1. Add a case and display name to `AppLanguage` in
   `macos/Sources/KindleManager/Localization.swift`.
2. Create one dictionary file, for example
   `macos/Sources/KindleManager/Localization+German.swift`, with the same keys
   as the existing `L10n.ru` / `L10n.es` tables.
3. Register the dictionary in `L10n.tables`.

UI strings, statuses and error messages use the shared `L10n` API, so no other
view code needs to change. Missing keys fall back to the English source string.

## Build

```sh
brew install pkg-config libmtp libusb
make check-deps
make package
```

Then run the packaged app. `make dmg` creates a DMG; `make notarize` supports
Developer ID/notarization when credentials are supplied. The optional
`.github/workflows/hardware.yml` runs the real-device test on a self-hosted
macOS runner. See `docs/BUILD.md` for manual steps, CI and troubleshooting.

## Tests

```sh
go test ./...
make test-race
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path macos
```

## Notes

- Only modern MTP Kindles are supported; USB mass-storage Kindles are not.
- Multiple Amazon devices are selectable; discovery/reconnect is polled.
- Device delete is permanent and requires confirmation.
- The app keeps one MTP session open; do not run other MTP tools concurrently.
- `docs/` is local-only and ignored by Git.
