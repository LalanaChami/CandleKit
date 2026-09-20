---
id: candles-and-viewport
title: Candles & the Viewport
sidebar_label: Candles & Viewport
---

# Candles & the Viewport

Before diving into indicators, drawings and styling, it's worth understanding the two things every
chart is built from: the `Candle` model, and the viewport that decides what part of your data is
currently on screen.

## The `Candle` model

A `Candle` is one OHLCV bar — open, high, low, close and volume for a single time period:

```swift
public struct Candle: Hashable, Sendable, Identifiable {
    public var time: Date
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double
    public var volume: Double
}
```

`id` is just `time`, and `isBullish` tells you whether the candle closed at or above where it
opened (`close >= open`) — useful if you ever need to color something yourself outside of
CandleKit's own rendering.

:::caution
Candles passed to `CandlestickChart` must be sorted by `time` in ascending order (oldest first),
with no duplicate times. The chart does binary searches and viewport math that assume this — an
out-of-order or duplicated series will produce a confusing chart, not a crash.
:::

## Live updates: append vs. prepend

You don't need a special "update" API. Just replace the `candles` array you're passing to
`CandlestickChart`, and it will figure out what changed and react appropriately:

- **The last candle updated in place** (e.g. the current bar ticking as a trade comes in) — the
  chart redraws it, and your scroll position doesn't move.
- **New candles appended** to the end — the chart scrolls to show them, but only if the newest
  candle was already on screen. If you'd scrolled back into history, appending new data at the tip
  doesn't yank you back to "now".
- **Older candles prepended** to the front (you loaded more history) — the chart keeps the exact
  same candles visible; nothing jumps around underneath the user's finger.
- **An unrelated series** (you switched symbols, or reloaded from scratch) — the chart treats this
  as brand new data and jumps to the newest candle.

```swift
@State private var candles: [Candle] = []

CandlestickChart(candles)
    .task {
        candles = await loadInitialCandles()
    }
    .onReachOldestCandle {
        Task {
            let older = await loadHistoryBefore(candles.first?.time)
            candles = older + candles
        }
    }
```

## `CandleChartState`: controlling the chart from outside

By default, `CandlestickChart` manages its own scroll position and zoom level internally — you
don't need to think about it at all. But sometimes your app needs to *drive* the chart from
somewhere else: a "Jump to latest" button, or resetting the zoom when the user switches symbols.
That's what `CandleChartState` is for.

```swift
struct PriceView: View {
    let candles: [Candle]
    @State private var chartState = CandleChartState()

    var body: some View {
        VStack {
            CandlestickChart(candles, state: chartState)

            if !chartState.isFollowingLatest {
                Button("Jump to latest") {
                    chartState.animatedScrollToLatest()
                }
            }
        }
    }
}
```

Create one `CandleChartState`, pass it to `CandlestickChart(_:state:)`, and you can read
`isFollowingLatest` or call methods like `scrollToLatest()`, `resetZoom()`,
`animatedScrollToLatest()` and `animatedResetZoom()` from anywhere else in your view hierarchy. See
the [`CandleChartState` API reference](/api/candle-chart-state) for the full list.

If you don't pass a `state:` at all, `CandlestickChart` creates its own internal one — you only
need to reach for `CandleChartState` explicitly when something *outside* the chart needs to control
or observe it.
