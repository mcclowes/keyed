.PHONY: generate build test clean run

generate:
	xcodegen generate

build: generate
	xcodebuild -project Keyed.xcodeproj -scheme Keyed -configuration Debug build

test: generate
	xcodebuild -project Keyed.xcodeproj -scheme KeyedTests -configuration Debug test

clean:
	rm -rf DerivedData build
	xcodebuild -project Keyed.xcodeproj -scheme Keyed clean 2>/dev/null || true

run: build
	open build/Debug/Keyed.app
