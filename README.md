# CandleKit

Interactive candlestick charts for SwiftUI, built to feel like a native iOS control.

CandleKit gives you momentum scrolling, pinch zoom around your fingers, a long-press crosshair, live updates and infinite history with Apple platform conventions: system colors that adapt to dark mode, haptic feedback, Dynamic Type, and VoiceOver Audio Graphs.

```swift
import CandleKit

struct PriceView: View {
    let candles: [Candle]

    var body: some View {
        CandlestickChart(candles)
            .indicators([.sma(20), .ema(50)])
            .frame(height: 360)
    }
}
```

> **Status: 0.1, pre-release.** The core engine has a full unit test suite. The SwiftUI layer has not yet been profiled on device or covered by snapshot tests. Feedback and bug reports are very welcome.

## Requirements

iOS 17 or later, and Xcode 16 or later (Swift 6 toolchain). The engine target, `CandleKitCore`, has no UI dependencies and builds on macOS and Linux too.

## Installation

In Xcode, choose **File › Add Package Dependencies** and enter the repository URL. Or add it to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/LalanaChami/CandleKit.git", from: "0.1.0")
]
```

Then add `"CandleKit"` to your target's dependencies.

## Interacting with the chart

Drag horizontally to scroll, and release with some speed for momentum. Pinch to zoom; the candles under your fingers stay put. Long-press to show the crosshair and move your finger to inspect candles, with a selection haptic as it snaps from one candle to the next. Lift to dismiss. Double-tap to reset the zoom and jump back to the newest candle.

Vertical drags are left alone, so a chart inside a `ScrollView` doesn't trap the page.

## Live data

Just update your array. The chart compares each new array with the previous one and adjusts:

| What changed | What the chart does |
| --- | --- |
| Last candle updated in place | Redraws; scroll position is untouched |
| Candles appended | Scrolls to show them if the newest candle was on screen, otherwise stays put |
| Older candles prepended | Keeps the same candles on screen |
| Unrelated series (e.g. new symbol) | Jumps to the newest candle |

```swift
@State private var candles: [Candle] = []

CandlestickChart(candles)
    .task {
        for await tick in priceFeed.ticks {
            if let last = candles.last, tick.time < last.time.addingTimeInterval(60) {
                candles[candles.count - 1].close = tick.price
                candles[candles.count - 1].high = max(last.high, tick.price)
                candles[candles.count - 1].low = min(last.low, tick.price)
            } else {
                candles.append(Candle(time: tick.time, open: tick.price, high: tick.price, low: tick.price, close: tick.price))
            }
        }
    }
```

Candles must be sorted oldest first, with unique times.

## Loading history as the user scrolls back

```swift
CandlestickChart(candles)
    .onReachOldestCandle {
        guard let oldest = candles.first else { return }
        Task {
            let older = try await api.candles(before: oldest.time, limit: 500)
            candles.insert(contentsOf: older, at: 0)
        }
    }
```

The handler fires once per data size, so it won't be called again until your array actually grows.

## Controlling the chart from outside

Create a `CandleChartState` when you need to drive the chart yourself:

```swift
@State private var chartState = CandleChartState(candleSpacing: 10)

CandlestickChart(candles, state: chartState)
    .toolbar {
        if !chartState.isFollowingLatest {
            Button("Jump to latest", systemImage: "arrow.right.to.line") {
                chartState.scrollToLatest()
            }
        }
    }
```

`CandleChartState` also offers `resetZoom()`, `scroll(byCandles:)` and the observable `crosshairIndex`.

## Customization

| Modifier | Purpose |
| --- | --- |
| `.candleChartStyle(_:)` | Colors, hollow candles, body width |
| `.indicators(_:)` | SMA and EMA overlays |
| `.volumeVisible(_:)` | Volume bars (on by default) |
| `.headerVisible(_:)` | Price readout above the chart (on by default) |
| `.priceFractionDigits(_:)` | Fixed decimal places instead of inferring them |
| `.onCrosshairChange(_:)` | The inspected candle, or `nil` when released |
| `.onReachOldestCandle(_:)` | Load more history |

Three style presets are included. `.standard` is green up and red down. `.redUp` follows the convention used in markets such as mainland China, Taiwan and South Korea. `.colorBlindSafe` uses blue and orange. You can also build your own:

```swift
.candleChartStyle(CandleChartStyle(upColor: .mint, downColor: .pink, hollowUpCandles: true))
```

## Accessibility

The chart is a single VoiceOver element with a spoken summary of the visible range. Swipe up or down to page through history. It also provides an `AXChartDescriptor`, so VoiceOver users can open Audio Graphs and hear closing prices as pitch. Axis labels scale with Dynamic Type up to a size that still fits the axes.

## Performance notes

Candles are drawn with `Canvas` and batched into a handful of paths, so the number of draw calls stays constant however many candles are visible. Only visible candles are processed each frame. Indicator values are cached and recomputed only when the data changes, never while scrolling. The crosshair is drawn on its own layer, so moving a finger doesn't redraw the candles.

Momentum scrolling asks for 120 Hz. On ProMotion iPhones that also requires the `CADisableMinimumFrameDurationOnPhone` key set to `YES` in your app's Info.plist.

## Architecture

The package has two targets. `CandleKitCore` is pure Foundation and holds every decision that can be tested without a screen: the `Viewport` (index-based positions, pan, anchored zoom, clamping), series change detection, price autoscaling and tick selection, time label placement, and indicators. `CandleKit` holds the SwiftUI and UIKit layers: the chart view, the `Canvas` renderers, the crosshair overlay, and a transparent UIKit view that owns the gesture recognizers.

The x-axis is positional rather than time-based, so nights, weekends and holidays don't leave gaps. Time labels are placed on multiples of a stride, so they don't jitter as you scroll, and a label is promoted to a coarser unit when it crosses a day, month or year boundary.

## Running the tests

```sh
swift test
```

This runs the engine tests on macOS or Linux. To build the SwiftUI layer, open `Package.swift` in Xcode and build for an iOS Simulator. The previews in `Previews.swift` include a live-streaming demo with history loading.

## Roadmap

Planned next: separate indicator panes (RSI, MACD), drawing tools anchored to time and price, eased autoscaling, macOS and visionOS input, DocC documentation, and snapshot tests for the renderers. Further out: a home screen widget, a Live Activity, a watchOS companion, and other things a WebView-based chart can't do. Full detail, including what's deliberately out of scope, is in [`docs/ROADMAP.md`](docs/ROADMAP.md). If one of these matters to you, open an issue so it can be prioritized.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

CandleKit is available under the MIT license. See [LICENSE](LICENSE).
