# Keyed

Native macOS text expansion tool. Menu bar app, Swift 6 + SwiftUI + SwiftData.

## Build

```bash
make generate  # Generate Keyed.xcodeproj from project.yml
make build     # Build the app
make test      # Run tests
```

Or directly: `xcodegen generate && xcodebuild -project Keyed.xcodeproj -scheme Keyed build`

## Architecture

- **MV pattern** with `@Observable` services, no ViewModels
- **Protocol-first** — every service has a protocol for testability
- **Swift 6 strict concurrency** enabled (`SWIFT_STRICT_CONCURRENCY: complete`)
- `project.yml` is the source of truth (XcodeGen). `.xcodeproj` is gitignored.

## Key modules

- `ExpansionEngine` — orchestrates keystroke monitoring + abbreviation matching + text injection
- `KeystrokeBuffer` — ring buffer tracking typed characters
- `CGEventTapMonitor` — system-wide keystroke capture via CGEventTap (requires Accessibility permission)
- `ClipboardTextInjector` — replaces typed abbreviation with expansion via clipboard
- `SnippetStore` — SwiftData CRUD + abbreviation map for the engine
- `SettingsManager` — UserDefaults-backed `@Observable`

## Testing

Tests are in `Keyed/Tests/KeyedTests/`. Run with `make test`.
Mock implementations in `Mocks.swift` — protocol-based, used by engine tests.
`SnippetStoreTests` use in-memory `ModelConfiguration`.

## Important notes

- Sandbox is **disabled** — required for `CGEventTap`. Not App Store compatible.
- `LSUIElement = true` — menu bar app, no Dock icon
- macOS 14.0+ deployment target (SwiftData requirement)
