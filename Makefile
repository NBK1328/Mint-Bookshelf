.PHONY: build-core test test-race build-macos build-cli package dmg notarize check-deps fmt

build-core:
	go build -buildmode=c-shared -o build/libkindlecore.dylib ./internal/bridge

test:
	go test ./...

test-race:
	go test -race ./internal/operations ./internal/converter ./internal/device ./internal/library ./internal/storage

fmt:
	gofmt -w cmd internal

DEVELOPER_DIR ?= $(shell if [ -d /Applications/Xcode.app/Contents/Developer ]; then echo /Applications/Xcode.app/Contents/Developer; else xcode-select -p; fi)

build-macos:
	cd macos && DEVELOPER_DIR="$(DEVELOPER_DIR)" swift build

build-cli:
	go build -o build/kindle-core ./cmd/kindle-core

package: build-core build-macos
	./scripts/package.sh

check-deps:
	./scripts/check-deps.sh

dmg: package
	./scripts/dmg.sh

notarize: package
	./scripts/notarize.sh
