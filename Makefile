.PHONY: build-core test test-race build-macos build-cli package check-deps fmt

build-core:
	go build -buildmode=c-shared -o build/libkindlecore.dylib ./internal/bridge

test:
	go test ./...

test-race:
	go test -race ./internal/operations ./internal/converter ./internal/device ./internal/library ./internal/storage

fmt:
	gofmt -w cmd internal

build-macos:
	cd macos && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build

build-cli:
	go build -o build/kindle-core ./cmd/kindle-core

package: build-core build-macos
	./scripts/package.sh

check-deps:
	./scripts/check-deps.sh
