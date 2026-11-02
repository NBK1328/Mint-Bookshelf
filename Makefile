.PHONY: build-core test build-macos build-cli

build-core:
	go build -buildmode=c-shared -o build/libkindlecore.dylib ./internal/bridge

test:
	go test ./...

build-macos:
	cd macos && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build

build-cli:
	go build -o build/kindle-core ./cmd/kindle-core
