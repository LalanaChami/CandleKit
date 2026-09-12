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
2. Run on a **real device**. The Simulator's rendering path isn't representative and its CPU is your
   Mac's — the capture bar labels simulator reports `NOT REPRESENTATIVE`, and those rows don't belong
   in the log. See [Simulator limits](#what-you-can-and-cant-do-on-the-simulator).
3. Performance tab → pick a dataset size → **Capture**.
4. Do exactly one interaction for ~10 seconds: slow pan, or hard flings, or continuous pinch.
5. **Stop capture** → **Copy** → paste into the log below under the right heading.

Repeat per scenario. One interaction per capture — mixing them averages the interesting case away.

## Recipe B — Instruments (when you need the full picture)

Recipe A only measures what CandleKit times. It can't see SwiftUI diffing, Core Animation commits,
or text rasterisation inside `Canvas`. When the phase table doesn't explain the hitches, do this.

> **Animation Hitches needs a physical device.** Hitch measurement reads timing from the real
> display pipeline (Core Animation commit → frame presented on the panel). The Simulator has no such
> pipeline, so the instrument fails with `Hitches is not supported on this platform`. There's no
> workaround and no setting — see [Simulator limits](#what-you-can-and-cant-do-on-the-simulator) for
> what's still worth doing without a device.

### Easiest route: Xcode's GUI

For interactive profiling this beats the CLI, because you can get the app into the state you want
before hitting record.

1. Release build (Product → Scheme → Edit Scheme → Profile → Build Configuration → Release).
2. Select your **physical device** as the run destination.
3. **⌘I** (Product → Profile) → choose **Animation Hitches**.
4. Add the **SwiftUI** and **os_signpost** instruments to the same document (`+` in the toolbar), so
   CandleKit's phase signposts line up against the hitch track.
5. Record ~10 seconds each of: slow pan · hard flings · continuous pinch · timeframe switch (fires
   the appear animation) · the same on the Performance tab at 100K candles.
6. In Time Profiler, set **Invert Call Tree** and **Hide System Libraries**, then read the top 10
   symbols per window.

### From the command line

Find the exact device name or UDID first — guessing doesn't work:

```sh
xcrun xctrace list devices
xcrun xctrace list templates    # exact template names, they're case-sensitive
```

Attaching is usually easier than launching, since you can navigate to the tab you want first, then
start recording:

```sh
# Launch the app on the device by hand, then:
xcrun xctrace record \
  --template 'Animation Hitches' \
  --device-name "Lalana's iPhone" \
  --output candlekit-pan.trace \
  --time-limit 20s \
  --attach CandleKitDemo
```

To launch from scratch instead, note two things that are easy to get wrong:

- `--launch --` takes a **path to the `.app` bundle**, not a bundle identifier. Get it from Xcode's
  Products group (right-click → Show in Finder) or from
  `xcodebuild -showBuildSettings -scheme CandleKitDemo | grep -w BUILT_PRODUCTS_DIR`.
- **`--output` must come before `--launch`.** Everything after `--` is passed to the app being
  launched, so a trailing `--output` is swallowed as an app argument and silently ignored.

```sh
xcrun xctrace record \
  --template 'Animation Hitches' \
  --device-name "Lalana's iPhone" \
  --output candlekit-pan.trace \
  --time-limit 20s \
  --launch -- /path/to/Build/Products/Release-iphoneos/CandleKitDemo.app
```

Open the result with `open -a Instruments candlekit-pan.trace`. CLI export (`xctrace export`) is
unreliable enough that reading the trace in the GUI is the better default.

### What you can and can't do on the Simulator

Hitches, and anything else that depends on real display timing, are unavailable. Worse, the numbers
you *can* get are distorted in both directions: CPU work runs on your Mac's cores and so looks far
cheaper than it is on a phone, while SwiftUI and Core Animation rendering goes through a different
path that is often slower. Ratios between phases aren't trustworthy, which is exactly what you'd be
profiling for.

The Simulator is still useful for finding gross algorithmic problems — an O(n) loop over all candles
in the per-frame path will show up anywhere. For that:

```sh
xcrun xctrace record \
  --template 'Time Profiler' \
  --device <simulator-UDID-from-list-devices> \
  --output candlekit-sim.trace \
  --time-limit 20s \
  --attach CandleKitDemo
```

Recipe A's in-app capture also runs on the Simulator, and the capture bar tags those reports
`NOT REPRESENTATIVE` for the reasons above. **Simulator runs don't go in the trace log.** If you
don't have a device to hand, record what you find as a note in the roadmap rather than as a
baseline, and be explicit that it's simulator data.

### Troubleshooting

| Symptom | Cause |
| --- | --- |
| `Hitches is not supported on this platform` | Recording on a Simulator. Device only. |
| `--output` ignored, trace saved as `Launch_…_<date>.trace` | `--output` came after `--launch --`, so it went to the app instead of xctrace. |
| Device not found | Name must match `xcrun xctrace list devices` exactly, apostrophes included. Use the UDID with `--device` if quoting fights you. |
| App crashes immediately on `--launch` | The build lacks `get-task-allow` — profile a locally-signed Debug or Release build, not an App Store one. |

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
