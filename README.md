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
make run         # Build and launch
make release     # Release build (unsigned)
make package     # Release + zip for distribution
make format      # SwiftFormat
make lint        # SwiftFormat --lint + SwiftLint --strict
```

Or directly: `xcodegen generate && xcodebuild -project Keyed.xcodeproj -scheme Keyed build`

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
