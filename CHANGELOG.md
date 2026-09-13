# Changelog

All notable changes to CandleKit are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Nothing has been tagged yet; entries
below describe what has landed on `main` since the initial commit.

## Unreleased

### Added — glass price axis and crosshair glow

Two cosmetic changes, both opt-in or additive — nothing here changes default appearance for
existing adopters.

- **`CandleChartStyle.priceAxisMaterial: Material?`** (default `nil`, unchanged appearance). Setting
  it — `.ultraThinMaterial` is a reasonable start — gives the price axis a frosted backdrop, and lets
  candles extend slightly underneath it (see `ChartMetrics.priceAxisOverlap`, internal, set
  automatically only when a material is chosen) so they show through, blurred, as they scroll toward
  the edge. Deliberately built on the standard `Material` APIs (iOS 15+) rather than iOS 26's
  `glassEffect()`, so it works across CandleKit's full iOS 17+ support; on iOS 26 a `Material` still
  renders with the system's current glass materials, just without the newer API's specular
  highlights and morphing.
- **Price axis tick labels moved out of the Canvas into a real view** (`PriceAxisGlassPanel`, new,
  in `CandlestickChart.swift`). A `Material` only blurs content *behind* the view it's attached to —
  labels painted into the same `Canvas` as the candles would have blurred right along with them.
  This is the same reason `LastPriceBadge` had to become a real view rather than Canvas-drawn text.
  Labels render identically whether or not a material is set; only the background layer is
  conditional.
- **Crosshair glow.** Long-pressing now draws a soft additive highlight around the focused candle,
  in `CrosshairLayer`. Two blurred passes at different radii and opacities (a single blur reads as a
  smudge), blended with `.plusLighter` so it brightens the candle rather than dulling it with an
  overlay. Deliberately uses only `GraphicsContext.Filter.blur(radius:)` — a single, simple
  parameter — rather than `.shadow(...)`, whose multi-parameter signature hasn't been confirmed to
  compile; getting a Canvas filter signature wrong has cost a compile-error round trip before, and
  `.blur` is a much smaller surface to be wrong about.

### Fixed during this change

Caught and corrected before packaging, not after: the price axis panel was initially wired to only
appear when a material was set, which meant leaving `priceAxisMaterial` at its default `nil` would
have drawn **no price labels at all** — a real regression, not a stub. Fixed so the panel — and the
labels — render unconditionally; only its background rectangle is conditional on the style.

### Verification

None of this has been seen rendered. The layout math (`ChartLayout`'s new `priceAxisOverlap`) was
checked by hand — with overlap `0` it's provably identical to the previous non-overlapping formula,
since that's the value used whenever `priceAxisMaterial` is `nil`, which is every existing
integration. What can't be checked without a device: whether tick labels stay legible against
candles moving underneath the glass, and whether the glow looks like a glow rather than a smudge or
a blown-out blob. Both are exactly the kind of thing that's hard to get right on the first attempt
without seeing it — tune the two blur radii and opacities in `CrosshairLayer.drawFocusGlow` and the
`28`pt overlap constant in `CandlestickChart` freely once you can.

## Earlier unreleased work

### Added — indicator panes (Phase 5.3)

RSI, MACD, Stochastic, ATR and OBV now actually draw. They were computed and cached since the
previous change but skipped by the renderer, because plotting 0–100 values against a price scale
would have been worse than plotting nothing. This closes that gap.

- **Stacked panes below the candles**, one per separate-pane indicator, each autoscaled to its own
  values with its own grid, value axis and title.
- **The price pane keeps what's left**, and indicator panes are capped at 60% of the content height
  no matter how many are added or how tall each asks to be — otherwise four indicators squeeze the
  candles into a sliver, which is the one thing the user is actually looking at.
- **Reference levels widen a pane's range**, so RSI's 70 line can't scroll off screen when the
  values are all low. A pinned `preferredRange` (RSI's 0...100) stays exactly pinned rather than
  drifting outward by the padding fraction on every render.
- **The crosshair spans every pane** — the candle under your finger lines up with its RSI or MACD
  value below — while the horizontal line and value tag belong to whichever pane the finger is
  actually in.
- **Gestures now cover the whole content area**, so a drag starting on an indicator pane pans the
  chart instead of doing nothing.
- Each pane is clipped to itself, so an indicator briefly exceeding its autoscaled range can't bleed
  into the candles above.
- The indicator drawing routines are now parameterised on a value mapping rather than reaching for
  the price scale, which is what lets panes and price overlays share one implementation.
- New Core helper `PriceScale.autoRange(forSeries:in:required:paddingFraction:)`, with tests.
- Demo: RSI and MACD toggles under a new "Panes" section on the Market tab.

### Known gaps

Panes aren't resizable or collapsible yet, volume can't move into its own pane, every separate-pane
indicator gets its own pane rather than being mergeable, and VoiceOver still reads only the price
rather than each pane's value at the crosshair. Tracked as roadmap task **5.11**.

One cosmetic edge: if an indicator has no visible values at all (fully inside its warm-up period),
its pane is laid out but left empty rather than collapsed. It reclaims the space as soon as values
appear.

### Verification

The new Core helper is covered by tests you can run with `swift test`, including the pinned-range
and no-visible-values cases. Everything else — pane layout, the spanning crosshair, gesture
coverage — is uncompiled and needs an iOS build and a look on device.

## Earlier unreleased work

### Changed — rendering layer migrated onto the indicator engine (Phase 5.10)

The engine added in the previous entry is now what the chart actually draws.

- **`ChartIndicator` wraps any `Indicator`**, including app-defined ones, with optional colour and
  line-width overrides and an `isVisible` flag (so a settings UI can toggle an indicator without
  discarding its configuration). Convenience factories added for the whole Tier 1 set:
  `.bollingerBands()`, `.vwap()`, `.rsi()`, `.macd()`, `.stochastic()`, `.atr()`, `.obv()`,
  alongside the existing `.sma()` / `.ema()` / new `.wma()`.
- **`IndicatorCache` is keyed by descriptor**, so changing one indicator's period recomputes only
  that indicator instead of invalidating every overlay on the chart. Covered by new tests that
  assert the computation count directly — a cache that silently recomputes every frame is
  indistinguishable from a working one without them.
- **The renderer draws the full output model:** lines (with dash patterns), stepped lines,
  sign-coloured histograms, point markers, fills between plots, and horizontal reference levels.
  Histograms are batched into two paths by sign, following the same constant-draw-call rule as the
  candles.
- **Autoscale now accounts for indicator overlays.** A long moving average on a trending series
  routinely sits outside the visible highs and lows; previously it would be clipped.
- **`CandleChartStyle` gained `indicatorPalette`**, so consecutive overlays are visually distinct
  without the app picking colours.
- Only visible indicators are computed — hiding one stops paying for it.
- `IndicatorKind` and `MovingAverage` are deprecated but still work, and now delegate to
  `IndicatorMath` so there is one implementation rather than two that can drift. Existing
  `.indicators([.sma(20), .ema(50, color: .blue)])` call sites are unchanged.
- Demo: Bollinger Bands and VWAP toggles on the Market tab, which exercise the multi-plot and fill
  paths that a plain moving average never touches.

### Known gap

Indicators that request their own pane — RSI, MACD, Stochastic, ATR, OBV — are computed and cached
but **not drawn**. The renderer skips anything not on the price pane, because plotting 0–100 RSI
values against a price scale would be worse than plotting nothing. Roadmap task **5.3** (indicator
panes) closes this and is the next task; until then, adding `.rsi()` to a chart will correctly
produce no visible output rather than a wrong one.

### Verification

The Core half — the new cache, its eviction and per-descriptor recomputation — is covered by tests
you can run with `swift test`. The rendering half is uncompiled as usual: the plot styles, fill
geometry and colour resolution need an iOS build and a look on a device.

## Earlier unreleased work

### Added — indicator engine (Phase 5.1, 5.2, most of Tier 1)

The foundation the indicator picker, saved layouts and indicator panes all depend on. All pure
Foundation in `CandleKitCore`, so **this is the first work in a while you can actually verify
yourself: run `swift test`.**

- **`Indicator` protocol and output model** (`IndicatorOutput.swift`, `Indicator.swift`). The old
  `IndicatorKind.values(for:) -> [Double?]` returned one number per candle, which cannot express
  Bollinger's three lines and a fill, MACD's histogram, RSI's pinned 0–100 pane with reference
  levels, or SAR's discrete dots. The new model covers plots (line, stepped, histogram, points,
  hidden), fills between plots, reference levels, a preferred scale range, and pane placement.
  Colours are expressed as roles rather than `Color` values, so Core stays UI-framework-free and
  Linux-testable.
- **Typed parameters** (`IndicatorParameter.swift`) — the piece that makes a *generic* picker
  possible. An indicator declares its inputs with kinds and valid ranges, so the settings form can
  be generated for any indicator, including one an app defines itself, with no bespoke UI. Values
  clamp on assignment, so a picker binding can't put an indicator into a divide-by-zero state.
- **`IndicatorCatalog`** — immutable and `Sendable` (no global mutable registry, so no locking and
  no Swift 6 concurrency problem). Apps extend it with `adding(_:)`, and two charts in one app can
  offer different sets. Provides category grouping and search for the picker.
- **`IndicatorDescriptor`** — the `Codable` `identifier + [key: value]` pair a saved layout stores.
  Unknown parameter keys are ignored and out-of-range values clamped on load, so a layout written
  by a newer build, or a hand-edited one, degrades gracefully instead of failing.
- **`IndicatorMath`** with SMA, EMA, WMA, Wilder smoothing, rolling population standard deviation,
  RSI, MACD, Stochastic, true range, ATR, Bollinger Bands, OBV and session-anchored VWAP. Every
  function documents which convention it implements, and where two are common the choice is a
  parameter rather than a silent decision.
- **Tier 1 indicators** as `Indicator` conformances: `MovingAverageIndicator` (SMA/EMA/WMA),
  `BollingerBandsIndicator`, `VWAPIndicator`, `RSIIndicator`, `MACDIndicator`,
  `StochasticIndicator`, `ATRIndicator`, `OBVIndicator`.
- **Tests** covering the maths, the parameter clamping, catalog round-tripping through `Codable`,
  the app-defined-indicator extension point, and degenerate inputs (empty series, single candle,
  mismatched array lengths, zero periods).

### Verification, and one thing that isn't verified

The O(n) WMA recurrence was checked against a direct computation of the definition over 200 random
inputs before being written, and the same check ships as a test. The expected values in
`IndicatorMathTests.swift` come from an independent reference implementation written separately
from the Swift, so the two agreeing is genuine evidence rather than the Swift agreeing with itself.

**What is not established: that these numbers match what a user sees on TradingView.** Validating
RSI against a widely reproduced published worked example came out consistently ~0.07 off, and
neither an alternative seeding convention nor intermediate rounding explained the gap. The most
likely explanation is that the recalled table was inaccurate, but that cannot be confirmed without
the primary source. Rather than bake in numbers of uncertain provenance, the tests verify internal
consistency and the documented formulas, and roadmap task **5.9** now tracks validating against an
authoritative source as required work — not optional polish.

### Changed

- Nothing was removed. `IndicatorKind` and the existing rendering path still work exactly as before;
  the new engine was added alongside it. Reconciling the two is roadmap task **5.10**, and has to
  happen before panes or the picker can ship.

### Decided

- **CandleKit will ship the indicator picker and drawing toolbar**, in a separate `CandleKitUI`
  product so the core stays headless. Recorded in the roadmap's decision log; open question 9 is
  closed.

## Earlier unreleased work

### Added — indicators, drawing tools, configuration and persistence roadmap

Phases 5–7 substantially expanded and restructured around what developers adopting a charting
library actually need.

- **Phase 5 (indicators)** now leads with architecture, not catalog. `IndicatorKind`'s current
  `[Double?]`-per-candle output can't express Bollinger Bands, MACD's histogram, Ichimoku's cloud or
  Parabolic SAR's dots, so a protocol and a richer output model (multi-line, band fill, histogram,
  point markers, reference levels) must land before any new indicator, or each one becomes migration
  debt. Catalog split into Tier 1 (the twelve that actually get used) and Tier 2 (the long tail,
  mostly good community-contribution material). Custom indicators folded into the architecture work
  rather than bolted on afterwards.
- **Indicator conventions called out explicitly.** RSI smoothing, ATR smoothing, MACD signal seeding
  and Stochastic %D all differ between platforms. Every indicator must document which convention it
  implements and test against cited reference values — a chart that disagrees with TradingView's
  numbers gets reported as a bug.
- **Phase 6 (drawing tools)** restructured the same way: interaction model, `(Date, price)` anchoring,
  hit testing, undo, and magnet/snapping first; then Tier 1 (horizontal line, ray, trend line,
  rectangle, Fibonacci retracement, text, measure) and Tier 2.
- **New Phase 7 — configuration, persistence and comparison**, promoted ahead of platform expansion:
  - `ChartConfiguration` making every capability individually switchable, replacing the ad-hoc
    `volumeVisible` / `headerVisible` modifiers before the surface grows further.
  - An open question on whether CandleKit ships default UI (indicator picker, drawing toolbar) — the
    recommendation is a separate `CandleKitUI` product so the core stays headless.
  - `ChartLayout: Codable`, versioned with a migration path from day one.
  - **Persistence recommendation: keep Core Data and SwiftData out of the core library.** Ship
    `Codable` as the contract with an optional `CandleKitPersistence` companion providing SwiftData
    wrappers. Reasoning is written out in 7.4 — adopting apps already have a persistence stack, a
    library-owned schema creates migration coupling, and a `Codable` value can be stored anywhere
    while a SwiftData model cannot.
  - Multi-symbol comparison (moved from 9.2), expanded with normalization modes and the genuinely
    hard part: aligning series with different trading calendars under an index-based x-axis.
- **Scope note added to the preamble.** Phases 5–7 are more work than Phases 0–4 combined. The plan
  states plainly that the extensibility API matters more than catalog size, and that Tier 1 finished
  properly beats both tiers half-finished.
- Old Phase 7 (More platforms) renumbered to Phase 11; all cross-references updated.
- Four new open questions: whether CandleKit ships UI, confirmation of the persistence stance, the
  comparison-view API boundary, and whether matching TradingView's numbers or textbook definitions
  wins when indicator conventions conflict.

### Added — competitive roadmap

`docs/ROADMAP.md` gains three new phases (8, 9, 10) plus a positioning section, laying out what
would make CandleKit a better choice than TradingView's Advanced Charts or SciChart iOS rather than
just a free imitation of either:

- **Phase 8 — signature features:** things a `WKWebView`-hosted chart structurally cannot do on
  Apple platforms — a home screen widget, a Live Activity, a watchOS companion, App Intents/Siri
  integration, chart-as-image sharing, and deeper visionOS use of depth.
- **Phase 9 — feature-parity rounding:** real gaps against professional charting tools that Phases
  4–6 don't already cover — extended-hours shading, multi-symbol comparison overlays, event
  markers, a price-crossing primitive for alerts, and a replay/bar-by-bar playback mode.
- **Phase 10 — developer experience:** `Codable` chart-layout persistence, a testing-support
  module, asset-class-aware number formatting, and a localization/RTL pass — the axis proprietary
  SDKs consistently under-invest in.
- An explicit **"What CandleKit deliberately will not become"** list — order books, bundled data
  feeds/brokers, a built-in alerting backend, and remote-config styling are called out as
  out-of-scope for the core library, with a suggested path (companion packages) for whichever of
  them someone eventually wants.
- The competitive claims are grounded in each competitor's own current pricing/licensing pages
  rather than assumed, and cited in the roadmap.

All of this is explicitly sequenced *after* the 1.0 criteria, not folded into getting there —
nothing here should pull focus while the project hasn't built yet (Phase 0).

## Earlier unreleased work

### Fixed — CI build failure

`animatedResetZoom()` and `animatedScrollToLatest()` were declared with no access modifier
(`internal`, Swift's default) when added a few commits back for the double-tap-to-reset gesture,
which only ever called them from within the `CandleKit` module. A later change (this changelog's
own "Jump to latest" and "Reset zoom" entries) had the Demo call them directly from its own module,
which needs `public` — an oversight on my part, since I recommended that change without checking
the methods it was calling were actually exposed. Xcode Cloud caught it correctly:

```
error: 'animatedResetZoom' is inaccessible due to 'internal' protection level
error: 'animatedScrollToLatest' is inaccessible due to 'internal' protection level
```

Both are now `public`, with doc comments explaining when to prefer them over the instant
`resetZoom()` / `scrollToLatest()`. Audited every other CandleKit symbol the Demo references
against its declared access level — nothing else is affected.

## Earlier unreleased work

### Fixed — docs

- `docs/PERFORMANCE.md`: the `xctrace` example was wrong in two ways. `--output` was placed after
  `--launch --`, where everything is passed to the launched app, so it was silently ignored and
  traces landed under auto-generated names. And `--launch --` takes a path to the `.app` bundle, not
  a bundle identifier.
- Made it explicit that **Animation Hitches requires a physical device** — on the Simulator it fails
  with `Hitches is not supported on this platform`, because hitch measurement reads real display
  pipeline timing. Added a section on what the Simulator can and can't tell you (gross algorithmic
  problems yes; relative phase cost no, since CPU work runs on the Mac's cores while rendering takes
  a different path), an `--attach` recipe that's easier for interactive profiling, the Xcode GUI
  route as the recommended default, and a troubleshooting table.

## Earlier unreleased work

### Added — performance instrumentation

Scrolling and the appear animation are reported fixed. This adds the measurement infrastructure
that should have come first, so the next round of performance work starts from numbers.

- `ChartPerformance`: opt-in instrumentation naming twelve phases of the per-frame work
  (`makeFrame`, `makeFrame.priceRange`, `draw.candles`, `draw.axes`, `draw.crosshair`, …). Emits
  `OSSignposter` intervals for the Points of Interest track in Instruments, and collects timings
  that `ChartPerformance.report(scenario:)` renders as a markdown table with call counts and
  mean/p50/p95/max per phase.
- Off by default, costing one `Bool` check per phase. Enable with the `CANDLEKIT_PERF` environment
  variable — so a Release build can be profiled without recompiling — or `setEnabled(_:)`.
- Demo: a capture bar on the Performance tab (record → interact → stop → copy). Reports are tagged
  with the device model, OS version and candle count, and simulator runs are labelled as not
  representative. `UIDevice.name` is deliberately not used, since it's often the owner's real name
  and these reports get pasted into a public repo.
- `docs/PERFORMANCE.md` rewritten: phase reference, in-app capture recipe, Instruments recipe
  (including an `xctrace` invocation), how to read the numbers against a 120 Hz budget, the two
  known-remaining costs, and a trace log with a template. The log is empty — the first entry should
  be a baseline on current `main`.
- `CLAUDE.md`: performance changes now require a before/after trace entry in the same change.

## Earlier unreleased work

### Performance — second pass (scrolling, zooming, appear animation)

Follow-up after the first pass didn't resolve the reported lag. See `docs/PERFORMANCE.md` for the
ranked hypothesis list, what's still open, and — more importantly — the Instruments recipe. None of
the below is measured; that document explains why measuring is now the priority over further
blind fixes.

- **The whole chart re-rendered on every animation frame.** `CandlestickChart.body` read
  `state.revision` at the top, so each bump — one per frame during a pan, fling or pinch, up to 120
  a second — invalidated the entire body: the header (which reformats a row of prices), the
  accessibility summary, the `UIViewRepresentable` gesture host, and the ZStack layout. Almost none
  of that changes when the viewport moves. `revision` is now read only by a new private
  `ChartContentLayer`, the one view that genuinely must repaint per frame. This is the largest
  single change in this pass and the most likely explanation for lag that survived the first round.
- **Accessibility strings were built on every frame.** `ChartAccessibility.summary` formats two
  dates and two numbers; date formatting is among the most expensive operations in Foundation, and
  this ran on every frame of every scroll to produce a string only VoiceOver reads. It's now
  attached only when `accessibilityVoiceOverEnabled` is true — and when VoiceOver *is* running
  there's no 120 Hz flinging to protect, so it stays fully accurate.
- **Appear animation issued a draw call per candle.** `drawAnimatedCandles` copied the
  `GraphicsContext` and issued two or three fills for every visible candle, every frame — over a
  thousand draw calls per frame at wide zoom, which is exactly why the animation stuttered worst
  when the most candles were on screen. Candles are now grouped into 8 quantised opacity buckets
  and drawn as batched paths, capping it at a couple of dozen fills. The fade zone spans only a few
  candles, so the quantisation isn't visible.
- **Axis labels ran `FormatStyle` inside the draw closure.** Every price and time label was
  re-formatted on every frame. Label strings are now built once in `makeFrame`, cached against the
  ticks that produced them (so panning, where tick values usually don't change at all, skips the
  work entirely), and passed to the renderer pre-formatted. The renderer no longer calls
  `ChartFormat` at all.
- **The crosshair Canvas re-rasterised even when idle.** `CrosshairLayer` always created a `Canvas`
  whose draw closure returned immediately when no crosshair was showing — but the Canvas itself
  still re-rendered every frame. It now produces no view at all when idle, and reads `revision`
  only while a crosshair is actually up.

### Added

- `docs/PERFORMANCE.md`: ranked hypotheses, the two known-remaining costs with concrete options for
  each, and a step-by-step Instruments recipe.

## Earlier unreleased work

Fixes from a pass looking specifically for memory leaks, hangs, and scrolling/animation smoothness,
prompted by reports that panning and animations didn't feel smooth. See `docs/ROADMAP.md` for the
full list of what's still open, and the "Verification" note at the end of this entry for what has
and hasn't been checked on a device.

### Fixed

- **Memory leak: chart animations could keep a whole chart alive forever.** `CandleChartState`'s
  appear-in and spring-to-target animations used `CADisplayLink(target: self, ...)`.
  `CADisplayLink` retains its target for as long as it's on a run loop; nothing invalidated these
  two if the chart was removed from the view hierarchy mid-animation (a list row scrolling away, a
  sheet dismissed, a navigation pop, all while data had just loaded or a "reset zoom" was still
  settling). Both are now driven through a small weak-referencing proxy (`DisplayLinkProxy`, new
  file) that never keeps the chart alive, and `CandlestickChart` now also calls
  `state.stopAnimations()` (new public method) from `.onDisappear`, so the common case cleans up
  immediately rather than only being leak-safe. The gesture coordinator's own two display links
  (momentum, rubber-band release) got the same treatment for consistency, even though their
  cleanup via `dismantleUIView` was already sound.
- **Scrolling: flinging to the newest or oldest candle stopped dead instead of bouncing.** Every
  other place the chart touches the data edge gives some kind of soft-limit feedback — dragging
  past the edge rubber-bands, a pinch past the zoom limit gives a haptic tick — except a fling that
  reached the edge under its own momentum, which just stopped. Momentum now hands off to the same
  rubber-band spring used for a drag release the instant it crosses the boundary, so it bounces
  like the rest of the chart instead of reading as a glitch.
- **Scrolling: a slow, deliberate drag could get mistaken for a long-press.** The crosshair's
  `minimumPressDuration` had been lowered from `0.25` to `0.15` seconds, which is close enough to
  how long a finger dwells before an intentional slow drag satisfies `UIPanGestureRecognizer`'s own
  movement threshold that panning would occasionally lose the race and open the crosshair instead.
  Reverted to `0.25`.
- **Redundant work on every render.** `ChartHeader` recomputed `TimeScale.estimatedInterval` from
  scratch on every render — including every crosshair move and every live price tick — duplicating
  work `CandleChartState.makeFrame` had already done and cached for the same data. It now reads the
  cached value.
- Overzealous haptics and sound. A recent pass had added `AudioServicesPlaySystemSound` (undocumented
  system sound IDs, not public API) plus layered haptics to nearly every gesture: a pop on long-press
  start, a peek on release, a click on every pinch past the zoom limit, a peek on every momentum
  edge-hit. Reaching the edge during ordinary scrolling is common, so that last one in particular
  fired on a large fraction of everyday scrolls. All system sounds are removed, and haptics are
  pared back to three: one light tap when the crosshair engages, one rigid tap at a hard zoom limit,
  one medium tap on double-tap-to-reset. Per-candle crosshair ticks still come from
  `CrosshairLayer`'s existing `.sensoryFeedback(.selection)`, unchanged.

### Added — animated price ticker

- The last-price tag (the badge on the price axis showing the current close) and `ChartHeader`'s
  price, change and percent values now use `.contentTransition(.numericText())`: digits roll up or
  down instead of cross-fading, the standard "stock ticker" look, on every live tick.
- This required moving the last-price tag out of the Canvas into a real SwiftUI view
  (`LastPriceBadge`, new). `.contentTransition` is a view modifier with no Canvas equivalent —
  Canvas-drawn text is rasterised immediately and can't animate. `ChartHeader`'s prices were already
  real views, so those only needed the modifier added.
- **Scoped deliberately to the numbers people actually watch tick**, not every number the chart
  draws. Axis tick labels and the crosshair's price/time tags stay Canvas-drawn:
  - Tick labels are a poor fit for `numericText` regardless — the *set* of visible ticks changes
    identity as the price range autoscales or the user pans, which is an insertion/removal, not a
    value transition on a stable view.
  - The crosshair's tags already update at gesture-frame-rate as a finger drags; animating those
    would fight the drag rather than help it, and would reintroduce a per-frame real-view cost in
    exactly the place the previous two passes worked to remove it.
  - If axis tick labels ever move to real views, it'll most likely be to fix the "text drawing in
    Canvas" performance question (see `docs/PERFORMANCE.md`), not for this animation — worth doing
    together if a trace shows `draw.axes` is hot, since the same view-based fix would clear both.
- `LastPriceBadge` reads `state.revision`, unlike most of `CandlestickChart.swift` — its vertical
  position needs to track the price scale during a pan or pinch. That's a deliberately narrow,
  cheap subscription (repositioning one small view), not the whole-subtree cost the render-scope
  refactor in the previous pass exists to avoid.

## Earlier unreleased work


### Added

- Appear-in and reset/scroll-to-latest animations now check `UIAccessibility.isReduceMotionEnabled`
  and skip straight to the end state when it's on, matching the demo's own build of the same
  feature for the reveal sweep. Direct-manipulation motion (the rubber-band drag itself, ordinary
  momentum) isn't gated, matching how `UIScrollView` behaves.
- `CandleChartState.stopAnimations()`: stops any in-flight appear or spring animation without
  touching the current viewport. Called automatically by `CandlestickChart` on disappear; also
  useful directly if you manage chart state outside a `CandlestickChart`'s own lifecycle.

### Changed (demo)

- The "Jump to latest" button and the chart-options menu's "Reset zoom" now call
  `animatedScrollToLatest()` / `animatedResetZoom()` instead of the instant versions, so they match
  the feel of double-tap-to-reset instead of snapping.

### Verification

None of this has been compiled — this environment has no Swift toolchain (see `docs/ROADMAP.md`,
Phase 0). Everything above was checked by careful reading, not by running it: the numeric spring
and rubber-band logic was traced by hand for the cases that looked riskiest (a stale rubber-band
flag surviving into an unrelated gesture, a momentum hand-off with too little overscroll to bounce
visibly), and the concurrency pattern in `DisplayLinkProxy` mirrors one already in
`Demo/CandleKitDemo/Performance/PerformanceView.swift`. It has **not** been verified that any of
this actually compiles under Swift 6's strict concurrency checking, and none of it has been felt on
a device. Before relying on this: run the Phase 0 build steps, then work through
`docs/QA.md`'s momentum/rubber-band/crosshair/Reduce-Motion items specifically, since those are
exactly what changed here.
