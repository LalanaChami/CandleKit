---
id: candle-chart-state
title: CandleChartState
sidebar_label: CandleChartState
---

# `CandleChartState`

Scroll position, zoom level and crosshair for a `CandlestickChart`. You only need to create one
when you want to drive the chart from outside — for example a "Jump to latest" button. Otherwise
the chart manages its own state internally.

```swift
@MainActor
@Observable
public final class CandleChartState
```

## Initializer

```swift
public init(candleSpacing: Double = 8, zoomLimits: ZoomLimits = ZoomLimits(), rightPadding: Double = 3)
```

| Parameter | Description |
| --- | --- |
| `candleSpacing` | Initial width of one candle slot, in points. |
| `zoomLimits` | How far the user can pinch in and out. |
| `rightPadding` | Empty candle slots shown after the newest candle. |

```swift
@State private var chartState = CandleChartState()
@State private var wideState = CandleChartState(candleSpacing: 12)

CandlestickChart(candles, state: chartState)
```

## Public properties

| Property | Type | Description |
| --- | --- | --- |
| `crosshairIndex` | `Int?` (get-only) | Index of the candle under the crosshair while the user is long-pressing, otherwise `nil`. |
| `isFollowingLatest` | `Bool` (get-only) | `true` when the newest candle is on screen. New candles then scroll into view automatically. |

## Public methods

### `scrollToLatest()`

```swift
public func scrollToLatest()
```

Jumps immediately to the newest candle.

### `resetZoom()`

```swift
public func resetZoom()
```

Restores the initial zoom level and scrolls to the newest candle, immediately (no animation).

### `animatedResetZoom()`

```swift
public func animatedResetZoom()
```

Like `resetZoom()`, but eases to the destination with a spring instead of snapping — the same
animation double-tap-to-reset uses. Prefer this for anything a person taps deliberately. Respects
Reduce Motion (jumps straight to the destination when it's on).

### `animatedScrollToLatest()`

```swift
public func animatedScrollToLatest()
```

Like `scrollToLatest()`, but eases to the destination with a spring instead of snapping. Keeps the
current zoom level, unlike `animatedResetZoom()`, which also resets it. Respects Reduce Motion.

```swift
Button("Latest") {
    chartState.animatedScrollToLatest()
}
```

### `stopAnimations()`

```swift
public func stopAnimations()
```

Immediately stops any running appear or spring-to-target animation, without changing the current
viewport. `CandlestickChart` calls this automatically when the chart leaves the view hierarchy.
Call it yourself if you manage a `CandleChartState` outside a `CandlestickChart`'s own lifecycle —
for example, one state object per row in a list of charts that scroll on and off screen.

## Example: a "Jump to latest" button

```swift
struct PriceView: View {
    let candles: [Candle]
    @State private var chartState = CandleChartState()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CandlestickChart(candles, state: chartState)

            if !chartState.isFollowingLatest {
                Button("Latest") {
                    chartState.animatedScrollToLatest()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
    }
}
```
