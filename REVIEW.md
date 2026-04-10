# Keyed — holistic code review

**Reviewer:** Principal engineer, newly onboarded.
**Target commit:** `8a257a4` (main).
**Scope:** Entire codebase — architecture, correctness, concurrency, security, tests.

> This review is intentionally blunt. The goal is not to make the team feel bad — it's to build the instincts that keep a keystroke-hooking, system-wide utility from silently corrupting people's work. Every "nit" here is the kind of thing that, at scale, turns into a 1-star review or a data-loss incident.

---

## TL;DR — the headline problems

1. **There is a correctness bug that silently breaks the core loop:** most UI mutation paths bypass `SnippetStore`, so the `ExpansionEngine`'s live abbreviation map becomes stale. Delete a snippet in the UI and it still expands. Add one and it doesn't fire. The observer contract is an illusion. This is a P0.
2. **`ClipboardTextInjector` is a pile of magic sleeps** around a clipboard save/restore dance that does not survive real-world clipboard contents (files, RTF, images with promise types), and will race against other clipboard listeners — including the team's own sister app, Clipped. This is the single highest-risk module in the codebase.
3. **`CGEventTapMonitor` has use-after-free, unicode, and tap-disable bugs** that will manifest as random crashes and dropped characters on real input. Specifically: `passUnretained` + `takeUnretainedValue` on the C callback, `maxStringLength: 1` dropping non-BMP code points, and no handler for `kCGEventTapDisabledByTimeout` (macOS will disable your tap under load — this is not optional to handle).
4. **There is no word-boundary or sigil requirement on abbreviations.** A user can register `the` and then every occurrence of "the" inside "other" expands. You have a placeholder UI flow, but the engine doesn't enforce it.
5. **`@unchecked Sendable` is sprinkled as a concurrency silencer** on classes that are already `@MainActor`, or that touch main-thread-only AppKit APIs. Strict concurrency is on. You are papering over the warnings rather than fixing them.
6. **Sensitive data leaks into `os.Logger`:** expansions are logged with default (public) redaction — if a user stores a password snippet, it goes to the unified log.
7. **Tests are thin and timing-coupled.** 66 tests sounds like a lot until you notice they never exercise the staleness bug above, never run the injector, never verify the event-tap state machine, and use `Task.sleep(50ms)` as a synchronization primitive.

The rest of this document breaks these — and many smaller issues — down module by module, with file and line references, rationale, and coaching notes. **The coaching notes are the point.**

---

## 1. Architecture and data flow

### 1.1 Two sources of truth for snippets (P0)

You have a clean-looking protocol (`SnippetStoring`) and a store (`SnippetStore`) that rebuilds a cached `abbreviationMap` on every write. The `AppDelegate` observes that map and updates the engine:

```swift
// Keyed/Sources/App/KeyedApp.swift:93
private func observeSnippetsLoop() {
    withObservationTracking {
        _ = snippetStore.abbreviationMap
    } onChange: { [weak self] in ... }
}
```

But the UI doesn't go through the store. It goes directly at `modelContext`:

- `SnippetListView.deleteSnippet` → `modelContext.delete(snippet)` then `try? modelContext.save()` (`SnippetListView.swift:190`)
- `SnippetListView.duplicateSnippet` → `modelContext.insert(copy)` (`SnippetListView.swift:198`)
- `SnippetListView.deleteGroup` → direct mutation (`SnippetListView.swift:209`)
- `AddSnippetView.addSnippet` / `replaceExisting` / `addWithSuffix` → all direct `modelContext.insert`/mutate (`AddSnippetView.swift:63-90`)
- `ImportView.importSelected` → direct `modelContext.insert` in a loop (`ImportView.swift:158`)
- `ExclusionSettingsView` → direct (`ExclusionSettingsView.swift:29, 52`)
- `SnippetDetailView` binds `@Bindable var snippet` directly, so edits skip the store entirely (`SnippetDetailView.swift:10`)

`SnippetStore.rebuildAbbreviationMap()` is only called inside the store's own CRUD methods. None of the above call them. Therefore `snippetStore.abbreviationMap` never changes, `withObservationTracking` never fires, and **the engine runs on a snapshot of the database from app launch**.

Consequences:

- Deleted snippets still expand until next relaunch. This is not a "nice to have" — it is user-destroying. Imagine deleting a snippet because the expansion was wrong, and it keeps firing.
- New snippets don't work until relaunch.
- Edits to `expansion` bind directly to the SwiftData object, which mutates in place — but the engine's `abbreviationMap` still holds a reference to the *value* from last rebuild. Actually — since the engine's map is `[String: String]` copied from `snippet.expansion`, edits do NOT propagate. Silent data staleness.
- Group changes don't matter for abbreviation matching, but updating `AppExclusion` via `ExclusionSettingsView` *also* only triggers via the snippet-observe loop (which fetches exclusions as a side effect — more on that below). If you only change exclusions, the engine doesn't see them either.

**Fix direction:** pick *one* source of truth. Either:

- (A) Make all writes go through `SnippetStore`. Remove `@Environment(\.modelContext)` from views. The store becomes the only thing that touches SwiftData. `@Query` reads are still fine because reads are idempotent, but writes must funnel through the store and rebuild the map. This is the cleaner option.
- (B) Drop the store's cached map. Have the engine observe the SwiftData context directly (via `NotificationCenter.default` on `.NSManagedObjectContextDidSave` or the SwiftData equivalent, or re-query on every match). Simpler but slower.

**Coaching note:** whenever you see an "observer" pattern, ask: *what mutations can bypass the thing being observed?* If the answer is "any code path that holds a `modelContext`", your observer is decorative. A protocol boundary only protects you if it is the *only* way through.

### 1.2 `SnippetStoring` is half a protocol

`SnippetStoring` declares `addSnippet`, `deleteSnippet`, etc., but *not* `updateSnippet` (`SnippetStore.swift:8-19` vs. the `updateSnippet` impl at line 54). You cannot write a test — or an alternate implementation — that exercises the edit path through the protocol. This is the kind of omission that happens when you add a method and forget the protocol, which tells me nothing is *actually* coding against `SnippetStoring` — it's all coding against the concrete `SnippetStore`. Either delete the protocol or complete it. Half-protocols give false confidence.

### 1.3 `@MainActor` + `@unchecked Sendable`

`ExpansionEngine` is declared `@MainActor final class ExpansionEngine: @unchecked Sendable` (`ExpansionEngine.swift:12-13`). `@MainActor` classes are *already* Sendable. `@unchecked Sendable` on top of that is a lie told to silence the compiler — and worse, it *opts out* of the real safety checks. Same pattern appears on `ClipboardTextInjector` (`TextInjector.swift:15`), `CGEventTapMonitor` (`KeystrokeMonitor.swift:18`), and the mocks.

For the actual non-main-actor class (`CGEventTapMonitor`), `@unchecked Sendable` is technically defensible because you're managing synchronization by hand with `NSLock`. But then `onKeystroke: (@Sendable ...)?` is a stored mutable var with no lock around it (line 25) — that itself is a data race under strict concurrency. `@unchecked` is masking a real bug.

**Coaching note:** `@unchecked Sendable` should hurt to type. Every instance of it should come with a comment explaining *what the invariant is* and *who enforces it*. If you can't write that comment, the code isn't thread-safe.

### 1.4 Observer recursion via `Task { @MainActor in ... observeSnippetsLoop() }`

The `observeSettingsLoop`/`observeSnippetsLoop` pattern (`KeyedApp.swift:81-110`) re-subscribes on every change. That is the correct pattern for `@Observable` + `withObservationTracking` (which is one-shot), but:

- Combining two concerns into `observeSnippetsLoop` — it watches `abbreviationMap` but *also* refetches `AppExclusion`. If abbreviations don't change but exclusions do, nothing happens. Split them into two loops.
- Each `onChange` hops through a `Task { @MainActor in ... }`. Since the class is already `@MainActor`, this is an unnecessary queue hop that creates a window where the engine is out of sync with the model.
- If `rebuildAbbreviationMap` produces a map that's equal to the previous one (common during renames where the aggregate dict is the same), you still re-run — fine, but there's no dedupe.

---

## 2. `ExpansionEngine` — the orchestrator

File: `Keyed/Sources/Services/ExpansionEngine.swift`

### 2.1 Matching algorithm

```swift
private func checkForMatch() {
    let abbreviations = Set(abbreviationMap.keys)   // <-- L93
    if let exact = buffer.firstMatch(from: abbreviations) { ... }
    else if let caseInsensitive = buffer.firstMatchCaseInsensitive(from: abbreviations) { ... }
}
```

Problems:

1. **Allocates a `Set` on every keystroke.** `abbreviationMap.keys` is already a `Keys` view; wrapping it in `Set(_:)` allocates. On every keystroke. Hoist `private var abbreviations: Set<String>` and update it alongside `updateAbbreviations`.
2. **`firstMatch` iteration order is undefined** because it's a `Set`. If you have `":email"` and `"email"` and the user types `":email"`, the shorter match can win non-deterministically.
3. **Longest-match is not honored.** If `":sig"` and `":signature"` both exist and a user types `":signature"`, the engine may expand `":sig"` after the 4th character and leave `"nature"` dangling in the document. A proper text expander uses a trie and waits for a boundary key, OR picks longest-prefix-first and only fires when no longer match is possible.
4. **Exact-first-then-case-insensitive double pass** does 2× the work. Do a single pass and prefer exact over case-insensitive in the same loop. (Also: case-insensitive could produce a different match than exact, so "try exact first" only helps if both matches are the same abbreviation, which is the common but not exclusive case.)
5. **No boundary-key gating.** Many real text expanders only fire *on* a space/punctuation/enter, which prevents `"the"` from expanding inside `"other"`. Right now, as soon as the last letter of the abbreviation lands in the buffer, the engine fires. See §2.5.
6. **Complexity:** O(N × M) per keystroke where N = number of abbreviations, M = average length. Fine at 100 snippets, noticeable at 5,000. A trie keyed on the reverse string (since you match at the tail) is the right structure long-term. Don't build it now — just document the limit and add a benchmark.

### 2.2 `isExpanding` guard is fragile

```swift
isExpanding = true
buffer.reset()

Task {
    await injector.replaceText(...)
    await MainActor.run {
        self.isExpanding = false
        ...
    }
}
```

(`ExpansionEngine.swift:118-131`)

You're launching a non-isolated `Task` from inside a `@MainActor` method, then hopping back to `MainActor.run` at the end. That works, but:

- **During the `await`**, the event tap is still delivering synthetic backspaces and `Cmd+V` (posted by your injector) and real user keystrokes, all into the `onKeystroke` closure, all hopping to MainActor via `Task { @MainActor in ... }`. These Tasks queue up on the main actor. They execute in FIFO order... *usually*. Swift's actor scheduling is not strictly FIFO across `Task` creation order — it's priority-based. So a high-priority keystroke Task can overtake a low-priority one. With user-initiated work this is unlikely to matter, but it's one more thing you cannot reason about.
- **The `isExpanding` read** in `handleKeystroke` and the write in the injection Task race across suspension points. If a user types a second abbreviation during a slow paste, the engine correctly drops those keystrokes (because `isExpanding == true`), but because `buffer.reset()` only happened *before* the paste, any characters typed during the paste gap land in the buffer when expansion completes, producing ghosts.
- **No timeout.** If `injector.replaceText` hangs (e.g. the target app stops accepting events), `isExpanding` is stuck `true` forever and the app silently stops expanding. Add a timeout + structured recovery.

### 2.3 Frontmost-app exclusion check is racy

```swift
if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
   excludedBundleIDs.contains(bundleID)
```

(`ExpansionEngine.swift:70-73`)

`NSWorkspace.shared.frontmostApplication` is a main-thread API that returns a cached value updated by notification. Between keystrokes there is no guarantee it matches the app that will actually receive the paste. More importantly, your *own* app briefly becomes frontmost during clipboard manipulation? It does not, because paste is dispatched to the already-frontmost app via CGEvent, but any accessibility dialog, Spotlight, or system overlay can interleave.

Also: this check is O(1) per keystroke but allocates nothing, which is fine. The real issue is that *password managers* and terminal emulators should be excluded by default — not "zero exclusions on first launch".

### 2.4 Logging leaks expansion content

```swift
logger.info("Expanding '\(matched)' → \(resolvedExpansion.prefix(50))...")
```

(`ExpansionEngine.swift:117`)

Under OSLog's default privacy policy, interpolated values in `info` log lines to the unified log system are **public** when they come from non-numeric types in release builds (the privacy defaults differ between debug and release, and between Swift versions). That means expansion content — which can include passwords, API keys, full sentences — ends up in syslog, viewable with `log show`, and shipped to Apple in crash reports if the log is in the aggregate.

Fix: `\(resolvedExpansion.prefix(50), privacy: .private)`. Also reconsider logging `matched` — abbreviation names can themselves be sensitive.

**Coaching note:** for a keystroke tool, the *default* assumption should be "everything is PII". Any log line must be `.private` unless you've deliberately decided it's safe.

### 2.5 Dead test-support API in production

```swift
func handleKeystrokeForTesting(_ event: KeystrokeEvent) {
    handleKeystroke(event)
}
```

(`ExpansionEngine.swift:136`)

This is shipping in the release binary. Either `#if DEBUG`-guard it or restructure tests to exercise the real `monitor.onKeystroke` plumbing via `MockKeystrokeMonitor.simulateKeystroke`. Right now you even have that method (`Mocks.swift:17`) but the tests don't use it — they call this shortcut instead, bypassing the `@Sendable` closure hop. Your tests are therefore *not* testing the same code path as production.

---

## 3. `KeystrokeBuffer`

File: `Keyed/Sources/Services/KeystrokeBuffer.swift`

### 3.1 `storage: [String]` is wasteful

Each entry is a heap-allocated Swift `String`. A `[Character]` or a raw `[UInt32]` (Unicode scalar) would be cheaper and more correct (see 3.2). You allocate one `String` per keystroke, per entry, per comparison. For a 128-slot buffer at 10 keystrokes/sec, this is tolerable — but it'll show up in Instruments.

### 3.2 Unicode and normalization bugs

```swift
guard storage[bufferIndex] == String(abbrevChars[i]) else { return false }
```

(`KeystrokeBuffer.swift:50`)

- `abbrevChars = Array(abbreviation)` gives `[Character]` (extended grapheme clusters).
- `storage` is populated from `CGEventTapMonitor.handleEvent` which does `String(utf16CodeUnits: unicodeChar, count: Int(unicodeLength))` with `maxStringLength: 1` — so each buffer entry is one UTF-16 code unit's worth of string, not a grapheme cluster.
- A user typing "é" composed from "e" + combining acute produces **two** buffer entries and **one** abbreviation character. They will never match.
- Emoji beyond the BMP (most of them) produce surrogate pairs that `maxStringLength: 1` drops entirely (see §4.2).
- Comparison uses `==` on the `String`, which does canonical-equivalence comparison — *good* for precomposed/decomposed cases, but only *after* you've assembled the right set of code units, which you aren't doing.

Fix: buffer Unicode scalars or characters, not arbitrarily-sized strings, and feed it from a fixed scalar extraction that reads the full composed character out of the event.

### 3.3 `hasSuffix` and `hasSuffixCaseInsensitive` are duplicated

Classic "parameterize the comparison" opportunity. One generic method taking a `(String, String) -> Bool` closure would eliminate the drift risk. Right now, if someone fixes the Unicode bug in one, they'll forget the other.

### 3.4 `typedSuffix(length:)` assumes the same length as the abbreviation in *characters*

```swift
let typed = buffer.typedSuffix(length: matched.count)
```

(`ExpansionEngine.swift:108`)

`matched.count` counts Swift grapheme clusters, but the buffer is indexed per-code-unit slot. For any abbreviation with a multi-code-unit grapheme (e.g. `:café` with decomposed form), this reads the wrong slice and the case-detection becomes nonsensical. Tests pass because they only use ASCII.

---

## 4. `CGEventTapMonitor`

File: `Keyed/Sources/Services/KeystrokeMonitor.swift`

This is the single most dangerous file in the codebase because it runs in the system event pipeline and talks to C APIs with raw pointers.

### 4.1 Use-after-free via `passUnretained`

```swift
let unmanagedSelf = Unmanaged.passUnretained(self)
...
callback: { _, _, event, userInfo -> Unmanaged<CGEvent>? in
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let monitor = Unmanaged<CGEventTapMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.handleEvent(event)
    return Unmanaged.passRetained(event)
}
```

(`KeystrokeMonitor.swift:36-48`)

`passUnretained` + `takeUnretainedValue` = "trust me, the object is alive." If `self` is deallocated while the tap is still enabled, the callback dereferences a dangling pointer and you get a crash, a corrupted keystroke, or — worst case for a system-wide event tap — you mutate random memory that happens to be at that address.

`stop()` disables the tap before releasing the object, which *usually* works, but it's guarded by an `NSLock` that the C callback cannot acquire. There is a race where:

1. Main thread calls `stop()`, takes lock, calls `tapEnable(false)`.
2. C callback was *already* running on the eventtap thread from a previous event.
3. Main thread finishes `stop()`, `self` is released shortly after via ARC.
4. C callback proceeds with a now-freed `self`.

Correct pattern:

- Use `Unmanaged.passRetained(self)` when installing the tap, storing the unmanaged reference.
- In the callback, `takeUnretainedValue()` (the retain is held by the tap's lifetime).
- On `stop()`, disable the tap, remove the run-loop source, **drain the runloop once**, and only then release the unmanaged via `.release()`.
- Better: hold `self` by strong reference from the runloop's userInfo via a retain, and tear down synchronously.

### 4.2 `maxStringLength: 1` drops non-BMP code points

```swift
var unicodeLength = 1
var unicodeChar: [UniChar] = [0]
event.keyboardGetUnicodeString(
    maxStringLength: 1,
    actualStringLength: &unicodeLength,
    ...
)
```

(`KeystrokeMonitor.swift:115-121`)

- `UniChar` is `UInt16`. Non-BMP characters (most emoji, some CJK extensions, mathematical symbols) produce **surrogate pairs** — two UTF-16 code units. `maxStringLength: 1` silently truncates.
- On macOS the common case is dead keys / input methods that compose characters over multiple events — `keyboardGetUnicodeString` may return 0 length for the first key and full length for the second. Your early-return on `unicodeLength > 0` handles the zero case, but buffer-length=1 rules out longer returns.
- **Fix:** allocate a 4-element `UniChar` buffer and pass `maxStringLength: 4`. Then construct the Swift string from the full range.

### 4.3 No handling of `kCGEventTapDisabledByTimeout`

macOS will disable your event tap if your callback blocks for too long. This is a well-known landmine for keystroke-based tools. The docs are explicit: you must listen for `kCGEventTapDisabledByTimeout` and `kCGEventTapDisabledByUserInput`, and re-enable the tap on timeout.

Your callback receives a `type: CGEventType` parameter — you ignored it (`_, _, event, userInfo`). You need to check it, and on disable, call `CGEvent.tapEnable(tap: tap, enable: true)`.

This is not a "nice to have". On a user's MacBook under load (Time Machine backup, Spotlight indexing, a busy Zoom call), your tap *will* get disabled and expansions will silently stop working until relaunch. This is the top-reported bug for every homemade text expander.

### 4.4 `monitorQueue` is abandoned after `stop()`

`stop()` stops the runloop, but:

- The `monitorQueue` DispatchQueue reference is nilled out via the properties but the queue itself is still around waiting to finish the `queue.async { ... }` block (which is blocked in `CFRunLoopRun()`).
- The block exits cleanly when the runloop stops, but the queue is never explicitly torn down. In practice DispatchQueues are released when unreferenced, so this works — but a subsequent `start()` call creates a *new* queue, not reusing the old one. Confusing.
- `monitor.stop()` in `deinit` can run on any thread (the class is not `@MainActor`). `NSLock` handles that, but `stop()` calls `CFRunLoopStop` on a run loop potentially owned by another thread — which is documented to be OK but worth a comment.

### 4.5 Modifier handling loses information

```swift
let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
if !flags.intersection(modifierMask).isEmpty {
    onKeystroke?(.modifiedKey)
    return
}
```

(`KeystrokeMonitor.swift:88-93`)

- `.maskAlternate` (Option) is a legitimate way to produce characters on European keyboards. `Option+e` + `a` → `á`. By treating any Option as "modified", you drop characters that real users type. This is another "test passes on ASCII qwerty, fails in the wild" bug.
- **Fix:** only treat `.maskCommand` and `.maskControl` as shortcuts. Let Option through. For AltGr layouts (which macOS represents differently), treat similarly.

### 4.6 Boundary key list is incomplete

```swift
let boundaryKeys: Set<Int64> = [
    Int64(kVK_Return), Int64(kVK_Tab), Int64(kVK_Escape),
    Int64(kVK_LeftArrow), Int64(kVK_RightArrow),
    Int64(kVK_UpArrow), Int64(kVK_DownArrow),
    Int64(kVK_Home), Int64(kVK_End),
    Int64(kVK_PageUp), Int64(kVK_PageDown),
]
```

(`KeystrokeMonitor.swift:102-108`)

Missing: Forward Delete (`kVK_ForwardDelete`), ANSI_KeypadEnter, mouse clicks (you don't get these from a keyboard tap — you'd need a separate tap). The docstring says `// boundary key — arrow, tab, escape, mouse click`, but mouse clicks are not in the list. Either update the comment or add the tap.

### 4.7 `guard unicodeLength > 0 else { return }` — but `unicodeLength` is `Int`, declared as `1`

You declare `var unicodeLength = 1` then pass `&unicodeLength` — the function writes the *actual* length. That's fine. But initialising to 1 instead of 0 looks like a bug on first read. Use `0`.

---

## 5. `ClipboardTextInjector`

File: `Keyed/Sources/Services/TextInjector.swift`

This module needs a rewrite. It is a collection of magic numbers around a design that cannot work for all clipboard content.

### 5.1 Clipboard round-tripping is lossy

```swift
private func savePasteboard() -> [NSPasteboardItem] {
    pasteboard.pasteboardItems?.compactMap { item in
        let saved = NSPasteboardItem()
        for type in item.types {
            if let data = item.data(forType: type) {
                saved.setData(data, forType: type)
            }
        }
        return saved
    } ?? []
}
```

(`TextInjector.swift:64-74`)

- **Promise types are lost.** File-promise drags, from Finder or mail apps, carry `NSFilePromiseProvider` entries whose data is generated lazily — `item.data(forType:)` returns `nil` for them.
- **Rich formats can be multi-representation.** An image on the clipboard may have `public.tiff`, `public.png`, `com.adobe.pdf`, and a URL component. You copy all four, which works for some apps but not those that expect the items in a specific order.
- **Change-count is not preserved.** Apps that watch `NSPasteboard.general.changeCount` (including your own sister app Clipped) see *two* clipboard changes during an expansion: the set-expansion change and the restore change. These are indistinguishable from user copies. Clipped will now have a ghost entry for every expansion that's a random user's clipboard content. That's a real, shipping collision between your own products.
- **Fix direction:** use a dedicated pasteboard (`NSPasteboard(name: .init("com.mcclowes.keyed.private"))`) to stage the expansion, then do a programmatic insertion via `CGEvent.keyboardSetUnicodeString(...)` which posts characters directly without touching the global pasteboard. The existing AX-based path (`AXUIElementCopyAttributeValue` on the focused element) is also viable for cooperative apps.

### 5.2 Magic sleeps

```swift
try? await Task.sleep(for: .milliseconds(5))
...
try? await Task.sleep(for: .milliseconds(20))
...
try? await Task.sleep(for: .milliseconds(100))
...
try? await Task.sleep(for: .milliseconds(20))
...
try? await Task.sleep(for: .milliseconds(3))
...
try? await Task.sleep(for: .milliseconds(50))
```

(`TextInjector.swift:26-54`)

Every number here is a guess. On a slow machine, a remote desktop session, a high-latency IME, or a CPU-pegged system, these will be wrong and you'll produce corrupted output. There is no retry, no verification, no feedback loop.

- **Coaching note:** `sleep(50ms)` is almost always a symptom of "I don't know what I'm waiting for." The correct answer is usually: figure out the event you're waiting for, and wait for *that*. For paste-completion, there's no synchronous signal, so the real fix is to use `CGEvent.keyboardSetUnicodeString` which bypasses the clipboard entirely and is synchronous.

### 5.3 `abbreviationLength` backspaces assume one-byte-per-char

```swift
for _ in 0..<abbreviationLength {
    postKeyEvent(keyCode: UInt16(kVK_Delete), keyDown: true)
    ...
}
```

(`TextInjector.swift:23-27`)

`abbreviationLength` comes from `matched.count` in the engine — that's the grapheme count. In most target apps, one backspace deletes one grapheme, so this is *usually* right. But:

- In terminals, one backspace deletes one *byte* of a UTF-8 sequence.
- In some text views (old Carbon apps, custom NSTextView subclasses), backspace deletes one code unit.
- For abbreviations with emoji, the count-to-backspace ratio can be wrong.

At minimum, add a comment explaining the assumption.

### 5.4 `restorePasteboard` can clear then not restore

```swift
private func restorePasteboard(_ items: [NSPasteboardItem]) {
    pasteboard.clearContents()
    if items.isEmpty { return }
    pasteboard.writeObjects(items)
}
```

(`TextInjector.swift:76-80`)

If the original clipboard was empty, you clear the clipboard (which was already empty) and return. Fine. If it was non-empty, you save, overwrite with expansion, then restore. Fine. But note the invariant: this method **always wipes the clipboard first**, even when items is empty. That means after an expansion, the clipboard is guaranteed to not contain the expansion text. Good — but also, between the `clearContents()` and the `writeObjects()`, the clipboard is briefly empty, and another process watching it sees a transient "empty" state. Unlikely to matter, worth knowing.

### 5.5 `kVK_ANSI_V` is physical-layout dependent for other keyboards

Cmd+V is bound to the physical position of V on ANSI, which is the same position on ISO and JIS. But if a user has remapped Cmd+V (system-wide, via a preference) — for example, to Cmd+Y — your synthetic Cmd+V will do the wrong thing. More commonly, apps that disable Cmd+V (e.g., some password fields) will reject the paste entirely and your backspaces will have already fired. Irreversible partial state.

`CGEvent.keyboardSetUnicodeString` would avoid this entirely.

### 5.6 No feedback to the engine on failure

`replaceText` returns `Void`. If the paste fails (frontmost app rejected Cmd+V), the engine has no way to know — `isExpanding` is cleared, the user sees mangled output, the logs show a successful expansion. Add a `Result`/`throws` return and surface failures to the user via the status bar.

---

## 6. `SnippetStore`

File: `Keyed/Sources/Services/SnippetStore.swift`

### 6.1 Duplicate detection inconsistency

- `SnippetStore.addSnippet` checks `findSnippet(byAbbreviation:)` which uses `$0.abbreviation == abbreviation` — **case-sensitive** (`SnippetStore.swift:99`).
- `AddSnippetView.isDuplicate` uses `$0.abbreviation.lowercased() == abbreviation.lowercased()` — **case-insensitive** (`AddSnippetView.swift:17`).
- The engine matches **case-insensitively** via `firstMatchCaseInsensitive` (`ExpansionEngine.swift:99`).

So the user can add `":Email"` after `":email"` exists — the store allows it, the view complains but lets you through, the engine then has two matches in its `Set`, and `Set.first { ... }` picks one non-deterministically (see §2.1). Pick one rule and enforce it everywhere.

### 6.2 `rebuildAbbreviationMap` scans everything

Every write triggers a full `allSnippets()` fetch, iterates the result, and replaces the map. For 100 snippets this is free; for 10,000 (enterprise importer users) it's a noticeable pause on every keystroke-triggered usage-count increment. Maintain the map incrementally.

Also, `incrementUsageCount` does not rebuild the map — good, but it *does* `try? modelContext.save()` on every expansion (`SnippetStore.swift:88`), which is a full SwiftData transaction per keystroke expansion. Batch these writes.

### 6.3 `findSnippet` runs a fresh fetch every call

```swift
func findSnippet(byAbbreviation abbreviation: String) -> Snippet? {
    let descriptor = FetchDescriptor<Snippet>(predicate: #Predicate { $0.abbreviation == abbreviation })
    return try? modelContext.fetch(descriptor).first
}
```

(`SnippetStore.swift:98-101`)

Called from `incrementUsageCount` on *every expansion*. A SwiftData fetch per keystroke is indefensible when you already have the map in memory. Maintain `[String: Snippet]` (or at least `[String: PersistentIdentifier]`) alongside the abbreviation map.

### 6.4 Error swallowing

`try? modelContext.save()` appears throughout (`SnippetStore.swift:88`, `SnippetListView.swift:74`, etc.). If the save fails — disk full, context out of sync, schema mismatch — the user gets silent data loss. At minimum, log the error. Better: propagate to a user-visible alert.

**Coaching note:** `try?` is the Swift equivalent of `except: pass` in Python. Every instance should be justified with a comment: *why is it safe to ignore this error?* If you can't answer, you can't use `try?`.

### 6.5 `SnippetStoring` protocol missing: `updateSnippet`, `modifyExclusions`, `findByAbbreviation`, etc.

See §1.2.

---

## 7. SwiftData model design

### 7.1 No relationships

`Snippet` has `var groupID: UUID?`. `SnippetGroup` has nothing. This is a weak pointer that you have to manually maintain, which is why `deleteGroup` has to manually unassign snippets (`SnippetStore.swift:130-141`, `SnippetListView.swift:209-220`) — and do it twice in two different places with the same logic drift risk.

Proper SwiftData:

```swift
@Model final class SnippetGroup {
    @Relationship(deleteRule: .nullify, inverse: \Snippet.group)
    var snippets: [Snippet] = []
}

@Model final class Snippet {
    var group: SnippetGroup?
}
```

The framework handles nullify-on-delete for you.

### 7.2 No uniqueness constraint

`Snippet.abbreviation` should be `@Attribute(.unique)`. That enforces duplicates at the DB level, not just at the "if I remember to check" level. Same for `AppExclusion.bundleIdentifier`.

### 7.3 No schema versioning

First time you add a field to `Snippet`, the user's existing SwiftData store will migrate… maybe. You haven't set up `VersionedSchema` / `SchemaMigrationPlan`. Plan this before 1.0 — retrofitting migrations after shipping is miserable.

### 7.4 `id: UUID` manually managed

SwiftData gives you `persistentModelID` for free. Declaring your own `id: UUID` is fine for your own use, but means every `Snippet` row carries two identifiers. If you want the UUID for export/import stability, keep it. If not, delete it.

---

## 8. `CaseTransform`

File: `Keyed/Sources/Services/CaseTransform.swift`

### 8.1 Destroys existing casing

```swift
private static func titleCase(_ text: String) -> String {
    guard let first = text.first else { return text }
    return String(first).uppercased() + text.dropFirst().lowercased()
}
```

(`CaseTransform.swift:43-47`)

If the expansion is "Dr. Smith" and the user types `:Sig`, you produce "Dr. smith". You've destroyed intentional capitalization. `.allUpper` does the same: typing `:EMAIL` produces `TEST@EXAMPLE.COM` instead of `test@example.com`. Email addresses don't uppercase. Domain names don't uppercase. Your test asserts this exact broken behavior (`ExpansionEngineTests.swift:152-154`), which canonizes the bug.

The correct behavior:

- `.allUpper` should only uppercase letters that were lowercase in the original expansion's **first word**, or — more usefully — should be disabled for expansions that look like they contain structured data (URLs, emails, code).
- `.titleCase` should capitalize only the first letter, preserving the rest. Your test at `CaseTransformTests.swift:41-43` says "BEST REGARDS" → "Best regards" — that's your current behavior, but it's the wrong behavior. The user typed `:Sig` because they want a capital B, not because they want to force all other letters to lowercase.

### 8.2 Detection only looks at letters

```swift
let typedLetters = typed.filter(\.isLetter)
```

(`CaseTransform.swift:12`)

So `":Email"` and `":EMAIL"` are detected correctly, but an abbreviation that is *all punctuation* (`:::`) bypasses case detection entirely — fine. But `":1Password"` would strip the `1` from both typed and abbrev, then compare. Typed `:1PASSWORD`: typedLetters=`PASSWORD`, all upper — returns `.allUpper`. Result: expansion gets uppercased. Is that what the user wants? Probably.

Edge case: `:iOS`, typed `:IOS` — your detector sees `IOS`, all upper, returns `.allUpper`. Original expansion might be "iOS is great" → "IOS IS GREAT". Again, destroys intent.

### 8.3 `detect` should return `.asIs` when the abbreviation itself has mixed case

If the abbreviation is defined as `:XML` (intentionally upper), and the user types `:xml`, your current detect returns `.asIs` (because typed is all-lower → doesn't match the `.allUpper` or `.titleCase` paths). But the abbreviation had uppercase letters; you should probably *preserve* the defined casing. This is handled correctly by default (`.asIs`), but only by accident.

---

## 9. `PlaceholderResolver`

File: `Keyed/Sources/Services/PlaceholderResolver.swift`

### 9.1 `DateFormatter` is allocated per resolve

```swift
private func formattedDate() -> String {
    let formatter = DateFormatter()
    ...
}
```

(`PlaceholderResolver.swift:31-35`)

`DateFormatter` is **famously expensive** to construct. For a feature that runs on every expansion containing `{date}`, cache the formatter. Also, `struct PlaceholderResolver` is re-instantiated on every `checkForMatch` (`ExpansionEngine.swift:113`), which allocates the resolver and its three formatters every time. Hoist it into the engine as a stored property.

### 9.2 Hardcoded locale and format

`.long` date style is user-friendly but doesn't let the user control format. Eventually you want `{date:yyyy-MM-dd}` syntax. Not blocking, but note it.

### 9.3 `{cursor}` counts graphemes, cursor moves are per-key

```swift
func cursorOffset(in text: String) -> Int? {
    guard let range = text.range(of: "{cursor}") else { return nil }
    let afterCursor = text[range.upperBound...]
    return afterCursor.count
}
```

(`PlaceholderResolver.swift:21-25`)

Then the injector posts `offset` left-arrow keys. In most apps, one left-arrow moves past one grapheme — OK. In terminals and some text fields, it moves one code unit. Edge case for emoji-containing expansions. Document or normalize.

### 9.4 Only the first `{cursor}` is honored

Multiple `{cursor}` placeholders are silently stripped but only the first positions the cursor. That's reasonable, but `stripCursorPlaceholder` removes *all* of them, so the cursor offset math is only correct for the first occurrence. Test coverage is zero for this case.

### 9.5 `{clipboard}` is read at match time, not inject time

`ExpansionEngine.checkForMatch` calls `resolver.resolve(...)` which reads `NSPasteboard.general` (`PlaceholderResolver.swift:14`). Then it passes the resolved text to the injector, which *saves the current clipboard* and *overwrites it*. If there's a race between the resolver read and the injector save, both read the same clipboard. Fine.

But: the resolved expansion is passed as a plain string to the injector, which pastes it. That means if a user's clipboard contained an image, the `{clipboard}` placeholder resolves to `""` (because `string(forType: .string)` returns nil for images). Silent. Worth noting.

---

## 10. `ImportService`

File: `Keyed/Sources/Services/ImportService.swift`

### 10.1 CSV parser is not CSV-compliant

```swift
for char in line {
    if char == "\"" {
        inQuotes.toggle()
    }
    ...
}
```

(`ImportService.swift:48-57`)

RFC 4180 says `""` inside a quoted field is an escaped quote. Your parser treats it as open-then-close, producing corrupted output. Example:

```
abbreviation,expansion
:quote,"He said ""hi"""
```

Expected: `He said "hi"`. Your parser: `He said hi`.

Also:

- Embedded newlines inside quoted fields are impossible because you split on `.newlines` first (`ImportService.swift:14`).
- Header matching is case-sensitive and whitespace-sensitive. `Abbreviation,Expansion` won't match.
- Fields are trimmed with `.whitespaces`, which will strip leading/trailing spaces that were inside quotes. That's wrong — quoted fields preserve whitespace.

**Fix:** use a real CSV parser. Don't roll your own. If you must, at least support `""`, embedded newlines, and don't trim inside quoted fields.

### 10.2 TextExpander plist parser ignores most of the format

Real TextExpander groups have nested groups, rich-text snippets (`richText` key), fill-ins, scripts, AppleScript snippets, and more. You only read `plainText`. Any snippet with formatting is silently dropped to `nil` from `compactMap`. The user gets no error telling them which snippets were skipped.

At minimum, count skipped snippets and surface the count in the import preview.

### 10.3 No batch-level duplicate detection

`ImportView.importSelected` inserts directly via `modelContext.insert` without going through the store, so no duplicate detection runs. Import a CSV that contains `:email` when you already have `:email`, and you now have two `:email` rows — and the engine's `abbreviationMap` dedupes silently by taking the last one, so one of them becomes invisible.

---

## 11. Views

### 11.1 `AddSnippetView` bypasses the store

See §1.1 for the headline bug. But also:

```swift
private func addWithSuffix() {
    let snippet = Snippet(abbreviation: abbreviation + "2", ...)
    modelContext.insert(snippet)
    try? modelContext.save()
    dismiss()
}
```

(`AddSnippetView.swift:85-90`)

If `abbreviation + "2"` already exists, you now have two rows with the same abbreviation. No collision check. Run it twice with `:email`, you get `:email2` twice.

`private var errorMessage: String?` (line 11) is declared but never assigned — dead state. SwiftLint should catch this.

### 11.2 `SnippetDetailView` has no undo, no save indicator, and mutates on every keystroke

```swift
.onChange(of: snippet.abbreviation) { snippet.updatedAt = .now }
.onChange(of: snippet.expansion) { snippet.updatedAt = .now }
```

(`SnippetDetailView.swift:34-35`)

Every keystroke in the editor bumps `updatedAt` — fine. But the binding is via `@Bindable var snippet`, which writes back to SwiftData on every character. If a user holds down a key, you're doing a full SwiftData autosave storm. Debounce.

Also: no validation. User can clear the abbreviation and save an empty string, which the engine's `Set(abbreviationMap.keys)` will then include as `""`, potentially matching every buffer state. I'd check whether `Set` correctly handles `""` as a key — it does, but `hasSuffix("")` returns true trivially, so the engine would try to "expand" on every keystroke. Test this.

### 11.3 `SnippetListView.filteredSnippets` re-sorts on every render

```swift
private var filteredSnippets: [Snippet] {
    var result = snippets
    ...
    switch settings.snippetSortOrder {
    case .alphabetical:
        result.sort { ... }
    ...
}
```

(`SnippetListView.swift:17-38`)

Computed property, no memoization. On every view update (which is a lot, given `@Observable` propagation), you allocate a new array, filter it, and sort it. For 10,000 snippets this is a problem. Hoist into `@State` updated via `.onChange(of: snippets)`.

### 11.4 Dead "Rename..." button

```swift
Button("Rename...") {
    // Simple rename via alert would need additional state;
    // for now, editing in-place is deferred to v1.x
}
```

(`SnippetListView.swift:92-95`)

A button that does nothing, labeled as if it works. Users will click it and think the app is broken. Either remove the button or implement it. Never ship a dead UI affordance.

### 11.5 `OnboardingView` accessibility polling

```swift
Task {
    for _ in 0..<30 {
        try? await Task.sleep(for: .seconds(1))
        if accessibilityService.isTrusted() { ... }
    }
}
```

(`OnboardingView.swift:77-85`)

30-second poll, then silently gives up. If the user takes 31 seconds to navigate System Settings (which they will, because it's System Settings), the onboarding flow is stuck. Observe `DistributedNotificationCenter.default.addObserver(forName: .init("com.apple.accessibility.api"), ...)` or just poll indefinitely with a Cancel button.

### 11.6 `OnboardingView` starter snippets bypass the store AND show inconsistent prefixes

- Starter row shows `:email` (single colon) in the UI (`OnboardingView.swift:110`).
- Actually inserts `::email` (double colon) (`OnboardingView.swift:164`).

The user is promised one thing and gets another. This is a "nobody tried this end-to-end" bug.

Also, inserted directly via `modelContext.insert` — doesn't go through the store (§1.1).

### 11.7 `OnboardingView` window is not retained

From `AppDelegate.showOnboarding()`:

```swift
let controller = NSHostingController(rootView: onboardingView)
let window = NSWindow(contentViewController: controller)
...
window.makeKeyAndOrderFront(nil)
```

(`KeyedApp.swift:112-125`)

`window` is a local let and goes out of scope at the end of the function. NSWindow is usually retained by AppKit once it's key-and-ordered-front, but this is fragile — any SwiftUI/AppKit upgrade can break the assumption. Store `var onboardingWindow: NSWindow?` on `AppDelegate`.

### 11.8 `MenuBarPopoverView.openMainWindow` uses string-matching on window title

```swift
if let window = NSApp.windows.first(where: { $0.title == "Keyed" || $0.identifier?.rawValue == "main" }) {
```

(`MenuBarPopoverView.swift:46`)

Window identifier matching is fine; title matching will break if you ever localize. Use `@Environment(\.openWindow)` and pass the `id: "main"` directly. The hack also includes a fallback that calls `"showSettingsWindow:"` which is... a different concept entirely. This is "I don't know how SwiftUI window management works, so I'll brute-force it" code.

### 11.9 `ExclusionSettingsView.RunningAppPickerView` only shows running apps

If the user wants to exclude 1Password and it's not currently running, they can't. Offer a file picker into `/Applications` too.

---

## 12. `StatusBarController`

### 12.1 `nonisolated(unsafe)` is likely unnecessary

```swift
private nonisolated(unsafe) var eventMonitor: Any?
```

(`StatusBarController.swift:9`)

The class is `@MainActor`. Its deinit is main-actor-isolated. There's no cross-actor access. The `nonisolated(unsafe)` is a concurrency silencer with no justification. Remove it and find out what warning it was suppressing, then fix that properly.

### 12.2 Duplicate "close popover on outside click" logic

`NSPopover.behavior = .transient` already auto-closes on outside clicks. Your `eventMonitor` reimplements the same behavior. Pick one.

### 12.3 No cleanup on `stop()`-equivalent

There is no way to tear down the status bar item cleanly. In tests (if you add any), you can't reset between setUp calls. This would come up the moment you try to unit-test the controller.

---

## 13. Concurrency and strict checking — the big picture

The project declares `SWIFT_STRICT_CONCURRENCY: complete` (`project.yml:14`). That is the right choice. But the code is patched with `@unchecked Sendable`, `nonisolated(unsafe)`, and `Task { @MainActor in ... }` hops that together defeat the purpose. A clean pass would be:

1. `CGEventTapMonitor` is the only truly non-main-actor class. Keep it that way. Wrap its mutable state in a single serial queue or an `actor` instead of `NSLock` + `@unchecked Sendable`.
2. `ClipboardTextInjector` is `@MainActor` — it only touches NSPasteboard and CGEvents. Remove `@unchecked Sendable`.
3. `ExpansionEngine` is `@MainActor`. Remove `@unchecked Sendable`. Accept that `Sendable` is automatic.
4. Services that only exist on the main actor should not have `@Sendable` closures unless they bridge to the monitor.
5. The one thread boundary is: `CGEventTapMonitor` → main actor. That's the only place that needs any ceremony. Fold it into an `AsyncStream<KeystrokeEvent>` that the engine consumes with `for await event in monitor.events`.

**Coaching note:** strict concurrency mode is a tool for teaching you where your real boundaries are. When you reach for an unchecked escape hatch, you are deciding that the compiler is wrong — which should require evidence, not convenience.

---

## 14. Tests

66 tests across 7 files is good volume. Let me criticize the quality.

### 14.1 Tests use `Task.sleep` as a synchronization primitive

```swift
typeString(":email")
try? await Task.sleep(for: .milliseconds(50))
XCTAssertEqual(injector.replaceTextCalls.count, 1)
```

(`ExpansionEngineTests.swift:26-34`)

If the expansion takes 51ms on a busy CI, this test flakes. `MockTextInjector.replaceText` is `async` but doesn't actually do anything async (`Mocks.swift:25-27`) — you could make it synchronous and remove the sleeps. Better still, have the mock track completion via an `XCTestExpectation` and `await fulfillment(of:)`.

### 14.2 Tests don't exercise the production plumbing

`handleKeystrokeForTesting` (`ExpansionEngine.swift:136`) bypasses the `monitor.onKeystroke` closure entirely. The test never proves that a real monitor, dispatching through the `@Sendable` closure, lands in the engine's handler. You have 17 engine tests that all use the cheat path. The only test that touches `MockKeystrokeMonitor` is the start/stop count.

Change the tests to go through `monitor.simulateKeystroke(...)` (which exists on `MockKeystrokeMonitor`) so the real closure binding is exercised.

### 14.3 No test for the architectural staleness bug

There's no test for "delete a snippet from the UI and verify the engine stops expanding it." If you had one, it would fail today, and you'd find §1.1 before shipping.

Write the test. Wire `SnippetStore` to a live `ModelContainer` and an `ExpansionEngine` with mock monitor/injector. Add a snippet, type it, assert expansion. Delete via `modelContext.delete` (the UI path), type it, assert no expansion. The test will fail. Then fix §1.1.

### 14.4 No test for ambiguous abbreviations

Register `":sig"` and `":signature"`. Type `":signature"`. What wins? The test suite does not say. This is the single most important behavior of a text expander.

### 14.5 No test for non-ASCII or unicode abbreviations

Every test uses `:email`, `:sig`, `:hi`. Add `:café`, `:日本`, `:🎉`. Watch them fail (see §3.2, §4.2).

### 14.6 No test for `CaseTransform` with non-ASCII

Does `.allUpper` produce the right result for `":straße"`? (German sharp-s has a non-trivial upper mapping.)

### 14.7 No test for case-insensitive duplicate detection

Add `:email`, then attempt `:EMAIL`. What happens? The view says it's a duplicate, the store allows it. Test the contract.

### 14.8 No test for `ClipboardTextInjector`

Understandable because it's hard. At minimum, write a fake target app or extract the "how many backspaces for N graphemes" calculation into a pure function and test that.

### 14.9 No tests for the event tap state machine

Start, stop, double-start, stop-without-start, restart after disabled-by-timeout. These are the failure modes that bite in production.

### 14.10 `CaseTransformTests.test_apply_titleCase_alreadyCapitalized_lowersRest` locks in bad behavior

```swift
XCTAssertEqual(CaseTransform.apply(.titleCase, to: "BEST REGARDS"), "Best regards")
```

(`CaseTransformTests.swift:41-43`)

This test enshrines the bug from §8.1. If you ever try to fix the bug, this test will fail, and someone will "fix" the test instead of the code. This is the most dangerous kind of test: one that is *wrong and green*.

---

## 15. Security and privacy

### 15.1 Every keystroke is captured

The NSAccessibilityUsageDescription says "This happens entirely on your device. Nothing leaves your Mac." That's currently true, but:

- `os.Logger` *is* on-device, but it's also included in `sysdiagnose` tarballs sent to Apple when a user files a crash report. Anything you log (including `matched` abbreviation names, §2.4) can leave the device via that path.
- The `KeystrokeBuffer` holds cleartext typed characters in memory until reset. A process memory dump, a core file, or a screen-share screenshot (of lldb) contains plaintext.

**Mitigations:**

- `.privacy(.private)` on all log interpolations.
- Reset the buffer on screen lock (`NSWorkspace.didActivateScreensaverNotification`, `.screenIsLockedNotification`).
- Reset the buffer when the frontmost app is a password manager or a known-secure context (Keychain Access, System Settings > Users & Groups, Terminal when prompted for sudo password).
- Do not log `matched` at `.info` level. Log at `.debug` and scrub.

### 15.2 Unsandboxed + clipboard access + event tap = high blast radius

You are shipping an unsandboxed app that can read every keystroke and every clipboard contents. The user is trusting you a lot. Respect that trust by:

- Being paranoid about logging (§15.1).
- Shipping a signed + notarized build, always. The current `CODE_SIGN_IDENTITY: "-"` (`project.yml:34`) is a dev-only convenience; make sure CI builds with a real identity.
- Adding a hardened runtime exception list — currently `ENABLE_HARDENED_RUNTIME: YES` is set but there are no entries in the entitlements file for the exceptions this kind of app typically needs. Verify that nothing is silently broken.

### 15.3 Clipboard contents in logs

`PlaceholderResolver` reads clipboard contents into the expansion string. That expansion string is then logged (see §2.4). Now a user's clipboard ends up in syslog because they defined `:clip` → `{clipboard}`. Scrub.

### 15.4 `SettingsManager.updateLoginItem` silently swallows errors

```swift
} catch {
    // Silently fail — login item management can fail in debug builds
}
```

(`SettingsManager.swift:64-66`)

"Fails silently in debug" is not a reason to fail silently in release. The user toggles "Launch at Login", nothing happens, toggle reads as on, they reboot, nothing launches. Catch release-build errors and surface them.

---

## 16. Infrastructure

### 16.1 `xcodeVersion: "16.0"` is a tight pin

If your CI runs on Xcode 16.2 or 16.4, you're fine — xcodegen treats this as a minimum. But if you want reproducibility, pin the full version in CI and drop it from `project.yml` or be explicit that this is a floor.

### 16.2 No CI configuration in repo

I don't see `.github/workflows` in the listing. Make sure there is one, and make sure it runs `make format --lint`, `make lint`, `make test` on every PR. Otherwise the pre-PR checklist in CLAUDE.md is an honor system that will fail the day someone is in a rush.

### 16.3 No dependency on XcodeGen pinning

`minimumXcodeGenVersion: "2.38"`. Fine, but the Makefile doesn't install XcodeGen — it assumes it's on the PATH. Document it, or use `brew bundle` / a `.tool-versions` file.

### 16.4 No way to reproduce a user's state

For a keystroke app, "it worked on my machine" is the whole support story. Give users a way to export + import their snippet library for bug reports, and include app version + macOS version + accessibility-trust state in any error message.

---

## 17. What's actually good

I want this review to not be only criticism. These parts are solid and worth keeping:

- **Protocol-first service design** is a good instinct, and the services are small and testable. The protocols need some completion work (see §1.2, §6.5) but the shape is right.
- **`@Observable` + `withObservationTracking` re-subscription pattern** is the correct idiom for reactive wiring without Combine. Good call.
- **Separation of KeystrokeBuffer from KeystrokeMonitor** makes the ring-buffer logic unit-testable without touching AppKit. This is exactly the right factoring.
- **In-memory SwiftData tests** via `ModelConfiguration(isStoredInMemoryOnly: true)` (`SnippetStoreTests.swift:12`) is the right pattern.
- **XcodeGen as source of truth** with `.xcodeproj` gitignored is the right discipline. It eliminates a huge class of merge conflicts.
- **SwiftFormat + SwiftLint --strict in pre-PR checklist** is a good habit. Add CI enforcement so it's not optional.
- **CLAUDE.md** is the best kind of internal doc — architecture diagrams in prose. Keep it up to date as services change.

---

## 18. Prioritized fix list

If I had to land these in order, here is what I'd do:

### P0 — block shipping 1.0
1. Unify snippet mutation through `SnippetStore` so the engine's map updates (§1.1).
2. Fix `CGEventTapMonitor` use-after-free and `kCGEventTapDisabledByTimeout` handling (§4.1, §4.3).
3. Fix Unicode truncation in `keyboardGetUnicodeString` (§4.2).
4. Enforce word-boundary or sigil on abbreviation matching (§2.1 / §2.5). Right now a snippet named `the` is a footgun.
5. Scrub `os.Logger` interpolations to `.privacy(.private)` (§2.4, §15.1).
6. Fix the `AddSnippetView` double-prefix and dead error state (§11.1), and the `OnboardingView` single-vs-double colon mismatch (§11.6).

### P1 — needed before real users hit it
7. Replace `ClipboardTextInjector` with `CGEvent.keyboardSetUnicodeString`-based injection (§5.1-§5.6).
8. Deterministic longest-match + cached abbreviation set in `ExpansionEngine` (§2.1).
9. Fix `CaseTransform` to preserve original casing (§8.1).
10. Batch `incrementUsageCount` writes (§6.2, §6.3).
11. Remove `@unchecked Sendable` from `@MainActor` classes (§1.3, §13).
12. Real CSV parser with escaped-quote and embedded-newline support (§10.1).
13. Test for UI-delete → no-more-expansion (§14.3).

### P2 — hygiene and coaching
14. Complete `SnippetStoring` protocol with `updateSnippet` etc. (§1.2).
15. Use SwiftData `@Relationship` between `Snippet` and `SnippetGroup` (§7.1).
16. Add `@Attribute(.unique)` to `Snippet.abbreviation` and `AppExclusion.bundleIdentifier` (§7.2).
17. Cache `DateFormatter` and `PlaceholderResolver` in the engine (§9.1).
18. Debounce `SnippetDetailView` writes (§11.2).
19. Delete the dead `Rename...` button or implement it (§11.4).
20. Add CI, enforce format/lint/test on PR (§16.2).
21. Fix the `CaseTransform` test that locks in the `"BEST REGARDS" → "Best regards"` bug (§14.10).

### P3 — future-proofing
22. SwiftData schema versioning (§7.3).
23. Trie-based matching for 10k+ snippet libraries (§2.1).
24. Custom date format strings in placeholders (§9.2).
25. File-based app picker for exclusion (§11.9).
26. Accessibility-trust observation via `DistributedNotificationCenter` (§11.5).

---

## 19. Coaching notes — what to internalize

For the more junior members of the team, these are the meta-lessons from the specific findings:

1. **Observation patterns only work if mutation cannot bypass them.** Every `modelContext.insert` in a view is a hole in your observer. When you expose two ways to do the same thing, one of them will drift. Funnel writes through a single API.

2. **`try?` and `// silently fail` are debt.** Every one needs a comment explaining why it's safe. If you can't write the comment, it's not safe.

3. **`@unchecked Sendable` is a lie you tell the compiler.** It should hurt to type. Treat it like `unsafeBitCast` — last resort, with a paragraph of justification.

4. **"Works on ASCII" is not "works".** Any code that touches characters, keystrokes, or text must be tested with non-ASCII input from day one. Add a unicode test alongside every feature.

5. **Magic sleeps are a symptom, not a solution.** If you need `Task.sleep(50ms)` to make your code work, find the thing you should have been waiting for and wait for *that*. If there's no such thing, the design is wrong — change the design.

6. **Test the path production uses.** If your tests bypass the `onKeystroke` closure plumbing, they don't test the plumbing. If your tests never delete via the same method the UI calls, they never catch UI-deletion bugs. A test of the cheat path is worse than no test — it gives false confidence.

7. **Lock in behavior, not bugs.** Before you write `XCTAssertEqual("BEST REGARDS" → "Best regards")`, ask: *is this what I want, or is this what the code happens to do?* Tests are specifications. Don't specify a bug.

8. **Log like everything is PII.** For any tool with broad system access, the default privacy assumption is "logs leak". Use `.privacy(.private)` until you have a specific reason not to.

9. **C callbacks and ARC do not mix casually.** `Unmanaged` is a sharp tool. `passUnretained` says "I promise this object outlives the callback." If you can't prove that promise, use `passRetained` and release explicitly on teardown.

10. **Two sources of truth is zero sources of truth.** When the view has `@Query` and the service has `abbreviationMap`, one of them will be stale. Pick a single authority.

11. **Complete your protocols.** A protocol with three of the five needed methods is worse than no protocol — it implies a boundary that isn't there.

12. **Respect the threading model macOS gave you.** `@MainActor` is not a decoration. `NSWorkspace`, `NSPasteboard`, `NSStatusItem`, `NSWindow` — all main-thread. Strict concurrency will tell you this if you let it.

13. **Never ship dead UI.** A button that says "Rename..." and does nothing is a trust-breaking bug. Either implement it or delete it.

14. **Own the whole error path.** `replaceText` returns `Void`, which means "I succeeded" to the engine even when the paste failed. Every side-effecting function needs a way to say "I failed" and every caller needs a plan for handling that.

15. **Review your own code like you're reviewing a stranger's.** If you had not written `ExpansionEngine`, would you trust it with every keystroke on your machine? That is the bar.

---

## 20. Closing

None of the problems in this review are unfixable. Most of them are 10-100 lines of code. The architecture is salvageable — the service boundaries are in roughly the right places, the tests exist as a scaffold, and the project infra is clean.

The thing I'd want the team to take away is this: **the code currently looks right without being right.** The observer pattern looks right. The protocol-first services look right. The case-insensitive matching looks right. The tests look right. But in each case there's a gap — the UI bypasses the observer, the protocol is incomplete, the matching destroys case data, the tests call a back-door. That pattern is what makes brownfield code dangerous: it projects confidence it hasn't earned.

The fix is cultural, not technical. On every PR, ask: *what is the evidence this works in production, not just in the test harness?* If the answer is "the test passes", dig further. Good engineering is not making the test pass. It is making the test meaningful.

Good luck. The foundation is here; it just needs someone to insist on the details.
