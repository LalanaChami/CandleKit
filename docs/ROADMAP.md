# CandleKit roadmap

Last reviewed: 2026-09-11

This is the working plan for CandleKit and its demo. It's written to be executed one task at a time, mostly by Claude Code, with the maintainer verifying on device what can't be checked from the command line.

## How to use this document

- Work phases in order. A phase is done when its exit criteria are met. Tasks marked **(parallel-safe)** can be done early without blocking anything.
- Tasks marked **(design first)** start in plan mode. Write a short design note (in the PR description or `docs/design/`) and get the maintainer's agreement before implementing.
- Each task lists who verifies it. **CLI** means commands prove it. **Device** means the maintainer must check it on a simulator or phone.
- When you finish a task, tick its box, add a one-line note if something differed from the plan, and move any new problems you found into [Known issues](#known-issues).
- Don't silently expand scope. If a task turns out to need more than described, stop and report back.

Status key: `[ ]` not started · `[~]` in progress · `[x]` done · `[-]` dropped (with reason)

---

## Phase 0: Make it build

**Goal:** the package and demo compile, tests pass, and CI keeps it that way. Nothing else starts until this is done.

- [x] **0.1 Core compiles and tests pass.** Run `swift build` and `swift test` on macOS and fix what fails in `Sources/CandleKitCore/`. If a test fails, investigate the implementation before touching the expected values (see CLAUDE.md pitfalls). *Verify: CLI.* — No fixes needed; `swift build` and `swift test` both passed clean (36/36 tests, 6 suites) on the first run.
- [x] **0.2 SwiftUI layer compiles for iOS.** Run `xcodebuild build -scheme CandleKit -destination 'generic/platform=iOS Simulator'` and fix errors. Likely trouble spots, all written without a compiler:
  - `ChartGestureView.swift`: `@objc` selectors on a `@MainActor` class, `CADisplayLink` target, delegate isolation.
  - `ChartAccessibility.swift`: exact initializer signatures of `AXNumericDataAxisDescriptor`, `AXDataSeriesDescriptor`, `AXDataPoint` and `AXChartDescriptor`, and whether the value-description closures must be `@Sendable`.
  - `CrosshairLayer.swift`: `sensoryFeedback(_:trigger:condition:)`.
  - `CandlestickChart.swift`: `@unknown default` on `AccessibilityAdjustmentDirection`, and `let _ =` statements in view builders.
  - `CandleChartState.swift`: `@Observable` combined with `@MainActor`, `@ObservationIgnored` and `private(set)`.

  Fix root causes; don't add escape hatches. List each non-obvious fix in the PR description. *Verify: CLI.* — No fixes needed; `xcodebuild build -scheme CandleKit -destination 'generic/platform=iOS Simulator'` passed with zero errors and zero warnings on the first run.
- [x] **0.3 Demo builds against the local package.**
  - `Demo/project.yml` switched from `url: + branch:` to `path: ..`.
  - `Demo/README.md` rewritten for the monorepo layout: "Update to Latest Package Versions" and "clone both repos side by side" instructions removed.
  - `Demo/LICENSE` removed; the root LICENSE covers the whole repo.
  - `xcodegen generate` + `xcodebuild` succeeded with zero errors and zero warnings. No Swift 6 fixes needed — `CoinbaseMarketData` was clean as written.
  *Verify: CLI.*
- [~] **0.4 CI.** `.github/workflows/ci.yml` written with three jobs:
  1. `core-linux`: `swift test` in the `swift:6.0` container on `ubuntu-latest`.
  2. `core-macos`: `swift test` + `xcodebuild CandleKit` (iOS Simulator) on `macos-15`.
  3. `demo`: `brew install xcodegen`, `xcodegen generate`, `xcodebuild CandleKitDemo` on `macos-15`.
  Triggers on push to `main` and on pull requests. `.github/` is untracked (`??`) — not gitignored. *Verify: a green run on GitHub after the first push.*
- [ ] **0.5 Simulator smoke test.** Claude writes `docs/QA.md` (the checklist in 1.1). The maintainer launches the demo and confirms all four tabs render and the chart responds to touch. Watch Xcode's console for purple runtime warnings: "Modifying state during view update", "Publishing changes from within view updates", main-thread checker hits. Paste any into an issue. *Verify: Device.*
- [ ] **0.6 Repository hygiene** (parallel-safe).
  - Add `CHANGELOG.md` in Keep a Changelog format.
  - Update `CONTRIBUTING.md` with the real build commands, including the iOS `xcodebuild` step and the demo workflow.
  - Decide on formatting: `swift format` ships with the Swift 6 toolchain. If adopted, add a config and a CI lint step in a separate PR.

  *Verify: CLI.*
- [x] **0.7 Scroll and haptic UX polish** (parallel-safe).
  - Rubber-band overscroll at both data edges with resistance proportional to overscroll distance, spring-back on release.
  - `makeFrame` skips viewport clamping while `isRubberBanding` is set, so the overscroll renders correctly.
  - Haptics: medium impact on crosshair engage, soft on dismiss, light on momentum edge-hit (once per scroll run), rigid on zoom limit (once per pinch session), medium on double-tap reset.
  - Spring-animated zoom reset (double-tap uses `animatedResetZoom()`; programmatic `resetZoom()` still snaps).
  - Long-press minimum duration reduced 0.25 s → 0.15 s.
  *Verify: CLI build. Device: rubber-band feel at both edges, correct haptic at each event, spring-back with no bounce, no double-firing on crosshair appear.*
- [x] **0.9 Loading animation** (parallel-safe).
  - `SkeletonChartView` added to `Demo/CandleKitDemo/Market/`. Draws 30 deterministic placeholder candles using overlapping sine waves so the shape is consistent across appearances, with a gradient shimmer band that sweeps left → right via `TimelineView(.animation)`.
  - `MarketView.chart` restructured from `switch` to `if/else` so SwiftUI can track view identity and apply `.transition(.opacity)` on each branch. A `.animation(.easeInOut(duration: 0.35), value: feed.candles.isEmpty)` modifier crossfades skeleton ↔ real chart when the user changes timeframe or product.
  - `MarketView.realChart` extracted as a separate `@ViewBuilder` property; `failureMessage` helper extracts the error string from `feed.status` to keep the `@ViewBuilder` readable.
  *Verify: CLI build. Device: switching timeframe shows skeleton while loading, then crossfades to the real chart.*
- [x] **0.8 Pan scroll smoothness** (parallel-safe).
  - `PriceScale.autoRange` now uses a ±5-candle padded window around the viewport so the price axis stays stable when a single candle enters or leaves the visible range during panning — eliminating vertical jitter on all candle Y-positions.
  - `estimatedInterval` cached in `CandleChartState` and updated only when series data changes (not every frame). Zero calls during a pan; one call on data update. `TimeScale.ticks()` accepts an optional `interval:` parameter so callers avoid a second internal call.
  - Time-axis labels now fade in/out over a 48 pt zone at both edges instead of hard-clipping at 16 pt, so labels scroll in smoothly rather than popping.
  *Verify: CLI build + 36/36 tests. Device: pan feels fluid — no axis jitter, labels fade in at edges.*

**Exit criteria:** CI is green on `main`; the demo runs in the simulator with all four tabs working; no runtime warnings from CandleKit.

---

## Phase 1: Correct on device

**Goal:** everything v0.1 claims actually works on real hardware. No new features in this phase.

- [ ] **1.1 Device QA pass.** Work through `docs/QA.md` on at least one ProMotion iPhone and one iPad. The checklist covers:
  - Pan with momentum that stops at the data edges.
  - Pinch that keeps the candles under the fingers fixed, and pan and pinch together.
  - Long-press crosshair with haptic ticks, cleared on lift, while the header follows the crosshair.
  - Double-tap reset.
  - A vertical drag starting on the chart scrolls the page in the "In a page" tab.
  - Rotation and resizing, including iPad split view.
  - Light and dark mode, and increased contrast.
  - Dynamic Type from XS to AX5.
  - VoiceOver: summary, swipe up and down to page, and the Audio Graph.
  - Live data: follows the latest candle when at the right edge, stays put when scrolled back.
  - History paging.
  - Momentum at 120 Hz on ProMotion.

  Each failure becomes a Known issue with steps to reproduce. *Verify: Device.*
- [ ] **1.2 Fix history loading edge cases (KI-1, KI-2).** (design first)
  - The history request must re-arm after a failed fetch, for example once the user scrolls away from the edge and back.
  - The request must also fire when the initial data doesn't fill the screen, which currently only gets checked on pan or zoom.
  - The handler must never run during a view update.
  - Add `CandleChartState` tests, which need the iOS test target from 2.2; do 2.2 first or together.

  *Verify: CLI plus Device.*
- [ ] **1.3 Crosshair survives history prepends (KI-3).** (design first) While a finger is down and older candles are prepended, the crosshair must stay on the same candle. Likely approach: track the crosshair by candle time or shift the index by the prepend count, without mutating observed state during render. *Verify: CLI where testable, plus Device.*
- [ ] **1.4 Price axis width fits its labels (KI-4).**
  - Size the price axis from the widest label it will show (tick labels and the last-price tag) at the current Dynamic Type size.
  - Avoid layout jitter while panning, for example by only letting it grow within a series or by sizing from the data's maximum magnitude.
  - Test with BTC-scale prices (64,000.00), sub-cent prices (0.00001234) and AX sizes.

  *Verify: Device.*
- [ ] **1.5 Performance baseline.**
  - Profile a release build of the demo's Performance tab with Instruments (Animation Hitches and SwiftUI templates) at 1K, 10K and 100K candles.
  - Confirm the base layer doesn't re-render while only the crosshair moves.
  - Record device, OS, dataset size, hitch rate and time per frame in `docs/PERFORMANCE.md`. These numbers decide whether 5.4 (incremental indicators) and a Metal renderer are ever needed.

  *Verify: Device.*

**Exit criteria:** the QA checklist passes on iPhone and iPad; KI-1 to KI-4 are closed; a performance baseline is recorded.

---

## Phase 2: Test and quality infrastructure

**Goal:** regressions in the UI layer get caught automatically.

- [ ] **2.1 Pull renderer geometry into testable functions** (parallel-safe after Phase 0). Candle pixel widths and parity, body and wick rectangles, layout bands, and price and time tag clamping become pure functions with tests. Put them in Core (using `Double`) where that's natural. *Verify: CLI.*
- [ ] **2.2 iOS unit-test target.** Add `CandleKitTests` (swift-testing, `@MainActor` suites) run with `xcodebuild test` on a simulator. It covers `CandleChartState`:
  - Pan and zoom clamping.
  - Following the latest candle versus staying put on append.
  - Prepend adjustment.
  - Deduping and re-arming the history handler.
  - Crosshair index bounds.

  Add the job to CI. *Verify: CLI.*
- [ ] **2.3 Snapshot tests.** (design first, needs maintainer approval for a test-only dependency such as swift-snapshot-testing) Cover:
  - Light, dark and increased contrast.
  - The standard, red-up, color-blind-safe and hollow styles.
  - Volume off, header off, crosshair visible.
  - Empty data, a single candle, flat prices, huge and tiny prices.
  - AX Dynamic Type.

  Pin the simulator model and OS in CI so images are stable. *Verify: CLI.*
- [ ] **2.4 Edge-case hardening.** Add tests, then fixes, for:
  - NaN or infinite prices, zero or negative volume.
  - Duplicate or unsorted times. Decide between debug assertions and tolerance.
  - A zero-size or tiny frame, and extreme zoom levels.
  - Swapping between very different series.

  *Verify: CLI.*

**Exit criteria:** CI runs the Core tests, iOS unit tests and snapshot tests on every PR.

---

## Phase 3: Release 0.1.0

**Goal:** people can depend on a tagged version and find the package.

- [ ] **3.1 API review.** (design first) Review the whole public surface before tagging:
  - Naming consistency: `candleChartStyle(_:)` versus `volumeVisible(_:)`, `headerVisible(_:)`, `priceFractionDigits(_:)`.
  - What `CandleChartState` exposes.
  - Whether `IndicatorKind` should become an open protocol before users depend on the enum (see 5.2).
  - Default values.

  Record decisions in the PR. *Verify: maintainer sign-off.*
- [ ] **3.2 DocC documentation.** Add documentation catalogs for `CandleKit` and `CandleKitCore` with articles: getting started, streaming live data, loading history, customizing appearance, accessibility. Audit every public doc comment. *Verify: CLI (`swift package generate-documentation` or an Xcode docs build).*
- [ ] **3.3 README with real media.** Record screenshots and a short GIF from the demo, in light and dark mode. Link the demo, fix install instructions for the tag, and describe the demo setup. *Verify: maintainer.*
- [ ] **3.4 Name check.** The maintainer confirms no widely used package or module called `CandleKit` would clash, checking GitHub and the Swift Package Index. *Verify: maintainer.*
- [ ] **3.5 Tag and publish.** Update `CHANGELOG.md`, tag `0.1.0`, write GitHub release notes, add `.spi.yml` and submit to the Swift Package Index. Confirm a fresh app can add `.package(url: "https://github.com/LalanaChami/CandleKit.git", from: "0.1.0")`. *Verify: CLI plus maintainer.*

**Exit criteria:** tag `0.1.0` is published and resolvable, the docs build, and the README shows the real chart.

---

## Phase 4: 0.2, interaction polish

- [ ] **4.1 Eased autoscale (KI-6).** (design first) Animate the price range toward its target instead of snapping. Decide what happens during an active pan (snap or ease), and respect Reduce Motion. The animation must not re-run layout for the whole chart every frame.
- [ ] **4.2 Time labels stable across prepends (KI-5).** Anchor label strides to calendar or epoch multiples of time instead of index multiples. Keep the promotion to day, month and year labels.
- [ ] **4.3 Manual price scaling.** Dragging vertically on the price axis scales prices, and double-tapping the price axis returns to autoscale. Expose the mode on `CandleChartState`. Must not break ScrollView embedding.
- [ ] **4.4 iPad pointer and keyboard.** Show the crosshair on hover (`UIHoverGestureRecognizer`), support trackpad scrolling and pinching, and scroll with arrow keys when focused.
- [ ] **4.5 Programmatic viewport.** (design first) Add `scroll(to: Date)`, a readable visible date range, and a way to set how many candles are visible. Consider whether a `Binding`-based API fits better than imperative methods.
- [ ] **4.6 More series types.** Line and area (close price), OHLC bars, and Heikin-Ashi (the transform goes in Core, with tests).

Each feature ships with a demo example, docs, a CHANGELOG entry and tests where the logic is testable.

---

## Phase 5: 0.3, indicators and panes

- [ ] **5.1 More indicators in Core:** RSI, MACD, Bollinger Bands, VWAP. Test against published reference values, with the source cited in a comment.
- [ ] **5.2 Custom indicators.** (design first) A public protocol so apps can supply their own series. Decide whether `IndicatorKind` stays an enum of built-ins alongside it.
- [ ] **5.3 Indicator panes.** (design first) An API like `.indicator(.rsi(14), pane: .below(height: 90))`:
  - The panes share the horizontal viewport.
  - The crosshair spans all panes.
  - Each pane has its own vertical scale and labels.
  - Volume can move into its own pane.
  - Accessibility covers every pane.
- [ ] **5.4 Incremental indicator updates.** Only if the 1.5 baseline shows that recomputing indicators on data change is a measurable cost with live data. Otherwise mark as dropped, citing the numbers.

---

## Phase 6: 0.4, drawing tools

- [ ] **6.1 Design note** in `docs/design/drawing-tools.md`, agreed before any code. It covers:
  - A model owned by the app: `Codable`, anchored to (Date, price).
  - API shape, for example `.drawings($drawings)` plus a tool mode.
  - How drawing gestures coexist with pan and long-press.
  - Hit testing, selection handles, and snapping to open, high, low and close.
  - Deletion and undo.
  - VoiceOver access.
- [ ] **6.2 Horizontal line and trend line.**
- [ ] **6.3 Ray and rectangle.**
- [ ] **6.4 Fibonacci retracement** (optional).

**Exit criteria:** drawings survive history prepends and timeframe switches, and round-trip through `Codable`.

---

## Phase 7: More platforms

- [ ] **7.1 Mac Catalyst check:** does the iOS build work as-is?
- [ ] **7.2 Native macOS 14:** `NSViewRepresentable` gesture host, scroll wheel and trackpad magnify, crosshair on hover.
- [ ] **7.3 visionOS:** input model, and how the chart looks on glass.
- [ ] **7.4 Metal renderer**, behind the existing renderer seam, only if performance baselines require it.

## 1.0 criteria

- Public API unchanged across two minor releases.
- DocC complete.
- Snapshot and unit coverage for all public features.
- Accessibility audit done.
- Used in at least one shipping app.

---

## Known issues

| ID | Issue | Planned fix |
| --- | --- | --- |
| KI-1 | `onReachOldestCandle` fires once per data size. If the app's fetch fails, the count never changes, so the handler never fires again. | 1.2 |
| KI-2 | History is only requested after a pan or zoom. If the initial data doesn't fill the screen, older candles are never requested. | 1.2 |
| KI-3 | If history is prepended while the crosshair is showing, the crosshair points at a different candle. | 1.3 |
| KI-4 | The price axis has a fixed scaled width, so large prices or AX Dynamic Type sizes can truncate labels. | 1.4 |
| KI-5 | Time labels shift once when history is prepended, because label strides are anchored to indices. | 4.2 |
| KI-6 | Autoscale snaps rather than easing. | 4.1 |
| KI-7 | `CandlestickChart` creates a throwaway internal `CandleChartState` on every re-render, even when a state is passed in. Minor. | Opportunistic |
| KI-8 | `ChartHeader` recomputes `TimeScale.estimatedInterval` on every render. Minor. | Opportunistic |
| KI-9 | Demo: candles missed while the WebSocket is disconnected aren't backfilled. | Opportunistic (demo only) |
| KI-10 | Several framework API signatures were written without a compiler. See the 0.2 list. | 0.2, 0.3 |
| KI-11 | Vertical drags on the plot do nothing. This is intentional, for ScrollView embedding, but there is no vertical price scaling yet. | 4.3 |

## Open questions for the maintainer

1. **Platform priority:** does macOS or visionOS matter before indicator panes and drawing tools, or can Phase 7 stay last?
2. **Test dependency:** is swift-snapshot-testing acceptable as a test-only dependency (2.3)?
3. **Versioning:** strict SemVer from 0.1.0, or allow breaking changes in 0.x minor releases with CHANGELOG notes?
4. **Demo scope:** should the demo stay a showcase, or also serve as a manual test bench (debug overlays, redraw counters)?
5. **Naming:** keep `CandleKit`, pending the 3.4 check?

## Decision log

- **2026-09:** Canvas renderer over Swift Charts, index-based x-axis, UIKit gesture recognizers via `UIViewRepresentable` (iOS 17 minimum), Core and UI split into two targets. See CLAUDE.md for the reasoning.
- **2026-09:** Demo moved into this repository under `Demo/`, generated with XcodeGen. The `.xcodeproj` is not committed.
