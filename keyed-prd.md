# Keyed — A Native macOS Text Expansion Tool
### Product Requirements Document

| | |
|---|---|
| **Version** | 0.1 — Draft |
| **Date** | April 2026 |
| **Author** | Max Clayton Clowes |
| **Product** | Keyed |
| **Company** | Marginal Utility |
| **Status** | For internal review |

---

## 1. Overview

Text expansion is a well-understood problem. You type a short abbreviation; a longer piece of text appears in its place. The concept is not new. The execution, in 2026, is still largely broken or overpriced.

macOS ships with a built-in text replacement system that silently fails in Firefox, Electron apps, and a rotating cast of other environments. The tools that fix this gap either demand a subscription for a feature set most solo users will never touch, or they look and feel like they were designed in 2011.

Keyed is a lightweight, native macOS text expansion tool for individual users. One-time purchase. Works everywhere. Looks like it belongs on a modern Mac.

### 1.1 Product Positioning

Keyed sits within the Marginal Utility catalogue alongside Clipped (clipboard manager) and Barred (menu bar manager). Together they form a suite around a coherent idea: the Mac assumes you can only hold one thing at a time, and it is wrong. Keyed addresses the typing dimension of that problem.

### 1.2 Problem Statement

- Apple's native text replacement does not work in non-Cocoa apps (Firefox, Chrome, most Electron apps including Slack, VS Code, Notion)
- TextExpander — the category leader — moved to a mandatory subscription in 2016. For solo users, the pricing is misaligned with actual usage
- Dedicated one-time-purchase tools (Typinator, aText, TypeIt4Me) are functional but aesthetically dated and have stagnated
- Tools bundled inside launchers (Raycast, Alfred) require a different interaction model — search-and-select rather than type-and-expand — and are secondary features, not first-class tools
- Espanso is free and cross-platform but requires YAML configuration files. There is no GUI. It is not for most people

### 1.3 Opportunity

There is a clear gap for a native, well-designed, one-time-purchase text expansion tool aimed at individual Mac users who want something that just works — without enterprise overhead, subscription fatigue, or setup friction.

This is the same positioning that made Clipped viable. The clipboard management space had incumbents. The gap was a tool that respected the platform aesthetic and did not overreach.

---

## 2. Goals & Success Metrics

### 2.1 Goals

- Ship a text expansion tool that works reliably across all macOS apps, including Electron and non-Cocoa environments
- Provide a setup experience that takes under two minutes from download to first expansion
- Match the design quality and restraint of the existing Marginal Utility catalogue
- Establish a one-time-purchase pricing model that competes on value against subscription alternatives
- Achieve the same word-of-mouth distribution pattern as Clipped — users recommend it because it is genuinely good, not because of marketing

### 2.2 Non-goals

- Team sharing and collaborative snippet libraries — this is TextExpander's core differentiator; we are not competing on it
- Cross-platform support (Windows, iOS) in v1
- Advanced scripting, AppleScript integration, or shell execution in snippets
- AI-assisted snippet generation in v1
- Browser extensions

### 2.3 Success Metrics

| Metric | Target (3 months) | Target (12 months) |
|---|---|---|
| Downloads | 500 | 3,000 |
| Trial-to-paid conversion | >20% | >25% |
| App Store rating | ≥4.5 | ≥4.6 |
| D30 retention (snippets created) | >40% | >50% |
| Avg. snippets per active user | >8 | >15 |

---

## 3. Target User

Keyed is for individual Mac users who type the same things repeatedly and are frustrated that macOS's built-in text replacement silently fails in half their apps. They are not looking for a team tool. They are not looking for automation software. They want something that works, costs a reasonable amount once, and does not require them to read a manual.

### 3.1 Primary Personas

**The Knowledge Worker**

Works primarily in a browser and two or three desktop apps. Types variations of the same responses, signatures, and phrases every day. Has probably tried macOS text replacement and given up after it failed in Slack or Chrome. Would pay £15–25 for something that reliably solved this.

- Uses: Mail, Slack, Notion, Chrome or Firefox, occasionally Word
- Recurring text: email sign-offs, support responses, meeting notes templates, personal info fields
- Pain: native macOS text replacement stops working after macOS updates or in non-native apps

**The Developer / Power User**

Spends most of their day in VS Code, Terminal, and a browser. Has strong opinions about their tools. Might already use Espanso but finds it fiddly. Wants something with a GUI that doesn't feel like a compromise.

- Uses: VS Code, iTerm, GitHub, Jira, Figma, Slack
- Recurring text: code snippets, boilerplate, ticket references, CLI commands, variable patterns
- Pain: Espanso requires YAML editing; Raycast snippets aren't inline expansion

---

## 4. Competitive Landscape

| Tool | Price | Works everywhere | Key weakness |
|---|---|---|---|
| Apple text replacement | Free | No | Fails in Firefox, Chrome, Electron apps silently |
| TextExpander | $3.33/mo | Yes | Subscription-only; overbuilt for solo users |
| Typinator | ~£35 one-off | Yes | Dated UI; manual iCloud sync setup; stagnant |
| Raycast snippets | Free | Partial | Search-select, not inline expansion; secondary feature |
| Alfred snippets | Free/£34 | Partial | Reported lag; inconsistent; secondary feature |
| Espanso | Free | Yes | No GUI; YAML config only; not for most users |
| aText / TypeIt4Me | £19–29 | Yes | Minimal development; aged aesthetics |

### 4.1 Keyed's Differentiation

- Works everywhere on macOS via accessibility API input simulation, not NSTextCheckingClient
- One-time purchase, priced for individuals not teams
- Native Swift + SwiftUI; matches modern macOS design language
- Setup in under two minutes — no sync services, no account creation required
- Part of a coherent catalogue that builds trust with users already on Clipped or Barred

---

## 5. Features & Requirements

### 5.1 Core: Snippet Management

**Must have**

- Create, edit, and delete snippets via a clean main window
- Each snippet has: an abbreviation trigger, expansion text, and an optional label/description
- Abbreviation triggers support alphanumeric characters plus common prefix conventions (`:`, `;;`)
- Expansion text supports plain text; formatted text is a stretch goal for v1
- Snippets organised into user-defined groups or collections
- Fuzzy search across snippets by abbreviation or label
- Import from common formats (CSV, TextExpander `.textexpander` files) to ease migration

**Should have**

- Duplicate snippet detection with merge prompt
- Sort by most-used, alphabetical, or recently created
- Snippet usage count visible in management view

### 5.2 Core: Expansion Engine

**Must have**

- System-wide expansion via accessibility API — must work in Firefox, Chrome, Slack, VS Code, Notion, and other Electron or non-Cocoa apps
- Typed abbreviation is deleted and replaced with expansion text in under 100ms on modern hardware
- No visible flicker or intermediate state during expansion
- Per-app exclusion list: user can disable Keyed in specific applications
- Global on/off toggle accessible from menu bar icon

**Should have**

- Case-matching: if trigger is typed in ALL CAPS or Title Case, expansion follows suit where possible
- Cursor positioning: optionally place cursor at a defined point in the expanded text

**Nice to have**

- Date/time placeholders in expansions ("Today is {date}")
- Clipboard placeholder: insert current clipboard content into expansion

### 5.3 Onboarding

**Must have**

- Onboarding flow that requests Accessibility permission with clear explanation of why it is needed
- Starter snippet set covering the most common use cases (email address, signature, date)
- First-run experience completes in under 2 minutes to first working snippet

**Should have**

- Suggested snippets based on common patterns (detects if user types the same phrase multiple times — see Section 5.5)

### 5.4 Menu Bar Presence

**Must have**

- Keyed lives in the menu bar; no persistent Dock icon by default
- Menu bar icon provides: global toggle, quick snippet count, open main window
- Complements Barred — Keyed's icon should behave well when organised or hidden by Barred

### 5.5 Smart Suggestions _(Differentiating Feature)_

This is where Keyed can move beyond a feature-equivalent of existing tools. Using the accessibility API's observation capabilities, Keyed can detect when a user types the same phrase multiple times across sessions and surface a prompt to save it as a snippet.

This is a passive, opt-in capability. No content is stored without user action. The prompt is non-intrusive: a brief notification or indicator in the menu bar. The user reviews and confirms; nothing is created automatically.

**Must have**

- Detection runs locally, on-device. No text content is transmitted anywhere
- User can disable this feature entirely in preferences
- Suggestions are presented in a review queue, not applied automatically

**Should have**

- Configurable sensitivity threshold (e.g. suggest after 3 repetitions vs 5)
- Ability to dismiss suggestions permanently without creating a snippet

_This feature is the clearest point of differentiation from existing tools, all of which require users to proactively think of what they want to save. Keyed watches what you actually type and meets you there._

### 5.6 iCloud Sync

**Should have**

- Optional iCloud sync for snippets across the user's own Macs
- Sync is opt-in; local-only is a first-class option
- No proprietary cloud service required — data stays in Apple's infrastructure

---

## 6. Technical Approach

### 6.1 Expansion Mechanism

The core technical challenge is system-wide text expansion that works in non-native apps. Apple's `NSTextCheckingClient` (used by native text replacement) is not available to third-party apps and fails in apps that do not implement the `NSTextInput` protocol.

Keyed uses the macOS Accessibility API (`AXObserver`, `AXUIElement`) to monitor keystroke input and simulate replacement via `CGEvent` keyboard injection. This is the same approach used by Typinator and Espanso on macOS, and it is the only approach that reliably works across Cocoa, Electron, and browser environments.

Required permissions: Accessibility (mandatory). Screen recording is not required. This is a meaningful privacy advantage over some competitors.

### 6.2 Stack

- Swift + SwiftUI for all UI
- Swift concurrency (async/await) for non-blocking event handling
- CoreData or SwiftData for local snippet storage
- CloudKit for optional iCloud sync
- No third-party dependencies in the core expansion engine

### 6.3 Distribution

- Primary: direct download from mcclowes.com/docs/keyed (consistent with Clipped and Barred)
- Secondary: Mac App Store (sandbox limitations need investigation for accessibility permissions)
- Pricing: one-time purchase, £17.99 / $19.99. No subscription. No upsell.

---

## 7. Design Principles

Keyed should feel like it was made by the same hands as Clipped and Barred. The same restraint applies.

**Native macOS controls throughout. No custom UI elements that fight the platform.**
List views, sheets, and inspectors over custom panes. Toolbar and sidebar patterns that macOS users already understand.

**Menu bar tool, not a Dock app.**
Keyed is infrastructure, not a workspace.

**Lightweight by default.**
No onboarding videos. No feature tours. A working tool on first launch.

**Trust through transparency.**
Accessibility permission request includes a clear, plain-English explanation:

> "Keyed uses macOS Accessibility to detect what you type and replace abbreviations with your saved snippets. This happens entirely on your device. Nothing leaves your Mac."

---

## 8. Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Apple restricts Accessibility API further in future macOS versions | Medium | Monitor WWDC closely. All existing tools face the same risk. Keyed's approach mirrors Typinator, which has survived many macOS transitions. |
| Mac App Store rejects app due to Accessibility permission requirements | Medium | Direct download is primary channel. App Store is secondary. Clipped and Barred already demonstrate the direct-download model works. |
| Accessibility permission prompts deter users | High | Invest heavily in permission copy. Be explicit about what is and is not happening with user input. No screen recording required — call this out. |
| Suggestion engine surfaces private content unexpectedly | Low | Feature is opt-in. No suggestions are applied automatically. Suggestions can be reviewed and dismissed. Excluded apps list applies here too. |
| Market too small for solo-user text expansion | Low | TextExpander has 1M+ users. Typinator has been commercially viable for 15+ years. The market exists; the gap is positioning. |

---

## 9. Milestones

| Milestone | Target | Scope |
|---|---|---|
| M0 | Technical spike | Validate expansion engine works in Firefox, Chrome, Slack, VS Code. Proof-of-concept only — no UI. |
| M1 | Private alpha | Core expansion engine + basic snippet management UI. Shared with 5–10 trusted testers. |
| M2 | Public beta | All must-have features complete. Onboarding flow. Menu bar presence. Import from TextExpander. Free during beta. |
| M3 | v1.0 launch | All should-have features. iCloud sync. Smart suggestions (opt-in). Pricing enabled. mcclowes.com product page. |
| v1.x | Post-launch | Nice-to-have features, iOS companion consideration, deeper Clipped integration. |

---

## 10. Open Questions

- Can the expansion engine be made to work within sandboxed App Store distribution, or is direct-download the only viable route?
- What is the right abbreviation prefix convention? Should Keyed enforce one (e.g. `:`) or leave it entirely open?
- How sensitive should the smart suggestions engine be by default, and what patterns should disqualify text from suggestion (passwords, URLs, numeric-only strings)?
- Is there a meaningful connection to Clipped to build in v1 — e.g. promoting a clipboard item to a saved snippet — or does that overcomplicate the first release?
- Pricing: £17.99 is a hypothesis. Does this need validation against willingness-to-pay research before launch?

---

*Marginal Utility — Keyed PRD v0.1 — April 2026*
