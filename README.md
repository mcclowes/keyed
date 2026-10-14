# Keyed

Native macOS text expansion tool. Type a short abbreviation, get a longer snippet. Lives in the menu bar.

Part of the Marginal Utility catalogue, alongside [Clipped](https://github.com/mcclowes/clipped).

## Features

- System-wide text expansion via `CGEventTap`
- Case-aware expansion (ALL CAPS, Title Case inferred from typed input)
- Placeholders: `{date}`, `{time}`, `{datetime}`, `{clipboard}`, `{cursor}`
- Per-app exclusions
- Import from CSV or TextExpander `.textexpander` files
- Snippet groups, search, usage counts
- Duplicate detection on add
- Launch at login
- Onboarding wizard that walks through the Accessibility permission

## Requirements

- macOS 14.0+
- Accessibility permission (mandatory — `CGEventTap` does not work without it)

## Build

```bash
make setup       # Configure git hooks (first time only)
make generate    # Generate Keyed.xcodeproj from project.yml
make build       # Debug build
make test        # Run all tests
make test-package # Check packaging with stubbed build tools
make test-run     # Check launch paths with stubbed build and launch tools
make run         # Build and launch
make release     # Release build (unsigned)
make package     # Release + zip for distribution
make format      # SwiftFormat
make lint        # SwiftFormat --lint + SwiftLint --strict
```

Or directly: `xcodegen generate && xcodebuild -project Keyed.xcodeproj -scheme Keyed build`

`make package` creates and validates a fresh archive before replacing `Keyed.zip`,
so deleted resources don't remain from previous builds and failures preserve the
previous package. It preserves paths with spaces, executable permissions, and
symlinks. `make test-package` checks these
behaviors with temporary fixtures and real archive tools, without building or
launching the app.

`make run` preserves build paths containing spaces and stops if the build or
build-settings lookup fails. `make test-run` checks these behaviors without
building or launching the app.

## Stack

- Swift 6 (strict concurrency)
- SwiftUI + SwiftData
- MV pattern with `@Observable` services — no ViewModels
- Protocol-first services for testability
- `os.Logger` structured logging under `com.mcclowes.keyed`
- XcodeGen (`project.yml` is the source of truth; `.xcodeproj` is gitignored)
- No third-party dependencies in the core expansion engine

## Distribution

Sandbox is **disabled** — required for `CGEventTap`, so Keyed is not App Store compatible. Direct download is the primary distribution channel.

## Project layout

See [CLAUDE.md](./CLAUDE.md) for the full module map, service responsibilities, and test coverage breakdown.
