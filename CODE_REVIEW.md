# Keyed — senior code review

A holistic, opinionated review of the Keyed codebase from a principal-engineer perspective. The goal is not to make the code sound bad for sport; it is to surface real bugs, sharpen the team's instincts, and leave every reviewer-in-training with a concrete mental model of "what would I have asked here?"

The codebase is in good shape for a pre-1.0 menu bar app. The architecture (MV with `@Observable`, protocol-first services, SwiftData, environment DI) is exactly what I would recommend. What follows are the things I would not ship without fixing, alongside the smaller crimes that tell you the team hasn't seen this code stressed yet.

---

## 1. Bugs that will actually bite users

These are not style issues. Each one is a reproducible failure mode in the current tree.

### 1.1 `UnicodeEventTextInjector` splits grapheme clusters on chunk boundaries — any non-BMP character in a long expansion is corrupted

`Keyed/Sources/Services/TextInjector.swift:55-75`

```swift
private func postUnicodeString(_ string: String) {
    let chunkSize = 20
    let utf16 = Array(string.utf16)
    var index = 0
    while index < utf16.count {
        let end = min(index + chunkSize, utf16.count)
        let chunk = Array(utf16[index..<end])
        ...
    }
}
```

Splitting at a flat 20-UTF-16-code-unit boundary will happily cut a surrogate pair in half. Anything above U+FFFF — emoji, CJK extensions, flag sequences, family emoji, skin-tone modifiers, ZWJ joiners — produces invalid UTF-16 when the boundary lands mid-cluster. The first chunk ends with a lone high surrogate, the next begins with a lone low surrogate, and the receiving app gets two garbage characters.

This is exactly the kind of bug that passes the test suite (no emoji in test fixtures) and ships because "it worked for the typical user." It absolutely will not work for the user whose signature ends with 🎉 or the user whose name contains a skin-toned 👋🏽.

**Fix**: chunk by grapheme cluster, not code unit. Advance through `string.indices` and emit whichever prefix still fits the 20-code-unit budget, never breaking a `Character`.

**Teaching point**: any time you see `.utf16` + arithmetic, ask "what happens at the code unit that is half of a surrogate pair?" The test should include a string like `"aaaaaaaaaaaaaaaaaa🎉bbbbbbbbbbbbbbbbbbb"` that is designed to land the emoji on the chunk boundary.

### 1.2 `{cursor}` offset is computed against the *un-resolved* template

`Keyed/Sources/Services/PlaceholderResolver.swift:46-50`
`Keyed/Sources/Services/ExpansionEngine.swift:106-120`

```swift
let cursorOffset = placeholderResolver.cursorOffset(in: caseExpansion)
let resolvedExpansion = placeholderResolver.resolve(
    placeholderResolver.stripCursorPlaceholder(caseExpansion)
)
```

`cursorOffset(in:)` counts characters after `{cursor}` in the raw template — which still contains `{date}`, `{time}`, `{clipboard}`, etc. After resolution those placeholders expand to arbitrary lengths. The final cursor position is then off by `(resolved length) − (placeholder length)`.

Pathological example: expansion `"{cursor} — logged at {datetime}"`. The cursor offset is computed as `" — logged at {datetime}".count == 23`. After resolution `{datetime}` becomes `"April 10, 2026 at 3:42 PM".count == 25`, adding 15 characters. The injector then backs up 23 characters from the new cursor, which lands the caret halfway through `"April"` instead of at the intended position.

**Fix**: resolve first, then compute the offset of the (stripped) `{cursor}` marker *after* resolution — or compute the offset from the tail of the final string. Either way, don't measure the template and inject into the result.

**Teaching point**: when two transformations compose, always think about whether offsets are measured in "source space" or "target space," and make that invariant explicit.

### 1.3 Menu-bar popover `@Query` has no `ModelContainer` in its environment

`Keyed/Sources/Services/StatusBarController.swift:34-43`
`Keyed/Sources/Views/MenuBarPopoverView.swift:7`

```swift
let popoverView = MenuBarPopoverView(...)
    .environment(settingsManager)
    .environment(snippetStore)
    .environment(accessibilityService)
popover.contentViewController = NSHostingController(rootView: popoverView)
```

`MenuBarPopoverView` uses `@Query private var snippets: [Snippet]`. `@Query` reads its `ModelContext` from the environment set by `.modelContainer(...)`. The Scene-level containers in `KeyedApp.swift` only attach to the `WindowGroup` and `Settings` scenes — the popover is hosted through a detached `NSHostingController` that never gets `.modelContainer(appDelegate.modelContainer)`. Depending on SwiftData runtime behavior, the query silently returns an empty array or logs a warning to the console that nobody sees.

This is a silently-broken feature waiting for an "it works on my machine" bug report. Either the pinned snippets are populated via a separate `snippetStore.pinnedSnippets()` call (in which case the `@Query` is dead code) or they are actually broken and nobody has noticed because the starter set has nothing pinned.

**Fix**: apply `.modelContainer(modelContainer)` to the popover's root view, or drop `@Query` and drive the list from `snippetStore.pinnedSnippets()` via a `withObservationTracking` loop.

**Teaching point**: every time you reach for `@Query`, ask "which environment is this view hosted in, and does that environment actually carry a `ModelContainer`?" `@Query` is not automatic — it's a handshake with the environment.

### 1.4 `hasCompletedOnboarding` is set the moment the welcome window *opens*, not when it completes

`Keyed/Sources/App/KeyedApp.swift:203-205`

```swift
if initialStep == .welcome {
    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
}
```

If the user quits the app mid-onboarding, they never see the welcome flow again. The flag is named after a terminal condition ("completed") but is being toggled at an initial condition ("displayed"). That is a logic bug, not a naming quibble — the name describes a user-visible invariant and the code violates it.

**Fix**: set this flag from `OnboardingView` when the user actually advances past the last step.

**Teaching point**: boolean flags in UserDefaults should be named for the condition they guard. If the name says "completed" and the toggle point is "shown," you've created a lie that will be read by future code as truth.

### 1.5 In-memory fallback on `ModelContainer` failure silently destroys user data

`Keyed/Sources/App/KeyedApp.swift:42-55`

```swift
// Fallback: reset the store if schema migration fails.
// Pre-1.0; no meaningful data loss risk yet.
let config = ModelConfiguration(isStoredInMemoryOnly: true)
modelContainer = try ModelContainer(
    for: Snippet.self, SnippetGroup.self, AppExclusion.self,
    configurations: config
)
```

The app silently discards the on-disk store and boots with an empty, in-memory container when SwiftData can't open the file. Reasons that can cause this in the wild: permission issues, disk full, iCloud sync weirdness, a beta macOS version, a user copying the app bundle incorrectly. Any of those will wipe the user's snippet library on launch with no warning, no backup, no mention in the UI.

"Pre-1.0, no meaningful data loss risk" is a statement about *today*, not about the instant this code is shipped. The moment you put the app in front of a user who has typed a meaningful `.csv` import or hand-crafted 30 snippets, this clause becomes a landmine.

**Fix**: if the main container fails, surface an explicit error state in the UI ("Keyed could not open its database. Reveal in Finder / Quit") rather than pretending nothing happened. At minimum, move the failed store aside (`keyed.store.corrupt-<timestamp>`) so the user can recover it.

**Teaching point**: defaulting to an in-memory store on failure is the software equivalent of "if the engine won't start, pretend the car is floating." Always prefer a loud, recoverable failure to a silent, destructive one.

### 1.6 `isExpanding` guard runs on the main thread, but the tap is not paused during injection

`Keyed/Sources/Services/ExpansionEngine.swift:110-125`

```swift
isExpanding = true
buffer.reset()
...
Task { [weak self] in
    ...
    await injector.replaceText(...)
    await MainActor.run {
        self.isExpanding = false
        ...
    }
}
```

Logic is sound *in isolation* — synthetic events received during expansion are dropped because `isExpanding == true`. But because `replaceText` is not marked `async` at the call-site boundary (it's a `Sendable` class with a sync-body `async` stub), the work blocks the current execution context. Worse, it blocks the main thread — every `postKey` and `postUnicodeString` is a synchronous `CGEvent.post` called from a MainActor-hopping task.

For a four-character signature that is invisible. For a 500-character paragraph, the main thread is unresponsive for long enough that the user notices a hitch. And because the tap is live during injection, any queued keystrokes the user typed in that window hit `isExpanding == true` and get dropped — that is, the keystrokes are still processed by the target app (the tap passes them through) but the abbreviation buffer doesn't see them. Net effect: typing ahead during a long expansion will desynchronize the buffer from the text the user actually has in the target field, and the next abbreviation they try will behave unpredictably.

**Fix**: push injection to a background queue (`DispatchQueue.global(qos: .userInteractive)`) and don't block the main actor for the duration of the synthetic stream. Also pause the tap (`CGEvent.tapEnable(tap:enable: false)`) while injecting, and re-enable it after the final event. That's the canonical way to avoid feedback loops without a software flag.

**Teaching point**: "I set a flag to ignore re-entrant events" is the beginning of the solution, not the end. Always ask: during the time the flag is set, what else is running, and what state are they reading?

### 1.7 Ring-buffer word-boundary check lies after the buffer overflows

`Keyed/Sources/Services/KeystrokeBuffer.swift:115-122`

```swift
func hasWordBoundaryBefore(suffixLength: Int) -> Bool {
    guard suffixLength > 0, suffixLength <= size else { return false }
    let boundaryPosition = size - suffixLength
    if boundaryPosition == 0 { return true }
    ...
}
```

"At the start of the buffer" is treated as a word boundary. That's true at app launch, but not after the buffer has cycled. Once the ring has overflowed, `boundaryPosition == 0` means "the abbreviation occupies the entire 128-character window," which is definitely not the same as "the abbreviation sits at the start of a word."

Practical impact: a user types a long paragraph (>128 chars) without any boundary keys (rare but possible in rapid-fire chat apps, code editors, URL bars). An abbreviation that matches the full buffer will fire without a real word boundary. Edge case — but the fix is two lines and the test to prove it is one.

**Fix**: track whether the buffer has overflowed (a simple `hasWrapped` bool). If wrapped, "suffix fills the buffer" must be treated as "unknown" and reject the match, or always require one boundary character to be present in the stored window.

**Teaching point**: ring buffers replace "we know what's before the start" with "we know what's in the window." Every invariant that used to lean on "start of input" needs to be re-examined.

### 1.8 `incrementUsageCount` does an O(n) full fetch per expansion

`Keyed/Sources/Services/SnippetStore.swift:151-159, 190-193`

```swift
func incrementUsageCount(for abbreviation: String) {
    guard let snippet = findSnippet(byAbbreviationCaseInsensitive: abbreviation) else { return }
    ...
}

private func findSnippet(byAbbreviationCaseInsensitive abbreviation: String) -> Snippet? {
    let lowered = abbreviation.lowercased()
    return allSnippets().first { $0.abbreviation.lowercased() == lowered }
}
```

Every expansion fires a `FetchDescriptor` for *all* snippets plus a linear scan. For a user with 1,000 snippets, this is a 1,000-row fetch on the main actor on every expansion — which happens, by definition, while the user is typing. You're paying milliseconds of main-thread time on every hot-path event.

**Fix**: keep a `[String: PersistentIdentifier]` (lowercase-keyed) alongside the abbreviation map; look up by identifier, fetch the single object. Or even simpler: cache the `Snippet` reference itself in a dictionary on rebuild and invalidate on mutation.

**Teaching point**: hot paths deserve their own benchmarks. If you can articulate "this runs on every keystroke," you should be able to articulate its worst-case complexity without guessing.

### 1.9 The engine's "case-sensitive first, case-insensitive second" ordering can prefer a shorter exact-case match over a longer fuzzy one

`Keyed/Sources/Services/KeystrokeBuffer.swift:103-111`

```swift
func longestSuffixMatch(in candidates: [String]) -> String? {
    for candidate in candidates where hasSuffix(candidate) {
        return candidate
    }
    for candidate in candidates where hasSuffixCaseInsensitive(candidate) {
        return candidate
    }
    return nil
}
```

The method is documented as "longest match wins." With the two-pass structure, that is false for mixed-case inputs. Example: abbreviations `["abcdefgh", "CD"]`. If the user types `" abCD"`, the first pass finds `"CD"` exact-case and returns it — even though `"abcdefgh"` is eight characters longer and matches case-insensitively. The documented contract and the actual behavior disagree.

Either fix the behavior (walk once, treating exact match as a tiebreaker only within the same length) or rewrite the doc comment to reflect reality. I recommend fixing the behavior; most users expect length to dominate.

**Teaching point**: when a function claims an invariant in a doc comment, write the test that *proves* that invariant. If the test is awkward to write, the comment is probably lying.

### 1.10 `DistributedNotificationCenter` + `Task.sleep(150ms)` is a race workaround, not a solution

`Keyed/Sources/Services/AccessibilityService.swift:28-34`

```swift
Task { @MainActor [weak self] in
    try? await Task.sleep(for: .milliseconds(150))
    self?.refresh()
}
```

There is no upper bound on how long macOS takes to update `AXIsProcessTrusted` after the notification fires. 150 ms is a coin flip — it works on a fast Mac, fails on a loaded CI runner or an old machine. This is the kind of code you ship once, get one bug report a year about, and spend half a day re-debugging because it's timing-dependent.

**Fix**: poll with exponential backoff until the value actually flips, or retry once if the first read disagrees with the notification. Either way, don't hard-code a guess.

**Teaching point**: whenever you write `sleep` inside production code, write a comment with the load-bearing assumption and the failure mode if the assumption is wrong. If you can't, the code isn't ready.

---

## 2. Architectural tension points

Smaller than a bug but bigger than a nit. Each of these suggests the codebase has not yet been stressed by real scale or real users.

### 2.1 `rebuildAbbreviationMap()` is O(n) on every mutation

Every `addSnippet` / `updateSnippet` / `deleteSnippet` / seed-defaults call re-fetches every snippet and rebuilds the entire map. For a hundred snippets this is invisible. For ten thousand (power users importing from TextExpander) it is not free. The mutations are incremental — the map updates should be too.

### 2.2 `SnippetStoring` protocol and `SnippetStore` type share the same environment key

`SnippetListView` etc. use `@Environment(SnippetStore.self)` rather than the protocol. That locks every view to the concrete class and removes the testability the protocol was introduced to provide. Either the protocol has value (and should be injected) or it doesn't (and should be deleted). Right now you're paying the cost of both.

### 2.3 `StatusBarController` is the second place that owns wiring

`AppDelegate` constructs and injects services; `StatusBarController` *also* builds the popover's view graph and applies environment values. That's two places encoding the same knowledge about what the popover needs. As the graph grows (accessibility, settings, store, engine, a future theme manager), these two call sites will drift. Extract a single `makePopoverRoot()` function that takes all dependencies explicitly.

### 2.4 `ExpansionEngine.injectSnippet` doesn't honor `isEnabled` or excluded apps

`Keyed/Sources/Services/ExpansionEngine.swift:132-146`

The keystroke path checks both the enabled flag and the excluded-apps list before expanding. The pinned-snippet injection path checks neither. The result: a user who has disabled Keyed via the menu bar toggle can still inject a snippet from the same menu bar popover, and a user who has excluded their password manager can still click a pinned snippet into it. Both are trivially wrong.

At minimum, `injectSnippet` should early-return on `!isEnabled` and on the current frontmost app being in `excludedBundleIDs`. Better: the menu bar pinned section should grey out or remove pinned snippets when the target is excluded.

### 2.5 `CGEventTapMonitor` is manually juggling retain semantics, locks, and CFRunLoop ownership

`Keyed/Sources/Services/KeystrokeMonitor.swift`

This file is correct today but has five interlocking concerns: `Unmanaged<Self>` retain lifetime, an `NSLock` protecting state, a dedicated dispatch queue, a `CFRunLoop` that it calls `CFRunLoopRun` on inside that queue, and two failure paths that each manually unwind the retain. The `deinit { stop() }` takes the same lock, which is technically fine but depends on the invariant that nothing calls into the monitor from another thread during deinit.

This is the sort of code a senior Swift engineer should re-read with a pencil. It would benefit from:

- An explicit state machine (`.idle`, `.starting`, `.running`, `.stopping`) rather than optional fields. Any method guards against invalid transitions.
- Dropping `NSLock` and making the public API `@MainActor`. The tap fires on a background queue and bounces into main for state access.
- A comment explaining *why* `CFRunLoopRun` is called from inside `queue.async`. (Because `CFMachPortCreateRunLoopSource` binds the source to that run loop, which has to keep running to receive events.) Without that comment, a future engineer will assume the `CFRunLoopRun` is a mistake and delete it.

### 2.6 The buffer-reset-on-overflow invariant is not documented

`KeystrokeBuffer` is agnostic about what counts as "start of input." The engine assumes "buffer start == nothing typed before" (see §1.7). That coupling is not spelled out anywhere. Either `KeystrokeBuffer` should expose an explicit `hasOverflowed` property that the engine checks, or `ExpansionEngine.checkForMatch` should be rewritten to stop depending on that property.

### 2.7 Mock classes live alongside production tests but there is no abstraction for the timing

`ExpansionEngineTests` uses `await waitForInjector()` to flush scheduled tasks. That's a hint: the engine's `Task { @MainActor in handleKeystroke(event) }` pattern makes every test implicitly async and forces the test writer to know about the task hop. A nicer design is an `EngineTestHarness` that takes a synchronous-mode flag or exposes a `flush()` entry point, so the tests don't each implement the same polling dance.

---

## 3. Edge cases not yet spotted

A checklist of things the test suite should exercise but doesn't (yet).

- **Surrogate pairs / ZWJ sequences** in expansion text crossing the 20-UTF-16-unit chunk boundary (see §1.1).
- **Surrogate pairs in abbreviations** themselves. The buffer stores `Character` (grapheme) but the engine counts `matched.count` for the backspace loop — verify a `"🧑‍💻"` abbreviation produces exactly one backspace and that target apps treat that as deletion of one cluster (they vary).
- **Combining marks typed as separate events**. If `"é"` arrives as `"e"` + `"́"` in two separate `.character(...)` events, the buffer stores two `Character`s and can never match an abbreviation containing a pre-composed `"é"`. Worth a test with a real decomposed sequence.
- **`{clipboard}` containing other placeholders**. Currently clipboard substitution runs last, so `{date}` inside a clipboard payload won't resolve. Is that the intended contract? Write the test that pins it down, then document it.
- **`{clipboard}` is empty / binary / huge**. What happens if the clipboard holds 5 MB of text? Currently you inject all of it. Consider a length cap.
- **`{clipboard}` privacy**. Reading the clipboard on every expansion that references it quietly exposes whatever is on the clipboard — including passwords from a password manager — into the target app. This is a feature, but it should be surfaced and probably gated by an explicit opt-in per snippet.
- **Concurrent expansion triggers**. User types `:sigxyz` where both `:sig` and `:sigxyz` are abbreviations. Current code fires on the first match and resets; that's fine. Now test with overlapping prefixes like `:sig` and `:signal` typed rapidly (`:sig` fires before `:signal` can form). Is that the documented behavior? If yes, write the test.
- **Backspace past buffer empty**. The buffer handles `backspace()` on an empty buffer correctly, but `ExpansionEngine` doesn't. Once the user has backspaced into text typed *before* the buffer was tracking, the engine has no idea what the current word looks like, and the next typed character is treated as if the cursor were at the start of input. Likely to cause false expansions inside existing words.
- **Rapid typing during expansion**. Queue a dozen keystrokes while `isExpanding == true` and verify they are either all dropped or all kept, consistently. Right now "they all get dropped but the target app still receives them" is surprising.
- **Tap timeout re-enable**. `tapDisabledByTimeout` is handled by re-enabling the tap, but the buffer isn't reset. The buffer now contains characters that may not reflect what the user typed during the blackout. Reset-on-reenable is safer.
- **Abbreviation collision with synthetic events**. If a user has an abbreviation `";date"` and the expansion of another snippet resolves `{date}` into text that happens to contain `";date"` as a substring, the posted synthetic events could (in theory) re-trigger. `isExpanding` saves you, but only because you posted inside a single main-actor hop. Move injection off the main thread (which you should) and this becomes a real race to reason about.
- **Excluded-app switch mid-expansion**. User triggers expansion in app A, then before the async injection begins, switches to excluded app B. The expansion lands in B. Rare, but real.
- **Launch-at-login failure**. `SettingsManager.updateLoginItem()` swallows the error with no user feedback. A user who toggles "Launch at login" and then finds it didn't work has no way to know.
- **Seed-defaults idempotency across reinstalls**. The `hasSeededDefaultSnippets` flag is in UserDefaults, which is per-app-bundle. Wipe the app's Application Support (to reset the SwiftData store) but leave `~/Library/Preferences` alone (because users rarely clean both), and you relaunch into an empty store with the "already seeded" flag true. Now the user has no snippets *and* no starter set, and the only path out is a reinstall that also wipes preferences. Consider checking the actual snippet count as well.
- **Import conflict resolution**. `ImportService` doesn't tell the caller about collisions; the caller calls `addSnippet` which throws on duplicates. What does `ImportView` do with a partial import where row 5 of 20 failed? Silent skip, loud error, per-row choice? Needs a decided policy.
- **CSV with BOM / CRLF-only / tab-separated**. The tokenizer handles `\r\n` and `\n`, but not BOM-prefixed input. A user exporting from Excel will send you a BOM. Strip it.

---

## 4. Style, maintainability, small wins

None of these alone warrant a rewrite. Together they are the difference between "ok codebase" and "codebase I look forward to working in."

### 4.1 Dead code in `KeystrokeBuffer`

`firstMatch(from:)` and `firstMatchCaseInsensitive(from:)` (`Keyed/Sources/Services/KeystrokeBuffer.swift:93-99`) take a `Set<String>` and scan it. `ExpansionEngine` doesn't use them — it uses `longestSuffixMatch(in:)`. Delete them. Unused code is lies that compile.

### 4.2 `handleKeystrokeForTesting` is a smell

`Keyed/Sources/Services/ExpansionEngine.swift:148-152`

```swift
#if DEBUG
    func handleKeystrokeForTesting(_ event: KeystrokeEvent) {
        handleKeystroke(event)
    }
#endif
```

Either `handleKeystroke` should be internal (which it already is) or the tests should drive the `MockKeystrokeMonitor` through the public API. Debug-only test affordances invite divergence between tested and shipped behavior.

### 4.3 `containsPlaceholder` checks `text.contains("{")`

`Keyed/Sources/Services/PlaceholderResolver.swift:56-58`

That's not a placeholder check, that's a "no left brace" shortcut. Fine optimization, but name it honestly: `hasNoBraces`, or inline it.

### 4.4 `DefaultSnippets` / `DefaultExclusions` are static arrays at module scope

That's fine today, but the moment you want to A/B test defaults or ship locale-specific ones, these become a problem. Consider loading from a resource file so product can edit them without a code change.

### 4.5 `SnippetStore.flushPendingWrites()` is public but not on the protocol

`Keyed/Sources/Services/SnippetStore.swift:164-168`

It's called by `AppDelegate.applicationWillTerminate`. That means any mock used in tests is missing it, and any replacement implementation quietly won't be flushed on shutdown. Put it on the protocol.

### 4.6 `SnippetStore.findSnippet(byAbbreviation:)` is public but only used by tests

If the only reason a method exists is to support the test file, make it `internal` with an `@testable` import (which is what you already have) or fold it into a test helper. Methods in production APIs should have production callers.

### 4.7 `CaseTransform.detect` silently misclassifies single-letter abbreviations

`Keyed/Sources/Services/CaseTransform.swift:10-28`

A one-letter abbreviation where the user types a single uppercase letter is detected as `.allUpper`. That's defensible but ambiguous: it's also `.titleCase`. Write the tests that document what the code actually does, even for the "doesn't matter" cases, so future refactors don't silently change the behavior.

### 4.8 `SettingsManager.updateLoginItem` swallows errors with a comment that admits it's wrong

```swift
} catch {
    // Silently fail — login item management can fail in debug builds
}
```

The "debug build" rationale is a footgun. In release, the catch still eats the error. At minimum log it. Better: only suppress the error in `#if DEBUG`.

### 4.9 `Snippet.abbreviation` has `@Attribute(.unique)` but the store enforces case-insensitive uniqueness

`Keyed/Sources/Models/Snippet.swift:7`

The model's unique constraint is case-sensitive; the store layer enforces case-insensitive. If someone ever inserts a `Snippet` bypassing `SnippetStore.addSnippet` (a seed file, a migration, a unit test), the model-level constraint fires only for exact-case duplicates. Either enforce case-insensitive uniqueness at the store always *and* document it, or store a lowercased mirror column and make that the unique key.

### 4.10 The tests are called `test_thing_condition_result` but with camelCase components

`KeyedTests/ExpansionEngineTests.swift` uses `test_typingAbbreviation_triggersExpansion`. The CLAUDE.md promises `test_method_condition_result` (snake_case everywhere). Pick one and be strict.

### 4.11 `KeyedApp.swift` wires four separate `observe…Loop()` methods, each of which self-restarts `withObservationTracking`

`Keyed/Sources/App/KeyedApp.swift:121-175`

This is the documented pattern for continuous observation, but doing it four times (settings, abbreviations, exclusions, accessibility) is a cue to build one generic helper:

```swift
func observeForever(_ track: @MainActor @escaping () -> Void, onChange: @MainActor @escaping () -> Void)
```

Cuts four near-identical blocks down to four one-liners and removes a class of "oops, forgot to re-subscribe" bugs.

### 4.12 Logging leaks the abbreviation length in the clear

`Keyed/Sources/Services/ExpansionEngine.swift:109`

```swift
logger.info("Expanding \(matched.count, privacy: .public) char abbreviation")
```

This is fine but worth flagging: the length of a just-typed snippet is weak side-channel information. Keep `privacy: .public` for the length, but make sure you never move to logging the abbreviation itself without changing that marker.

### 4.13 `incrementUsageCount` writes every 10 expansions, but nothing flushes on app resign-active

`applicationWillTerminate` flushes. But `applicationWillTerminate` is not guaranteed to run (crashes, force-quit, power loss). Move the flush to `NSApplication.willResignActiveNotification` as well, or just write through and measure whether the batching is worth the complexity.

---

## 5. What the review does *not* find wrong

It is useful to call out what's good so juniors can calibrate — not everything should be criticized.

- **Protocol-first service design with mock doubles in `Mocks.swift`**. Textbook. Keep doing this.
- **`os.Logger` with a single subsystem and per-file category**. Exactly right — future you will thank present you when Console.app is the only debugger you have.
- **`@MainActor` on services**. Correct for a SwiftUI-facing state surface. No premature off-main-actor experimentation.
- **Dedicated `KeystrokeBuffer` struct** rather than stuffing ring-buffer logic into the engine. Easy to test in isolation, which is the whole point of having it.
- **`@Observable` + `withObservationTracking` rather than Combine + `@Published`**. Modern, right call.
- **Swift 6 strict concurrency turned on**. Good discipline; the pain is up-front.
- **XcodeGen with `project.yml` source of truth**. Reduces merge conflicts on `.xcodeproj` to zero. Every Swift project should do this.
- **No third-party dependencies in the core expansion engine**. Means the hot path can be reasoned about end-to-end without pulling in anyone else's tech debt.
- **CSV tokenizer is actually a state-machine parser, not a `components(separatedBy:)` hack**. Almost nobody gets this right on the first try.

---

## 6. Priority-ordered action list

If this were my backlog for the next sprint:

**P0 — user-visible correctness**
1. Fix grapheme-cluster splitting in `UnicodeEventTextInjector` (§1.1)
2. Fix `{cursor}` offset computation (§1.2)
3. Fix `@Query` without `ModelContainer` in menu-bar popover (§1.3)
4. Fix `hasCompletedOnboarding` being set at open, not close (§1.4)
5. Make `ExpansionEngine.injectSnippet` respect enabled / excluded state (§2.4)

**P1 — data safety and robustness**
6. Replace silent in-memory fallback on SwiftData failure with explicit error UI (§1.5)
7. Move injection off the main thread; pause the tap during injection (§1.6)
8. Replace the 150 ms `Task.sleep` in `AccessibilityService` (§1.10)
9. Fix the ring-buffer "start of buffer == word boundary" lie (§1.7)

**P2 — scaling and maintainability**
10. Cache abbreviation → snippet lookups in `SnippetStore` to remove the per-expansion O(n) fetch (§1.8)
11. Rewrite `longestSuffixMatch` to actually be longest-match (§1.9)
12. State-machine `CGEventTapMonitor`; drop the manual lock (§2.5)
13. Extract `observeForever(track:onChange:)` helper (§4.11)
14. Delete dead `firstMatch` methods and debug-only test shim (§4.1, §4.2)

**P3 — test coverage gaps**
15. Add tests for every item in §3.

---

## 7. How to read this review if you're newer to the team

Three habits I want to leave the junior engineers with:

1. **Ask "what's the worst input?" before you merge.** Every time you see a chunk, a count, a timeout, or an index, mentally pick the value most likely to break it. For chunks, that's "a grapheme straddles the boundary." For counts, that's "zero or `Int.max`." For timeouts, that's "a machine slower than mine." If you can articulate the worst input, you should be writing the test for it.

2. **Ask "what environment is this running in?" every time you use SwiftUI environment values.** `@Query`, `@Environment`, `@EnvironmentObject` are handshakes. The compiler cannot tell you whether the handshake happens. The only protection is your own habit of tracing the view-host path at least once per new entry point.

3. **Loud failures > silent wrong behavior.** The in-memory fallback in `KeyedApp.swift`, the swallowed `updateLoginItem` error, the 150 ms sleep-and-hope in `AccessibilityService` — all of these make the app feel more "graceful" and are each a bug waiting to eat a user's data or sanity. A crash is a ticket. A silent lie is a lost user. When in doubt, fail loud.

Do those three things and most of this review writes itself.
