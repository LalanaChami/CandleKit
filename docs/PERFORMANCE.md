# Performance

## Read this first

Three rounds of performance work have now shipped without a single measurement, because the
environment they were written in has no Swift toolchain and no device. Each round fixed something
real, and each round guessed at the ranking. That's a bad way to fix a frame-rate problem: the
usual outcome is that four true-but-minor costs get fixed while the one that actually dominates is
never touched.

**The highest-value next step is a ten-minute Instruments trace, not another round of guesses.**
The recipe is below. With a hot-spot list from a real device, the remaining work becomes precise.

## Getting a trace

1. Build the **Demo** app in **Release** (Product → Scheme → Edit Scheme → Run → Build
   Configuration → Release). Debug builds have unoptimised Swift and misleading SwiftUI overhead;
   a Debug trace will send you after the wrong thing.
2. Run on a **real device**, not the simulator. The simulator's rendering path isn't
   representative. A ProMotion iPhone is ideal, since a 120 Hz target is the hardest case.
3. Product → Profile → **Time Profiler**. Add the **Animation Hitches** and **SwiftUI** instruments
   to the same document.
4. Record while doing one thing at a time, roughly 10 seconds each, in this order:
   - a. Slow continuous panning on the Market tab (5m timeframe).
   - b. Hard flings, letting momentum run out.
   - c. Continuous pinch in and out.
   - d. Switching timeframe (this triggers the appear animation).
   - e. Repeat b and c on the **Performance tab at 100K candles**.
5. Stop. In Time Profiler, set the call tree to **Invert Call Tree** and **Hide System Libraries**,
   then look at the top 10 symbols for each window.

## What to report back

For each of the five windows, the top 10 inverted-call-tree symbols with their weights, plus from
the Animation Hitches track: hitch count, total hitch time, and the longest single hitch. That's
enough to rank the remaining work properly.

## Hypotheses, ranked

These are the costs identified by reading the code. The ranking is a guess until a trace confirms
it — that's the point of the section above.

| # | Suspected cost | Status |
| --- | --- | --- |
| 1 | Whole-body invalidation: `CandlestickChart.body` read `revision`, so every animation frame rebuilt the header, the accessibility strings, the gesture representable and the ZStack. | Fixed (unverified) |
| 2 | `ChartAccessibility.summary` formatting two dates and two numbers **per frame**, for a string only VoiceOver reads. Date formatting is among the most expensive things Foundation does. | Fixed (unverified) |
| 3 | Appear animation copying `GraphicsContext` and issuing 2–3 fills **per candle per frame** — over a thousand draw calls per frame at wide zoom. | Fixed (unverified) |
| 4 | Axis labels running `FormatStyle` for every tick inside the Canvas draw closure, every frame. | Fixed (unverified) |
| 5 | An always-present crosshair `Canvas` re-rasterising every frame even with no crosshair shown. | Fixed (unverified) |
| 6 | `context.draw(Text)` in Canvas: ~12 text layouts per frame, which SwiftUI may or may not cache across frames. Cannot be removed without moving axis labels out of the Canvas into real `Text` views. | **Open** — see below |
| 7 | Per-frame O(visible) geometry for candles, volume and indicators. Unavoidable in principle, but at minimum zoom on iPad this is ~1000 candles × several layers. | **Open** |
| 8 | During a pinch, `isScrolling` is false, so the price range, tick values and every label string are recomputed each frame. Legitimate (the scale really is changing), but it makes zoom strictly more expensive than pan. | **Open** |
| 9 | `Canvas` renders synchronously on the main thread by default. `rendersAsynchronously: true` may help, but interacts badly with text. Worth an experiment once a trace exists. | **Open — experiment** |

### If the trace points at #6 (text drawing)

The fix is to stop drawing axis labels inside the `Canvas` and render them as real SwiftUI `Text`
views positioned over it. SwiftUI caches glyph rasterisation for unchanged `Text`, so panning would
stop re-rasterising labels entirely. This is a real refactor of `drawAxes`, which is why it hasn't
been done speculatively.

### If the trace points at #7 (raw geometry volume)

Options, in increasing order of effort: raise `ZoomLimits.minimumSpacing` so fewer candles are ever
on screen at once; downsample to one candle per horizontal pixel below some spacing threshold
(visually identical, since sub-pixel candles can't be distinguished anyway); or move the renderer
to Metal behind the existing seam.

The downsampling option is probably the best value: below roughly 2pt spacing the user cannot
resolve individual candles, so aggregating each pixel column into a single min/max/first/last bar
costs nothing visually and cuts the per-frame work by whatever the oversampling factor is.

## Baseline

No numbers recorded yet. Fill this in from the first trace:

| Device | OS | Scenario | Candles | Hitches | Longest hitch | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| | | | | | | |
