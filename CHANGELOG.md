# Changelog

All notable changes to CandleKit are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Nothing has been tagged yet; entries
below describe what has landed on `main` since the initial commit.

## Unreleased

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
