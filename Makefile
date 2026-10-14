.PHONY: generate build test test-package test-bump-helper test-run clean run release package format lint setup

generate:
	xcodegen generate

build: generate
	xcodebuild -project Keyed.xcodeproj -scheme Keyed -configuration Debug build

test: generate
	xcodebuild -project Keyed.xcodeproj -scheme Keyed -destination 'platform=macOS' test

test-package:
	bash scripts/test-package.sh

test-bump-helper:
	bash scripts/test-bump-version.sh

test-run:
	bash scripts/test-run.sh

clean:
	rm -rf DerivedData build
	xcodebuild -project Keyed.xcodeproj -scheme Keyed clean 2>/dev/null || true

run: build
	@BUILD_SETTINGS=$$(xcodebuild -project Keyed.xcodeproj -scheme Keyed -configuration Debug -showBuildSettings) || exit $$?; \
	BUILT_DIR=$$(printf '%s\n' "$$BUILD_SETTINGS" | awk '/^[[:space:]]*BUILT_PRODUCTS_DIR = / { sub(/^[[:space:]]*BUILT_PRODUCTS_DIR = /, ""); print; exit }'); \
	test -n "$$BUILT_DIR" || { echo 'Xcode did not report a build products directory.' >&2; exit 1; }; \
	open "$$BUILT_DIR/Keyed.app"

release: generate
	xcodebuild -project Keyed.xcodeproj -scheme Keyed -configuration Release build

package: release
	@BUILT_DIR=$$(xcodebuild -project Keyed.xcodeproj -scheme Keyed -configuration Release -showBuildSettings 2>/dev/null | awk '/^[[:space:]]*BUILT_PRODUCTS_DIR = / { sub(/^[[:space:]]*BUILT_PRODUCTS_DIR = /, ""); print; exit }'); \
	ditto -c -k --keepParent "$$BUILT_DIR/Keyed.app" "$$BUILT_DIR/Keyed.zip" && \
	echo "Package created at $$BUILT_DIR/Keyed.zip"

format:
	swiftformat Keyed/Sources Keyed/Tests

lint:
	swiftformat --lint Keyed/Sources Keyed/Tests
	swiftlint lint --strict

setup:
	git config core.hooksPath .githooks
	@echo "Git hooks configured."
