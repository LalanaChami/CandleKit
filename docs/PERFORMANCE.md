# Performance

## Why this file exists

CandleKit's first three rounds of performance work were done without a single measurement — costs
were ranked by reading the code. Each round fixed something real, but the ranking was guesswork, and
the usual result of that is fixing four minor things while the dominant cost goes untouched.

Scrolling and the appear animation are reported fixed as of the second perf pass. This file exists
so the *next* problem gets numbers first. **Record a trace before changing anything for performance,
and paste it into the log at the bottom.**

## The chart measures its own phases

The renderer is instrumented with named phases (`Sources/CandleKit/ChartPerformance.swift`). They
feed two outputs from the same measurements:

- **Signposts** on the Points of Interest track in Instruments, so named intervals line up against
  Animation Hitches instead of leaving you to map SwiftUI symbols back to chart work by hand.
- **A markdown table** from `ChartPerformance.report(scenario:)`, which is what goes in the log
  below.

Instrumentation is **off by default** and costs one `Bool` check per phase when off. Turn it on by
setting `CANDLEKIT_PERF` in the scheme's environment, or by calling
`ChartPerformance.setEnabled(true)`.

### Phases

| Phase | What it covers |
| --- | --- |
| `makeFrame` | All of `CandleChartState.makeFrame`: data reconciliation, scales, ticks, labels |
| `makeFrame.priceRange` | Price autorange (skipped on a cache hit while panning) |
| `makeFrame.timeTicks` | Time-tick placement |
| `makeFrame.labels` | Axis label formatting (near-zero on a cache hit) |
| `draw.total` | The whole base-layer Canvas closure |
| `draw.grid` / `draw.volume` / `draw.candles` / `draw.indicators` | Batched geometry layers |
| `draw.appear` | Bucketed appear-animation candles (only while animating) |
| `draw.axes` | Axis labels and the last-price tag — the text-drawing path |
| `draw.crosshair` | The crosshair overlay Canvas (only while a crosshair is up) |

## Recipe A — in-app capture (fastest)

Gets you the table in the log below in about a minute per scenario.

1. Build the **Demo** in **Release** (Product → Scheme → Edit Scheme → Run → Build Configuration →
   Release). A Debug trace has unoptimised Swift and misleading SwiftUI overhead; it will send you
   after the wrong thing.
2. Run on a **real device**. The simulator's rendering path isn't representative — the capture bar
   labels simulator reports as such, and those rows don't belong in the log.
3. Performance tab → pick a dataset size → **Capture**.
4. Do exactly one interaction for ~10 seconds: slow pan, or hard flings, or continuous pinch.
5. **Stop capture** → **Copy** → paste into the log below under the right heading.

Repeat per scenario. One interaction per capture — mixing them averages the interesting case away.

## Recipe B — Instruments (when you need the full picture)

Recipe A only measures what CandleKit times. It can't see SwiftUI diffing, Core Animation commits,
or text rasterisation inside `Canvas`. When the phase table doesn't explain the hitches, do this:

1. Release build on device, as above.
2. Product → Profile → **Time Profiler**, then add **Animation Hitches**, **SwiftUI**, and
   **os_signpost** to the same document.
3. Record ~10 seconds each of: slow pan · hard flings · continuous pinch · timeframe switch (fires
   the appear animation) · the same on the Performance tab at 100K candles.
4. In Time Profiler, set **Invert Call Tree** and **Hide System Libraries**, then read the top 10
   symbols for each window. The signpost track tells you which chart phase each window sits in.

From the command line, if you'd rather script it:

```sh
xcrun xctrace record --template 'Animation Hitches' \
  --device-name '<your device>' \
  --launch -- '<app bundle id>' \
  --output trace.trace
```

### What to record in the log

For an Instruments run: hitch count, total hitch time, longest single hitch, and the top 5 inverted
symbols. For an in-app capture: paste the table as-is.

## Interpreting the numbers

A 120 Hz frame budget is **8.3 ms** and 60 Hz is **16.7 ms** — for *everything*, including the
SwiftUI and Core Animation work the phase table doesn't measure. Treat any phase over ~3 ms as worth
attention, and remember `draw.total` already includes its sub-phases (don't add them up).

## Known-remaining costs

Neither has been measured. Do that before acting on either.

- **Text drawing in `Canvas`** (`draw.axes`). Roughly 12 `context.draw(Text)` calls per frame, which
  SwiftUI may or may not cache across frames. If `draw.axes` is hot, the fix is to render axis labels
  as real SwiftUI `Text` views positioned over the Canvas, so glyph rasterisation is cached while
  panning. That's a real refactor of `drawAxes`, which is why it hasn't been done speculatively.
- **Raw geometry volume** (`draw.candles`, `draw.volume`). At minimum spacing on an iPad that's
  ~1000 candles across several layers. Best value fix is downsampling: below ~2pt spacing individual
  candles can't be resolved anyway, so aggregating each pixel column into one min/max/first/last bar
  is visually free and cuts the work by the oversampling factor. Failing that, raise
  `ZoomLimits.minimumSpacing`, or move the renderer to Metal behind the existing seam.

---

# Trace log

Newest first. Every entry needs device, OS, dataset size and interaction, or it can't be compared
against anything. Simulator runs don't belong here.

## Template

```
## <date> — <what changed since the last entry, or "baseline">

### <interaction> · <N> candles · <device> · iOS <version>

| Phase | Calls | Mean ms | p50 ms | p95 ms | Max ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| `draw.total` | | | | | |

Hitches: <count> · total <ms> · longest <ms>
Top inverted symbols: 1. … 2. … 3. …
Notes: <anything unusual — thermal state, other apps, Low Power Mode>
```

## Entries

_Empty. The first entry should be a baseline captured on the current `main`, before any further
performance changes — that's what everything after it gets compared against._
