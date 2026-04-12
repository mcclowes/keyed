.PHONY: generate build test clean run release package format lint setup

generate:
	xcodegen generate

build: generate
	xcodebuild -project Keyed.xcodeproj -scheme Keyed -configuration Debug build

test: generate
	xcodebuild -project Keyed.xcodeproj -scheme Keyed -destination 'platform=macOS' test

clean:
	rm -rf DerivedData build
	xcodebuild -project Keyed.xcodeproj -scheme Keyed clean 2>/dev/null || true

run: build
	open "$$(xcodebuild -project Keyed.xcodeproj -scheme Keyed -configuration Debug -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $$NF}')/Keyed.app"

release: generate
	xcodebuild -project Keyed.xcodeproj -scheme Keyed -configuration Release build

package: release
	@BUILT_DIR=$$(xcodebuild -project Keyed.xcodeproj -scheme Keyed -configuration Release -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $$NF}'); \
	cd "$$BUILT_DIR" && zip -r Keyed.zip Keyed.app && \
	echo "Package created at $$BUILT_DIR/Keyed.zip"

format:
	swiftformat Keyed/Sources Keyed/Tests

lint:
	swiftformat --lint Keyed/Sources Keyed/Tests
	swiftlint lint --strict

setup:
	git config core.hooksPath .githooks
	@echo "Git hooks configured."
