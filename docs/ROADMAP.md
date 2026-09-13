# CandleKit roadmap

Last reviewed: 2026-09-12

This is the working plan for CandleKit and its demo. It's written to be executed one task at a time, mostly by Claude Code, with the maintainer verifying on device what can't be checked from the command line.

## How to use this document

- Work phases in order. A phase is done when its exit criteria are met. Tasks marked **(parallel-safe)** can be done early without blocking anything.
- Tasks marked **(design first)** start in plan mode. Write a short design note (in the PR description or `docs/design/`) and get the maintainer's agreement before implementing.
- Each task lists who verifies it. **CLI** means commands prove it. **Device** means the maintainer must check it on a simulator or phone.
- When you finish a task, tick its box, add a one-line note if something differed from the plan, and move any new problems you found into [Known issues](#known-issues).
- Don't silently expand scope. If a task turns out to need more than described, stop and report back.

Status key: `[ ]` not started · `[~]` in progress · `[x]` done · `[-]` dropped (with reason)

**On scope.** Phases 5–7 (indicators, drawing tools, configuration and persistence) are the bulk of
what makes a charting library feel complete, and together they're comfortably more work than
everything in Phases 0–4 combined — realistically a long stretch of sustained effort, not a couple
of weekends. Two things follow from that, and both are baked into how those phases are written:

1. **The extensibility API matters more than the catalog size.** A well-designed indicator protocol
   and drawing-tool model means the long tail can be contributed by other people, or added by an
   adopting app without waiting for a release. Forty built-in indicators and no extension point is a
   worse product than twelve and a good protocol — and it's the only version of this a small team
   can actually maintain.
2. **Tier 1 before Tier 2, always.** Each catalog below is split into the set that gets used
   constantly and the long tail. Finishing Tier 1 properly — correct, tested against published
   reference values, documented, fast — beats half-finishing both.

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
  - **Library (`CandleKit`)**: `CandleChartState` gains `appearPhase: Double` (0 = hidden, 1 = visible). When `makeFrame` sees `candles` transition from empty to non-empty, it sets `appearPhase = 0` and schedules `startAppearAnimation()` via `Task` to run after the current view update. A `CADisplayLink` at 60–120 Hz steps `appearPhase` from 0 → 1 over 0.4 s and bumps `revision` each frame. `cancelAnimation()` now also calls `stopAppearAnimation()`.
  - **`BaseLayerRenderer`**: When `appearPhase < 1.0`, switches from the normal batched-path `drawCandles` to `drawAnimatedCandles`, which draws each visible candle individually with a staggered per-position opacity. Leftmost candle fades in at phase 0, rightmost at phase 0.7, each candle taking 30 % of the phase window to fully appear. Volume bars, indicators and the last-price line fade in uniformly at `appearPhase`. Normal batched rendering resumes at `appearPhase == 1.0`.
  - **Demo (`MarketView`)**: `chart` restructured from `switch` to `if/else` with `.transition(.opacity)` on each branch and `.animation(.easeInOut(duration: 0.35), value: feed.candles.isEmpty)` for crossfading. `SkeletonChartView` (static shimmer placeholder) shown while no candles exist; when real data arrives, skeleton fades out as real candles draw in left-to-right.
  *Verify: CLI build + 36/36 tests. Device: change timeframe → skeleton shows → real candles appear left-to-right over ~0.4 s; switch product → same. Check light and dark mode.*
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
  - Record device, OS, dataset size, hitch rate and time per frame in `docs/PERFORMANCE.md`. These numbers decide whether 5.8 (incremental indicators) and a Metal renderer are ever needed.

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

## Phase 5: 0.3, indicators

**Build the system before the catalog.** `IndicatorKind` is currently an enum with two cases and a
`values(for:) -> [Double?]` method — one line per candle. That signature cannot express Bollinger
Bands (three lines plus a fill), MACD (two lines plus a histogram), Ichimoku (five lines plus a
shaded cloud), or Parabolic SAR (discrete dots). Adding indicators before fixing it means either
rewriting each one later or bolting on special cases per indicator. Do 5.1 and 5.2 first.

### Architecture

- [x] **5.1 Indicator protocol and output model.** *(landed — `Sources/CandleKitCore/Indicators/`. Untested on a compiler; run `swift test` first.)* Replace the closed enum with a
      protocol apps can also conform to (this supersedes the old "custom indicators" item — it's
      the same work, and doing it first costs nothing extra while doing it later costs a migration).
      The output model needs to cover, at minimum:
      - a single line (SMA, EMA)
      - multiple related lines (Bollinger, Keltner, Donchian, Ichimoku)
      - a filled band or cloud between two lines
      - a histogram, with positive/negative colouring (MACD, volume delta)
      - discrete point markers (Parabolic SAR)
      - horizontal reference levels (RSI's 30/70, MACD's zero line)

      Also decide: where does each indicator declare it belongs on the price pane vs. its own pane,
      how are its parameters typed (so a settings UI can be generated), and does it carry its own
      default styling?
- [ ] **5.2 Renderer primitives for the above.** The `Canvas` renderer currently draws polylines
      only. Band fills, histograms, point markers and stepped lines are new draw paths; each is
      batched like the candles are (one path per colour, never per data point) and each needs a
      pixel-snapping story so it stays crisp.
- [x] **5.3 Indicator panes.** *(landed — needs an iOS build and a device check.)*
      - Panes share the horizontal viewport. ✅
      - The crosshair spans all panes; the horizontal line and value tag follow whichever pane the
        finger is in. ✅
      - Each pane has its own vertical scale, labels and reference levels. ✅
      - Gestures cover every pane, so a drag starting on an RSI pane still pans the chart. ✅
      - Indicator panes are capped at 60% of the content height, so adding four doesn't squeeze the
        candles into a sliver. ✅
      - **Still open:** panes are not yet resizable by dragging the divider, nor collapsible; volume
        cannot yet move into its own pane; every separate-pane indicator gets its own pane rather
        than being mergeable into a shared one; accessibility does not yet describe pane contents.
        Tracked as 5.11 below.
- [ ] **5.12 Glass price axis and crosshair spotlight — needs a device look.** Fifth revision, now
      addressing the axis's colour rather than its shape.
      - **The panel now blends toward the system background colour** rather than showing
        `Material`'s own neutral tint outright — `Color(uiColor: .systemBackground)` overlaid at
        low opacity, which resolves correctly in both light and dark automatically — plus an
        overall opacity reduction for more translucency than any single `Material` level offers on
        its own. Directly from feedback that the axis's colour was standing out against its
        surroundings rather than blending in.
      - Feather fractions widened slightly (leading 15%→20%, top/bottom 8%→12% each) for a smoother
        dissolve.
      - `glassEffect` remains reverted (see the previous entry); still a plain `Material`-based
        panel, not real Liquid Glass.
      - The crosshair glow is stroked, not filled (see the entry above this one for why).
      - **On iOS 26+, the price axis uses the real `glassEffect()` API** (genuine Liquid Glass —
        specular highlights, not just blur), clipped to a shape rounded only on the leading edge
        (the one edge that's an actual boundary; the others are flush with the screen/pane edges).
        iOS 17–25 falls back to the same edge-rounded shape filled with the chosen `Material`, plus
        a faint edge highlight for definition.
      - **The crosshair now dims the rest of the chart** (`CandleChartStyle.crosshairDimOpacity`,
        default `0.35`, `0` disables it) while glowing the focused candle, so the highlight actually
        draws the eye. The dim's "hole" reuses the glow's own shape and blur radius, so the two
        read as one effect rather than mismatched rings.

      Both remain pure rendering/style changes with no effect on data, gestures, or layout math
      beyond the axis's own bounds. Before relying on it:
      - Confirm the axis now actually reads as part of the background rather than a distinct box —
        this round's specific target, and the thing to check first.
      - Confirm the extra translucency (0.7 overall opacity on top of the background blend) hasn't
        made the panel so faint it no longer helps tick-label legibility, which was the entire
        reason a backing existed in the first place — this is the one place "more translucent" and
        "still functions as a legibility backdrop" are in real tension, and it's not obvious in
        advance which value wins that trade-off.
      - Confirm the dim-with-a-hole reads as a spotlight and not as a distracting hard edge, and
        that indicator panes dimming without their own point-highlight doesn't look like a bug
        (it's deliberate — see the doc comment on `crosshairDimOpacity` — but "deliberate" and
        "looks right" aren't the same thing until someone's seen it).
      - Both effects use `GraphicsContext.Filter.blur(radius:)` only, deliberately avoiding
        `.shadow(...)`'s multi-parameter signature, which hasn't been confirmed. If `.blur` itself
        turns out wrong, the fallback is a solid, unblurred additive outline and a hard-edged dim
        cutout — less soft, but avoids gambling on unconfirmed Canvas filter APIs.
      - Confirm the new stroke-based glow is actually visible at typical zoom levels — a candle
        only a few points wide leaves little room for a stroked outline before it starts looking
        like a slightly thicker candle rather than a distinct glow.
- [ ] **5.11 Pane interaction and accessibility.** Drag the divider to resize a pane, collapse and
      expand, move volume into its own pane, merge two indicators into one pane, and extend VoiceOver
      so each pane's values are readable at the crosshair rather than only the price.

### Catalog

Two tiers, and the split is deliberate. **Tier 1 is the set that actually gets used.** Most traders
use a handful of indicators, and shipping those twelve extremely well — correct, tested, fast,
documented — beats shipping forty of uncertain quality. Tier 2 exists so the long tail has a home,
and most of it is good "good first issue" community-contribution material once 5.1 lands.

- [~] **5.4 Tier 1 — overlays:** SMA, EMA, WMA (as one configurable `MovingAverageIndicator`),
      Bollinger Bands, and session-anchored VWAP have landed. Still to do: a session/period
      high-low band.
- [x] **5.5 Tier 1 — oscillators:** RSI, MACD, Stochastic, ATR, OBV have landed as `Indicator`
      conformances over `IndicatorMath`. **Caveat:** see the note in `IndicatorMathTests.swift` —
      the expectations are cross-checks against an independent implementation, *not* transcriptions
      from a published table. Validating against an authoritative source is 5.9 below.
- [ ] **5.6 Tier 2 — overlays:** Ichimoku Cloud, SuperTrend, Parabolic SAR, Keltner Channels,
      Donchian Channels, Pivot Points (classic/Fibonacci/Camarilla).
- [ ] **5.7 Tier 2 — oscillators:** ADX/DMI, CCI, MFI, Williams %R, ROC/Momentum, Chaikin Money
      Flow, Volume Profile (this last one is substantially harder than the rest — it's a horizontal
      histogram binned by price, not a per-candle series, and may not fit the 5.1 output model
      without an extra case; decide during 5.1 whether to accommodate it or defer it).

**Every indicator in both tiers must document which convention it implements, and test against
published reference values with the source cited in a comment.** This matters more than it sounds:
indicator definitions genuinely differ between platforms. RSI can use Wilder's smoothing or a simple
average; MACD's signal line differs by how it's seeded; Stochastic's %D smoothing period varies;
ATR has at least three common smoothing variants. A chart that silently disagrees with the numbers a
user sees on TradingView will be reported as a bug, and "which one is right" is not a question you
want to answer after the fact. Pick the most widely used convention, say so in the doc comment, and
where a second convention is common, expose it as a parameter.

- [ ] **5.8 Incremental indicator updates.** (was 5.4) Only if the 1.5 baseline shows recomputation
      on data change is a measurable cost with live data. Otherwise mark as dropped, citing the
      numbers.
- [ ] **5.9 Validate indicator values against an authoritative source.** Every Tier 1 indicator's
      numbers checked against a primary reference — Wilder's *New Concepts in Technical Trading
      Systems* for RSI/ATR, or a live TradingView chart on the same data — and the convention
      confirmed in each doc comment. **This is not optional polish.** An attempt to validate RSI
      against a widely reproduced worked example during 5.5 came out consistently ~0.07 off, and no
      seeding or rounding variant explained the gap; the recalled table was most likely wrong, but
      that couldn't be established without the primary source. Until this task is done, CandleKit's
      indicator values are internally consistent and match the documented formulas, but are *not*
      confirmed to match what a user sees on another platform.
- [x] **5.10 Migrate the rendering layer onto the new model.** *(landed — needs an iOS build and a
      device check.)* `ChartIndicator` now wraps any `Indicator`; `IndicatorCache` is keyed by
      descriptor so re-parameterising one indicator doesn't invalidate the rest; `ChartFrame`
      carries colour-resolved results; the renderer draws lines, stepped lines, histograms, points,
      fills and reference levels. `IndicatorKind` and `MovingAverage` are deprecated shims
      delegating to `IndicatorMath`, so existing call sites still compile.
      **Known gap:** indicators that request `.separate` panes (RSI, MACD, Stochastic, ATR, OBV) are
      computed but not drawn — the renderer skips anything not on the price pane, because drawing
      0–100 RSI values against a price scale would be worse than drawing nothing. 5.3 closes this,
      and should be the next task.

---

## Phase 6: 0.4, drawing tools

Same principle as Phase 5: the interaction model and the persistence model are the hard parts, and
every tool afterwards is comparatively mechanical. Get them right once.

### Architecture

- [ ] **6.1 Design note** in `docs/design/drawing-tools.md`, agreed before any code:
      - A model owned by the app: `Codable`, anchored to `(Date, price)` pairs — never indices,
        which shift when history is prepended.
      - API shape, for example `.drawings($drawings)` plus a current-tool binding.
      - How drawing gestures coexist with pan, pinch and long-press. This is the crux: entering a
        drawing mode has to change what a drag means without making the chart feel modal or trapped.
      - Hit testing with a touch-sized tolerance, selection, and drag handles per anchor.
      - Z-order, duplicate, lock, and per-drawing visibility.
      - Deletion, and undo/redo (probably `UndoManager`).
      - VoiceOver: drawings must be reachable, described, and adjustable, not just visual.
- [ ] **6.2 Magnet / snapping.** Snap anchors to nearby open/high/low/close values, with a
      configurable strength and an off switch. Cheap to add during 6.1's interaction work, very
      annoying to retrofit afterwards.

### Catalog

- [ ] **6.3 Tier 1:** horizontal line, horizontal ray, vertical line, trend line, ray, rectangle,
      Fibonacci retracement, text note, and a measure tool (drag to read price Δ, % Δ, bar count and
      elapsed time). These cover the overwhelming majority of real chart annotation.
- [ ] **6.4 Tier 2:** parallel channel, ellipse, triangle, Fibonacci extension / fan / time zones,
      Andrews' pitchfork, long and short position tools (entry/target/stop with risk-reward
      readout), arrow, and callout.

**Exit criteria:** drawings survive history prepends and timeframe switches, round-trip through
`Codable` without loss, and are fully operable under VoiceOver.

---

## Phase 7: Configuration, persistence and comparison

The three things that make CandleKit adoptable by a team with an existing app, rather than only by
someone starting fresh. Promoted ahead of platform expansion because they're worth more to more
developers.

### Configuration — everything opt-in

- [ ] **7.1 `ChartConfiguration` and feature gating.** (design first) Every capability the chart has
      should be something a developer can turn off: crosshair, pan, zoom, price-axis drag, drawing
      tools, indicator panes, replay, haptics, the header. A trading app wants all of it; a portfolio
      summary screen wants a static sparkline with none of it; a widget can't use any of it. Today
      the modifiers are ad-hoc (`volumeVisible`, `headerVisible`) — this replaces that with something
      coherent before the surface grows further.

      Worth deciding here: **does the chart also ship default UI for these?** An indicator picker, a
      drawing toolbar, and a settings sheet are a large amount of what makes a charting SDK feel
      complete — and a large amount of opinion to force on an app with its own design system. The
      recommendation is a **separate `CandleKitUI` product** with ready-made, themeable components
      that an app can adopt, ignore, or copy as a starting point, so the core stays headless.
- [ ] **7.2 Per-capability availability lists.** Which indicators and which drawing tools a given
      app exposes, so `CandleKitUI`'s pickers and an app's own UI can both be driven from one source
      of truth instead of hard-coding a list in two places.

### Persistence

- [ ] **7.3 `ChartLayout: Codable`.** (was 10.1) One versioned, `Codable` value capturing the style,
      the active indicators and their parameters, drawings, timeframe, pane sizes and viewport. Needs
      a schema version and a migration path from day one — layouts are user data, and a user who
      loses their annotations on app update will not be forgiving about it.
- [ ] **7.4 Persistence, as an optional companion — not in the core.** You asked about Core Data or
      SwiftData. **Recommendation: CandleKit's core should stay persistence-agnostic and ship
      `ChartLayout: Codable` (7.3) as the contract, with a separate optional
      `CandleKitPersistence` product providing SwiftData `@Model` wrappers for apps that want them.**

      The reasoning, since this is a decision worth disagreeing with explicitly if you see it
      differently:
      - Most apps adopting CandleKit already have a persistence stack. A library that brings its own
        `ModelContainer` forces a second one, complicates CloudKit configuration, and creates
        migration coupling between the app's schema version and the library's.
      - A `Codable` value can be stored in SwiftData, Core Data, a file, `UserDefaults`, Keychain,
        or a server — the app picks. A SwiftData model can only be stored in SwiftData.
      - Library-owned Core Data / SwiftData schemas are genuinely painful to version across releases,
        and would make every future indicator or drawing tool a potential migration event.
      - The SwiftData convenience layer is small — a few model types wrapping the `Codable` value —
        so offering it as an optional product costs little and locks in nothing.

      If a concrete requirement shows this is wrong (say, layouts need to be queryable by predicate
      rather than loaded whole), revisit it — but start with `Codable`.
- [ ] **7.5 Named layout presets.** Save, name, list and switch between layouts; a default layout per
      symbol or per timeframe. Mostly falls out of 7.3 once it exists.

### Comparison

- [ ] **7.6 Multi-symbol comparison.** (design first — was 9.2) Plot two or more series together:
      - Normalization modes: percent change from the first visible candle, indexed to 100, or a real
        secondary price axis.
      - Per-series colour and line style, with a legend.
      - The crosshair reads out every series at the hovered candle.
      - Handling series with differing candle counts or trading calendars — the hard part, and the
        reason this needs a design note. An index-based x-axis assumes one series defines the
        positions; a second symbol that doesn't trade on the same days has to be aligned by
        timestamp, with gaps handled explicitly.

      Decide during the design note whether this is a mode of `CandlestickChart` or a separate public
      view sharing `CandleKitCore`'s scale math.

---

## 1.0 criteria

- Public API unchanged across two minor releases.
- DocC complete.
- Snapshot and unit coverage for all public features.
- Accessibility audit done.
- Used in at least one shipping app.

---

## Beyond 1.0: competing with TradingView and SciChart

Phases 0–7 get CandleKit to a *correct, tested, shipping* candlestick chart. That has to happen
first — a beautiful feature nobody can rely on doesn't out-compete anything. Everything below is
what makes CandleKit worth choosing over the alternatives once it's there, and it assumes 1.0 is
done. Don't let any of this pull focus from Phase 0–3 while the project hasn't even built yet.

### The actual competition, and where the real edge is

Two products a developer evaluating CandleKit would also look at, and what's actually true of them
(checked, not assumed — TradingView's own docs and SciChart's own pricing pages, current as of this
writing):

- **TradingView Advanced Charts** is free to use, but it's a **client-side JavaScript library**,
  full stop. On iOS that means a `WKWebView`: no true native gestures or haptics without a JS
  bridge, WebView startup latency, VoiceOver support that's a second-class citizen behind a browser
  engine, higher memory overhead per instance, and it structurally **cannot run** in a widget, a
  Live Activity, on watchOS, or in most of visionOS — those environments don't host a full web
  runtime. Free use also requires the implementation to be public and TradingView-attributed;
  private or paywalled use needs a separate, negotiated agreement. You also host the library
  yourself and wire up your own datafeed — "free" doesn't mean "zero integration work."
- **SciChart iOS** is genuinely native (Metal-backed, serious performance engineering) and a fair
  fight on raw capability. It's also a real ongoing cost: SciChart's own pricing page quotes
  iOS/Android licensing on a **per-developer, per-year** basis (their public historical pricing put
  a single iOS+Android license in the several-hundred-to-low-thousands-of-dollars range annually,
  with enterprise-scale deployments needing a separate "Advanced" tier), and the unlicensed trial
  build **displays a "Powered by SciChart" watermark**.
- **CandleKit's edge isn't "more indicators than SciChart"** — that's a feature race a two-person
  open-source project won't win outright, and doesn't need to. The edge is being **fully native
  SwiftUI *and* interoperable with UIKit, MIT-licensed with no royalty or attribution obligation,
  and able to reach every Apple surface a WebView-based competitor cannot reach at all.** Most of
  Phase 8 below is specifically the list of things that are true *because* of that, not things
  every charting library eventually gets around to.

### What CandleKit deliberately will not become

Saying no to some of this matters as much as building the rest. Feature creep is exactly how a
focused, fast, well-tested candlestick chart turns into an unmaintainable everything-library that
nobody can be confident works.

- **No order book / depth chart / footprint chart.** Real, but a genuinely different rendering and
  data-modeling problem from OHLCV candles. If this gets built at all, it should be a companion
  package that depends on `CandleKitCore`, not a module inside CandleKit itself.
- **No bundled data feeds, brokers, or backend.** CandleKit draws candles it's given. The Demo's
  Coinbase integration is a *demonstration* of how to feed it, not a feature of the library, and
  should never become one — the moment CandleKit ships an opinion about where data comes from, it
  stops being a drop-in chart for an app with its own backend.
- **No built-in alerting system, notification scheduling, or backend-synced watchlists.** 9.3 below
  gives apps the *primitive* (a price crossed a level) and stops there. Firing a notification,
  persisting a list of alerts, and syncing them are all app concerns.
- **Server-driven / remote-config styling.** A plausible enterprise ask, but out of scope for an
  open-source chart library's core; a fine candidate for a community package layered on top of the
  existing `CandleChartStyle`.

### Phase 8: Signature features — what a WebView chart can't do

This is the phase that actually answers "why CandleKit over TradingView." Each of these is either
impossible or seriously degraded in a `WKWebView`-hosted chart, and cheap for a SwiftUI-native chart
because the platform already does most of the work.

- [ ] **8.1 Home screen widget.** (design first) A small `WidgetKit` target rendering a
      `CandlestickChart` (or a purpose-built lightweight variant — a widget's render budget is not
      the same as a full-screen chart's) at small/medium/large sizes. The host app supplies the
      candle data via `TimelineProvider`; CandleKit's job is making the chart itself render cleanly
      at widget scale (no crosshair, no gestures, careful with the medium-size aspect ratio).
- [ ] **8.2 Live Activity / Dynamic Island.** A ticking price plus a tiny sparkline for a watched
      symbol during market hours, or for the duration of a simulated "open position." Needs a
      genuinely minimal rendering path — a Live Activity's update budget and process lifetime are
      far more constrained than an app's — so this likely wants its own tiny sparkline renderer in
      Core rather than reusing the full `CandlestickChart`.
- [ ] **8.3 watchOS companion view.** A compact price chart and a complication showing the latest
      close. `CandleKitCore` already has zero UIKit/SwiftUI-desktop dependencies, so the data and
      scale math needs no changes — this is really "does a slimmed-down rendering layer exist for
      watchOS," which is closer to 8.2's sparkline renderer than to the full iOS chart.
- [ ] **8.4 App Intents / Siri / Spotlight.** Expose an `AppIntent` a host app can adopt for
      "show me \<symbol\>'s chart," so it's reachable from Siri, Shortcuts, and Spotlight. This is
      mostly a documented integration pattern for host apps rather than new CandleKit surface —
      write the guide, provide a starter `AppIntent` conformance as sample code in the Demo.
- [ ] **8.5 Share chart as image.** Render the current visible chart (with a small CandleKit or
      app-supplied watermark) as a `UIImage`/`ImageRenderer` output for sharing to Messages or
      saving to Photos — the feature that makes Robinhood/Coinbase/Webull screenshots spread on
      social media. SwiftUI's `ImageRenderer` makes this close to free for a native view; it's not
      available to a WebView chart without a manual screenshot dance.
- [ ] **8.6 visionOS depth.** (design first, extends Phase 11.3) Beyond "does it render on glass":
      does a floating chart benefit from real depth — candles with subtle z-extrusion, or multiple
      symbols arranged in space for comparison? Needs hands-on time with a device or simulator
      before committing to anything beyond a flat chart in a window.

Ship each as a **separate SPM product** (`CandleKitWidgets`, `CandleKitWatch`, …) that depends on
`CandleKitCore` and, where relevant, `CandleKit`, rather than folding widget/watch code into the
main `CandleKit` target behind more `#if os(...)` branches. An app that only wants the iOS chart
shouldn't compile watchOS rendering code it never links against, and a widget extension has a much
tighter binary-size budget than a full app target.

### Phase 9: Rounding out feature parity

Real gaps against professional charting tools that aren't already covered by Phases 4–7. Unlike
Phase 8, none of these need a platform a WebView can't reach — they're just missing today.

- [ ] **9.1 Extended-hours / session shading.** Tint the plot background for pre-market and
      after-hours ranges (a very common ask for US equities apps). Needs a way to describe a
      symbol's trading sessions — probably a simple `TradingSession` value the app supplies, since
      CandleKit has no concept of "what market is this" — and a background-fill pass in the
      renderer keyed off it.
- [ ] **9.2 Event markers.** Small tappable annotations on the time axis for earnings, dividends,
      or news — an app-supplied array of `(Date, label, kind)`, rendered as a marker glyph with a
      popover or callback on tap. Straightforward once indicator panes (5.3) establish a pattern
      for a second, app-driven data layer over the price series.
- [ ] **9.3 Price-crossing primitive.** Not an alerting system (see "What CandleKit will not
      become") — just `CandleChartState` (or a small standalone type in Core) exposing "the price
      crossed level X between the last two candles," so an app can wire its own notification to it.
      Small, testable, and the thing every "build price alerts" tutorial ends up hand-rolling badly.
- [ ] **9.4 Replay mode.** Step or auto-play through a loaded series candle-by-candle at an
      adjustable speed — genuinely popular for backtesting and teaching technical analysis, and
      cheap to build: it's a `Viewport` that advances on a timer rather than a finger, reusing the
      exact eased-scroll machinery 4.1 and the spring animations already build. `CandleChartState`
      gains a `play(candlesPerSecond:)` / `pause()` pair; the renderer doesn't change at all.

### Phase 10: Developer experience and ecosystem

The competitive lever proprietary SDKs consistently under-invest in. A developer chooses a library
partly on "how fast can I get this working and keep it working," not only on feature count.

- [ ] **10.1 Testing support module.** A small `CandleKitTestSupport` product bundling
      `CandleSampleData` (already exists, just needs its own product target) plus SwiftUI preview
      helpers and a couple of `swift-testing` snapshot-style assertions, so an app team adopting
      CandleKit can write tests for *their* integration on day one instead of inventing fixtures.
- [ ] **10.2 Asset-class-aware formatting.** `PriceScale.suggestedFractionDigits` already adapts to
      magnitude; extend it to an explicit `AssetKind` (equity, forex, crypto) an app can set, since
      "8 decimal places for a satoshi-denominated price" and "pip-based forex formatting" are real,
      distinct conventions that magnitude alone doesn't fully capture.
- [ ] **10.3 Localization pass.** Audit every user-facing string (accessibility labels, the "Vol"
      label in `ChartHeader`, VoiceOver summaries) into a String Catalog, and confirm the layout
      holds up under RTL locales — a real requirement for any finance app with an Arabic or Hebrew
      market, and one a from-scratch charting implementation frequently gets wrong on day one.

---

## Phase 11: More platforms

- [ ] **11.1 Mac Catalyst check:** does the iOS build work as-is?
- [ ] **11.2 Native macOS 14:** `NSViewRepresentable` gesture host, scroll wheel and trackpad magnify, crosshair on hover.
- [ ] **11.3 visionOS:** input model, and how the chart looks on glass.
- [ ] **11.4 Metal renderer**, behind the existing renderer seam, only if performance baselines require it.

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
| KI-7 | ~~`CandlestickChart` creates a throwaway internal `CandleChartState` on every re-render.~~ **Correction:** this doesn't happen — `@State`'s initializer runs once per view identity, not per render, so `internalState` is only ever wastefully allocated once (per chart instance) when `state:` is always provided, not repeatedly. Downgraded; not worth fixing. | Won't fix |
| ~~KI-8~~ | ~~`ChartHeader` recomputed `TimeScale.estimatedInterval` on every render.~~ Fixed — see CHANGELOG "Unreleased". | Done |
| KI-9 | Demo: candles missed while the WebSocket is disconnected aren't backfilled. | Opportunistic (demo only) |
| KI-10 | Several framework API signatures were written without a compiler. See the 0.2 list. | 0.2, 0.3 |
| KI-11 | Vertical drags on the plot do nothing. This is intentional, for ScrollView embedding, but there is no vertical price scaling yet. | 4.3 |
| KI-12 | Two independent, hand-written critically-damped spring integrators exist: `CandleChartState`'s (reset zoom / scroll-to-latest, stiffness 180 / damping 27) and `ChartGestureCoordinator`'s (rubber-band release and the momentum edge-bounce, stiffness 300 / damping 35). The different constants may be intentional — a snap-back arguably should feel snappier than a deliberate reset — but the duplicated integrator code risks drifting inconsistently if one is retuned without the other. | Extract a shared spring-integrator type into Core (Double-only, testable) when 4.1 (eased autoscale) is tackled, since that needs the same kind of easing. |
| KI-13 | `CandleChartState` retains its own full copy of the candle array between renders, purely for `count` bookkeeping and crosshair random access. An app that mutates the last candle in place for a hot live-tick path (the pattern this README itself recommends) will force at least one full-array copy-on-write per tick, because CandleKit's retained reference and the app's own array reference are no longer uniquely held at the moment of mutation. Negligible for series in the hundreds to low thousands of candles (the demo's scale); worth revisiting for very large series (tens of thousands of candles) updated many times per second — the CPU cost of the copy itself is small, but the repeated allocation of a large buffer many times per second could contribute to hitches on constrained devices. | Investigate as part of 5.8, if the 1.5 performance baseline shows it matters. Likely fix: stop invoking the crosshair-change callback from inside `CandleChartState` (which needs the full array) and instead fire it reactively from `CrosshairLayer`, which already receives `frame.candles` per render — then `CandleChartState` itself would only need to retain a candle *count*. |
| KI-14 | On first load, `MarketView`'s outer 0.15s opacity crossfade (skeleton → chart) and `CandlestickChart`'s own ~0.5s per-candle reveal sweep run concurrently but aren't coordinated: the container is fully opaque well before the candles finish sweeping in. Not wrong, just slightly uncoordinated. | Opportunistic — either have the outer transition wait for `appearPhase` to settle, or drop one of the two animations. |
| KI-15 | `DisplayLinkProxy` (added in the Unreleased changes — see CHANGELOG) and its call sites haven't been checked against Swift 6's strict concurrency checker. The pattern mirrors `PerformanceView.DisplayLinkTarget` in the demo, but the generic, cross-type closures in `CandleChartState`/`ChartGestureCoordinator` may need explicit isolation annotations that can't be confirmed without compiling. | 0.2 (fold into the general "make the UI layer compile" pass) |

## Open questions for the maintainer

1. **Platform priority:** does macOS or visionOS matter before indicator panes and drawing tools, or can Phase 11 stay last?
2. **Test dependency:** is swift-snapshot-testing acceptable as a test-only dependency (2.3)?
3. **Versioning:** strict SemVer from 0.1.0, or allow breaking changes in 0.x minor releases with CHANGELOG notes?
4. **Demo scope:** should the demo stay a showcase, or also serve as a manual test bench (debug overlays, redraw counters)?
5. **Naming:** keep `CandleKit`, pending the 3.4 check?
6. **Phase 8 sequencing:** widgets/watch/Live Activities (8.1–8.3) are the strongest "native beats WebView" argument but also the most work for the least certain payoff — is there a specific app (yours, or an early adopter's) that would actually ship one of these, or is this speculative until there's a concrete use case pulling it?
7. **Multi-package split:** Phase 8 recommends separate SPM products per platform surface (`CandleKitWidgets`, `CandleKitWatch`). Worth deciding the package layout convention before the first one ships, rather than after.
8. **7.6's design boundary:** should multi-symbol comparison be a mode of `CandlestickChart`, or a second public view type? Whichever way this goes shapes the public API, so it's worth deciding before 7.6 starts rather than during it.
9. **Persistence:** 7.4 argues for `Codable` in the core with SwiftData as an optional companion, rather than Core Data or SwiftData in the library itself. Worth confirming you agree before anything gets built against it.
10. **Indicator conventions:** when a Tier 1 indicator has more than one common definition (RSI smoothing, ATR smoothing, MACD signal seeding), is matching TradingView's numbers the priority, or matching the textbook definition? These occasionally differ, and users will compare against TradingView.

## Decision log

- **2026-09:** Canvas renderer over Swift Charts, index-based x-axis, UIKit gesture recognizers via `UIViewRepresentable` (iOS 17 minimum), Core and UI split into two targets. See CLAUDE.md for the reasoning.
- **2026-09:** Demo moved into this repository under `Demo/`, generated with XcodeGen. The `.xcodeproj` is not committed.
- **2026-09:** **CandleKit ships the indicator picker and drawing toolbar** (decided by the maintainer). They live in a separate `CandleKitUI` product so the core stays headless and an app with its own design system isn't forced to adopt them, but they are a supported, shipped part of the library rather than sample code. This is what makes the parameter model in `IndicatorParameter` load-bearing: the picker generates a settings form for any indicator, including app-defined ones, from its declared parameters.
- **2026-09:** Competitive positioning against TradingView Advanced Charts (free, but JavaScript/WebView-hosted on iOS, public-implementation licensing terms) and SciChart iOS (native, but paid per-developer-per-year with a watermarked trial). CandleKit's differentiation strategy is *not* out-featuring either on raw indicator/drawing-tool count — it's being free, MIT-licensed, SwiftUI-native, and able to reach widgets, Live Activities, watchOS and App Intents, none of which a WebView-based chart can do at all. Order books, bundled data feeds, and a built-in alerting system are explicitly out of scope for the core library — see "What CandleKit deliberately will not become."
