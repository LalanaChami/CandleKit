# CandleKit

Open-source Swift package for interactive candlestick charts on iOS: TradingView-style interaction (momentum scroll, anchored pinch zoom, long-press crosshair, live updates, infinite history) with an Apple-native feel. MIT licensed, maintained by Lalana (@LalanaChami). `Demo/` holds an iOS demo app built on the package.

<!-- Maintainers: keep this file under ~150 lines. Area-specific guidance lives in .claude/rules/ (loaded only when matching files are touched). The work plan lives in docs/ROADMAP.md. HTML comments like this one are stripped before Claude sees the file. -->

## Current state — read first

- **The code has never been compiled.** v0.1 was written without a Swift toolchain. Expect compile errors, especially in `Sources/CandleKit/` (Swift 6 concurrency, UIKit bridging, Accessibility APIs). Getting it building is roadmap Phase 0. A later pass (see `CHANGELOG.md`, "Unreleased") fixed several leak/smoothness bugs found by *reading* the code, which is still true of that pass too — it needs the same Phase 0 build-and-device verification before anyone should trust it.
- No CI, no release tag. The README's `from: "0.1.0"` doesn't resolve yet.
- **Never change anything for performance without a trace.** `docs/PERFORMANCE.md` has the instrumentation, the capture recipe and a trace log; record a before/after entry in the same change. Three rounds of code-reading-based perf work shipped before this rule existed and mis-ranked the costs every time.
- All planned work, known issues and open questions are in `docs/ROADMAP.md`. Read the relevant section before starting a task, and update its status in the same change that completes it. Check `CHANGELOG.md` for what's already changed and why before re-deriving the same reasoning.

## Commands

Package, from the repo root:
- `swift build` and `swift test`: build everything and run the CandleKitCore tests.
- `swift test --filter Viewport`: run matching suites or tests.
- `xcodebuild build -scheme CandleKit -destination 'generic/platform=iOS Simulator'`: **the only command that compiles the SwiftUI layer.** Every file in `Sources/CandleKit/` is wrapped in `#if os(iOS)`, so `swift build` on macOS succeeds even when that layer is broken.

Demo app, from `Demo/`:
- `xcodegen generate`: creates `CandleKitDemo.xcodeproj` from `project.yml`. The project file is gitignored; never edit it directly.
- `xcodebuild build -project CandleKitDemo.xcodeproj -scheme CandleKitDemo -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
- For anything that runs on a simulator, pick a device from `xcrun simctl list devices available` instead of guessing a name.

## Structure

- `Sources/CandleKitCore/`: pure Foundation engine (viewport math, series diffing, price and time scales, indicators, sample data). Builds and tests on macOS and Linux.
- `Sources/CandleKit/`: SwiftUI and UIKit layer (`CandlestickChart`, `CandleChartState`, Canvas renderers, crosshair, gestures, accessibility). Re-exports Core, so apps only `import CandleKit`.
- `Tests/CandleKitCoreTests/`: swift-testing suites for Core.
- `Demo/`: iOS 17 SwiftUI app generated with XcodeGen. Tabs: live Coinbase market, style gallery, chart inside a ScrollView, performance.

## Architecture decisions

Don't reverse these without raising it with the maintainer first.

- **Index-based x-axis.** Candle `i` occupies positions `[i, i+1)`. Nights, weekends and holidays never leave gaps. `Viewport.rightEdge` is a fractional position and `spacing` is points per candle.
- **Canvas renderer, not Swift Charts.** Swift Charts has no zoom model and can't rebuild thousands of marks per frame. Candles are batched into a few paths (rising or falling bodies and wicks), so draw calls stay constant.
- **Crosshair on its own layer.** `CrosshairLayer` and `ChartHeader` read crosshair state. The base layer doesn't, so moving a finger never redraws candles.
- **Observation pattern.** `CandleChartState.makeFrame(...)` runs during view body evaluation and adjusts the viewport for new data there. It may only mutate `@ObservationIgnored` properties; mutating observed ones causes "Modifying state during view update". Viewport changes made outside rendering (gestures, public methods) must bump `revision`, which the chart body reads to redraw.
- **UIKit gestures.** A transparent `UIViewRepresentable` over the plot hosts real pan, pinch, long-press and double-tap recognizers. This gives simultaneous pan and pinch, release velocity, and "only claim horizontal drags" for ScrollView embedding. Momentum uses `CADisplayLink` with exponential decay.
- **Data diffing by fingerprint.** `SeriesChange` compares count and first/last times. Prepends keep the same candles on screen; appends scroll only when the latest candle is visible; an unrelated series jumps to the latest.
- **Future drawing tools anchor to (time, price)**, not indices, because prepending history shifts indices.
- **No third-party runtime dependencies.** Test-only dependencies need maintainer approval.

## Rules

- Logic that doesn't need a screen belongs in CandleKitCore, with tests. Keep the SwiftUI layer thin.
- Swift 6 language mode, iOS 17 minimum. Don't silence concurrency diagnostics with `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency` unless there's no alternative, and leave a comment explaining why.
- Nothing that runs per frame may do work proportional to the total candle count. Work over the visible range only.
- Public API follows Swift Charts' modifier style: methods on `CandlestickChart` return a modified copy. Every public symbol needs a doc comment. A public API change also updates the README, the demo, and `CHANGELOG.md` (once it exists).
- The demo uses only public API. If it needs something the library doesn't expose, record that as an API gap in the roadmap; don't reach into internals.
- Data contract: candles sorted by time ascending, with unique times. Only the last candle is expected to change in place.
- Never commit API keys or secrets. The demo uses unauthenticated Coinbase endpoints only.

## Pitfalls

- `swift build` passing proves nothing about `Sources/CandleKit/`. Always run the `xcodebuild` iOS build after touching that layer.
- If a Core test fails, suspect the implementation before the expected values. The v0.1 expectations were checked numerically against an independent port of the algorithms. Change an expectation only with a written reason.
- `CADisplayLink` retains its target. Momentum must be stopped when the view is dismantled (`ChartGestureView.dismantleUIView`).
- Hidden directories (`.github/`, `.claude/`) have been lost when files were copied into this repo before. After adding one, check `git status`.
- `Demo/project.yml` must point at the local package (`path: ..`) so the demo builds against the working tree. Pointing it at the GitHub URL builds the last pushed commit instead. It still points at the URL until task 0.3 is done.

## Definition of done

1. `swift test` passes.
2. The iOS `xcodebuild` build of `CandleKit` passes. If the UI layer or public API changed, the Demo builds too.
3. New Core logic has tests. Bug fixes get a regression test wherever the logic is testable.
4. `docs/ROADMAP.md` reflects the new status.
5. The completion report separates **verified** (commands you ran and their results) from **unverified**. Gestures, haptics, rendering, VoiceOver and performance can't be verified from the command line. List exactly what the maintainer should check on a device, and don't describe unverified behavior as working.

## Working style

- The maintainer prefers direct feedback. If a task rests on a wrong assumption or a roadmap item looks misguided, say so before implementing.
- Use plan mode for public API changes, cross-layer refactors, and anything touching gestures, the observation pattern or rendering.
- One roadmap task per branch or PR. Commit messages start with the roadmap ID, for example `0.2: Fix Swift 6 isolation in gesture coordinator`.
