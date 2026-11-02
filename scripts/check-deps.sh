#!/usr/bin/env bash
set -euo pipefail

failed=0

check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing command: $1" >&2
    failed=1
  fi
}

for command in go swift pkg-config codesign install_name_tool otool plutil; do
  check_command "$command"
done

if ! pkg-config --exists libmtp; then
  echo "missing pkg-config module: libmtp (brew install libmtp)" >&2
  failed=1
fi
if ! pkg-config --exists libusb-1.0; then
  echo "missing pkg-config module: libusb-1.0 (brew install libusb)" >&2
  failed=1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "missing Xcode command line tools" >&2
  failed=1
fi

if [[ -d /Applications/calibre.app ]] || command -v ebook-convert >/dev/null 2>&1; then
  echo "calibre: found"
else
  echo "calibre: optional, not found"
fi

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
echo "dependencies ok"
