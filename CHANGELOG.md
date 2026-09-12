# Changelog

All notable changes to CandleKit are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Nothing has been tagged yet; entries
below describe what has landed on `main` since the initial commit.

## Unreleased

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
