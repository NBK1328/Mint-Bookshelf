# Kindle Manager

Native macOS app for browsing a local e-book library and managing files on a
Kindle over USB (MTP).

Status: working prototype. Verified on a physical Kindle Scribe (MTP, one
storage). The app browses the device tree, uploads/downloads files, creates
folders, moves/copies objects, renames files and deletes from the device with
confirmation. MTP transfers report status but not live progress yet.

## Architecture

- SwiftUI front end (Swift 6, macOS 14+)
- Go core compiled to `libkindlecore.dylib`, called through a C ABI with JSON
- libmtp/libusb for device access, SQLite for the local library, optional
  Calibre CLI for conversion

## Features

- Kindle section with reconstructed folder tree
- Upload to a chosen Kindle folder (drag & drop or file picker)
- Download, download-to-folder and move-to-Mac
- Copy/move objects inside the device
- Create folders, rename and delete (with confirmation)
- Local Finder-style browser with navigation, search, hidden files, book filter
- Finder-compatible copy/cut/paste, drag-in and drag-out
- Live operation queue with progress and cancel
- Conversion form with file pickers, format selection and queue hand-off
- Library search and title sorting
- Empty-area context menus on both file lists

## Build

```sh
brew install pkg-config libmtp libusb
make check-deps
make package
```

Then run the packaged app. See `docs/BUILD.md` for manual steps, CI and
troubleshooting.

## Tests

```sh
go test ./...
make test-race
cd macos && swift test
```

## Notes

- Only modern MTP Kindles are supported; USB mass-storage Kindles are not.
- Only the first connected MTP device is opened.
- Device delete is permanent and requires confirmation.
- The app keeps one MTP session open; do not run other MTP tools concurrently.
- `docs/` is local-only and ignored by Git.
