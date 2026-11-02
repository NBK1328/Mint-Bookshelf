# Kindle Manager

Native macOS app for browsing a local e-book library and managing files on a
Kindle over USB (MTP).

Status: working prototype. Verified on a physical Kindle Scribe (MTP, one
storage). The app browses the device tree, uploads/downloads files, creates
folders, moves/copies objects, renames files and deletes from the device with
confirmation. MTP transfers expose byte-level progress and cancellation, and
conversion runs through a live operation queue.

## Architecture

- SwiftUI front end (Swift 6, macOS 14+)
- Go core compiled to `libkindlecore.dylib`, called through a C ABI with JSON
- libmtp/libusb for device access, SQLite for the local library, optional
  Calibre CLI for conversion

## Features

- Kindle section with reconstructed folder tree and device selector
- Upload files or whole folders (drag & drop, picker, clipboard)
- Download, download-to-folder, move-to-Mac and drag-out with on-demand download
- Copy/move objects inside the device, recursive folder delete with confirmation
- Local Finder-style browser with background listing, navigation, search and filters
- Finder-compatible copy/cut/paste, drag-in and drag-out
- Live operation queue with progress and cancel
- Byte-level MTP transfer progress with cancellation
- Conversion form with file pickers, format selection and queue hand-off
- Library search/sort, covers and a book details panel
- Empty-area context menus on both file lists

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
