# Keyed

Native macOS text expansion tool. Part of the Marginal Utility catalogue (alongside Clipped and Barred).
Menu bar app, Swift 6 + SwiftUI + SwiftData.

## Build

```bash
make generate    # Generate Keyed.xcodeproj from project.yml
make build       # Build debug
make test        # Run all tests
make run         # Build + launch
make release     # Build release (unsigned)
make package     # Release + zip for distribution
make format      # Auto-format with SwiftFormat
make lint        # SwiftFormat --lint + SwiftLint --strict
make setup       # Configure git hooks
```

Or directly: `xcodegen generate && xcodebuild -project Keyed.xcodeproj -scheme Keyed build`

## Architecture

- **MV pattern** with `@Observable` services, no ViewModels
- **Protocol-first** — every service has a protocol for testability (`SnippetStoring`, `SettingsManaging`, `KeystrokeMonitoring`, `TextInjecting`, `AccessibilityChecking`)
- **Swift 6 strict concurrency** enabled (`SWIFT_STRICT_CONCURRENCY: complete`)
- **`@MainActor`** on all services
- **Environment-based DI** — services injected via `.environment()` modifier
- **`withObservationTracking`** for reactive wiring between services (not polling)
- **`os.Logger`** structured logging across all services (`com.mcclowes.keyed` subsystem)
- `project.yml` is the source of truth (XcodeGen). `.xcodeproj` is gitignored.

## Project structure

```
Keyed/
  Sources/
    App/KeyedApp.swift                    # @main entry, AppDelegate, service wiring
    Models/
      Snippet.swift                       # SwiftData @Model
      SnippetGroup.swift                  # SwiftData @Model
      AppExclusion.swift                  # SwiftData @Model
    Services/
      ExpansionEngine.swift               # Orchestrates monitor + buffer + injector
      KeystrokeBuffer.swift               # Ring buffer for typed character tracking
      KeystrokeMonitor.swift              # CGEventTap-based system-wide keystroke capture
      TextInjector.swift                  # Unicode-event text injection + cursor positioning
      AccessibilityService.swift          # AXIsProcessTrusted check/request
      SnippetStore.swift                  # SwiftData CRUD + abbreviation map
      SettingsManager.swift               # UserDefaults-backed @Observable
      StatusBarController.swift           # NSStatusItem + NSPopover
      ImportService.swift                 # CSV + .textexpander file parsing
      CaseTransform.swift                 # Case detection + transformation
      PlaceholderResolver.swift           # {date}, {time}, {clipboard}, {cursor} resolution
    Views/
      SnippetListView.swift               # Main NavigationSplitView with sidebar + list
      SnippetDetailView.swift             # Edit snippet form
      AddSnippetView.swift                # New snippet sheet with duplicate detection
      MenuBarPopoverView.swift            # Status bar popover with pinned snippets
      OnboardingView.swift                # Multi-step first-launch wizard
      SettingsView.swift                  # Tabbed preferences (General + Excluded Apps)
      ExclusionSettingsView.swift         # Per-app exclusion management
      ImportView.swift                    # File picker + preview import UI
  Tests/KeyedTests/
    KeystrokeBufferTests.swift            # Ring buffer logic
    ExpansionEngineTests.swift            # Engine matching, case, disable, backspace
    SnippetStoreTests.swift               # CRUD, search, groups (in-memory SwiftData)
    ImportServiceTests.swift              # CSV + plist parsing
    CaseTransformTests.swift              # Case detection + application
    PlaceholderResolverTests.swift        # Placeholder resolution + cursor offset
    Mocks.swift                           # All mock implementations
  Resources/
    Info.plist                            # LSUIElement: true, Accessibility description
    Keyed.entitlements                    # Sandbox disabled
    Assets.xcassets/
```

## Key modules

- **`ExpansionEngine`** — orchestrates keystroke monitoring + abbreviation matching + text injection. Case-insensitive matching with case-aware expansion, word-boundary enforcement (no mid-word expansion), cached abbreviation list. Placeholder resolution. App exclusions. `isExpanding` guard prevents feedback loops. Exposes `injectSnippet(_:)` for menu-bar pinned-snippet insertion (no abbreviation to delete; resolves placeholders + `{cursor}`).
- **`KeystrokeBuffer`** — fixed-capacity ring buffer tracking typed characters. Supports exact and case-insensitive suffix matching, backspace, reset on boundary keys, and word-boundary lookbehind.
- **`CGEventTapMonitor`** — system-wide keystroke capture via CGEventTap on a dedicated dispatch queue. Handles modifier keys (Option passes through for character composition), boundary keys, unicode extraction (4 UTF-16 code units for non-BMP support), `tapDisabledByTimeout`/`tapDisabledByUserInput` re-enablement. Manages its own retain via `Unmanaged` for lifetime safety.
- **`UnicodeEventTextInjector`** — text injection via `CGEvent.keyboardSetUnicodeString`. No clipboard involvement — deletes the abbreviation with backspaces, then posts the expansion as a series of synthetic key events carrying Unicode string payloads.
- **`SnippetStore`** (`SnippetStoring` protocol) — SwiftData CRUD + abbreviation/exclusion caches. **All UI mutations go through this store** so the engine's live caches stay in sync. Case-insensitive duplicate detection, batched usage-count writes, group management, exclusion management, pin/unpin (`setPinned`, `pinnedSnippets`).
- **`SettingsManager`** (`SettingsManaging` protocol) — UserDefaults-backed `@Observable` with launch-at-login via `SMAppService`.
- **`ImportService`** — RFC 4180 CSV parser (quoted fields, escaped `""` quotes, embedded newlines, case-insensitive headers) and TextExpander `.textexpander` plist parser.
- **`CaseTransform`** — detects ALL CAPS / Title Case from typed input, applies transform to expansion text.
- **`PlaceholderResolver`** — resolves `{date}`, `{time}`, `{datetime}`, `{clipboard}`, `{cursor}` at expansion time.

## Testing

98 tests across 6 files. Run with `make test`.

| File | Tests | Covers |
|------|-------|--------|
| `KeystrokeBufferTests` | 21 | Ring buffer, matching, word boundary, longest match, unicode, overflow, backspace |
| `ExpansionEngineTests` | 22 | Matching, word boundary, ambiguous prefixes, disable, case, backspace, direct injection (pinned) |
| `SnippetStoreTests` | 27 | CRUD, search, groups, usage count, exclusions, duplicate-collision, pinning, staleness regression |
| `ImportServiceTests` | 9 | CSV, escaped quotes, embedded newlines, case-insensitive headers, TextExpander plist |
| `CaseTransformTests` | 10 | Detection + application of case patterns including preservation of existing caps |
| `PlaceholderResolverTests` | 9 | Date/time, cursor offset, strip |

**Mock pattern**: All mocks in `Mocks.swift`. Protocol-based. `MockKeystrokeMonitor`, `MockTextInjector`, `MockAccessibilityService`.
**SwiftData tests**: Use `ModelConfiguration(isStoredInMemoryOnly: true)`.

## Conventions

- **Formatting**: SwiftFormat (120 char, indent 4, balanced closing paren). Run `make format`.
- **Linting**: SwiftLint with force_try/unwrap warnings. Run `make lint`.
- **Naming**: Services are `CamelCase`, protocols are `-ing` suffix (`SnippetStoring`), tests are `test_method_condition_result`.
- **No third-party dependencies** in the core expansion engine.
- **Accessibility labels**: `.help()` on all icon-only buttons.

## Pre-PR checklist

1. `make format` — no changes
2. `make lint` — no errors
3. `make build` — succeeds
4. `make test` — all pass
5. Update this file if services/tests were added or removed

## Important notes

- Sandbox is **disabled** — required for `CGEventTap`. Not App Store compatible. Direct download is the primary distribution channel.
- `LSUIElement = true` — menu bar app, no Dock icon.
- macOS 14.0+ deployment target (SwiftData requirement).
- Accessibility permission is mandatory. The app is non-functional without it.
- Sister projects: [Clipped](https://github.com/mcclowes/clipped) (clipboard manager), Barred (menu bar manager).
