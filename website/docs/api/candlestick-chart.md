---
id: candlestick-chart
title: CandlestickChart
sidebar_label: CandlestickChart
---

# `CandlestickChart`

The main chart view. A plain SwiftUI `View`, so it composes with `.frame(...)`, `.padding(...)` and
everything else you'd expect.

```swift
public struct CandlestickChart: View
```

## Initializer

```swift
public init(_ candles: [Candle], state: CandleChartState? = nil)
```

| Parameter | Description |
| --- | --- |
| `candles` | The series to draw, sorted oldest first. |
| `state` | Pass your own `CandleChartState` to control scrolling/zoom from outside the chart. Omit it and the chart manages its own state internally. |

```swift
CandlestickChart(candles)
CandlestickChart(candles, state: chartState)
```

## Modifiers

Every modifier below returns a new `CandlestickChart`, so they chain like any other SwiftUI
modifier.

### `.candleChartStyle(_:)`

```swift
public func candleChartStyle(_ style: CandleChartStyle) -> CandlestickChart
```

Colors and candle appearance. See [`CandleChartStyle`](/api/style-and-configuration) for every
property and the built-in presets.

```swift
CandlestickChart(candles).candleChartStyle(.redUp)
```

### `.indicators(_:)`

```swift
public func indicators(_ indicators: [ChartIndicator]) -> CandlestickChart
```

Line overlays such as moving averages, plus oscillators in their own panes. Values are cached and
only recomputed when the data changes. See [`ChartIndicator`](/api/chart-indicator).

```swift
CandlestickChart(candles).indicators([.sma(20), .ema(50)])
```

### `.volumeVisible(_:)`

```swift
public func volumeVisible(_ visible: Bool = true) -> CandlestickChart
```

Shows volume bars beneath the candles. On by default.

```swift
CandlestickChart(candles).volumeVisible(false)
```

### `.headerVisible(_:)`

```swift
public func headerVisible(_ visible: Bool = true) -> CandlestickChart
```

Shows the price readout above the chart. On by default.

```swift
CandlestickChart(candles).headerVisible(false)
```

### `.priceFractionDigits(_:)`

```swift
public func priceFractionDigits(_ digits: Int?) -> CandlestickChart
```

Decimal places for prices. By default this is inferred automatically from the latest close (so a
$45,000 asset and a $0.003 asset both get a sensible number of decimals without you specifying
anything).

```swift
CandlestickChart(candles).priceFractionDigits(4)
```

### `.onCrosshairChange(_:)`

```swift
public func onCrosshairChange(_ action: @escaping (Candle?) -> Void) -> CandlestickChart
```

Called when the long-pressed candle changes, and with `nil` when the finger lifts.

```swift
CandlestickChart(candles)
    .onCrosshairChange { candle in
        selectedCandle = candle
    }
```

### `.onReachOldestCandle(_:)`

```swift
public func onReachOldestCandle(_ action: @escaping () -> Void) -> CandlestickChart
```

Called when the user scrolls near the oldest loaded candle — prepend older candles to your array in
response. The handler runs once per data size, so it won't fire repeatedly while a request is in
flight.

```swift
CandlestickChart(candles)
    .onReachOldestCandle {
        Task { await loadHistory() }
    }
```

### `.drawings(_:)`

```swift
public func drawings(_ drawings: Binding<[Drawing]>) -> CandlestickChart
```

The app-owned array of trend lines, rectangles, Fibonacci retracements and other annotations the
person draws on the chart — the same "app owns the array" shape `.indicators([...])` already uses.
Omitting this modifier means drawing tools cost nothing at all: no extra Canvas layer, no
gesture-mode branching. See the [Drawing Tools guide](/guides/drawing-tools) and the
[`Drawing` API reference](/api/drawings).

```swift
CandlestickChart(candles).drawings($drawings)
```

### `.defaultDrawingStyle(_:)`

```swift
public func defaultDrawingStyle(_ style: DrawingStyle) -> CandlestickChart
```

The color, line width, dash and fill opacity a **newly created** drawing starts with. Defaults to
`DrawingStyle()`'s neutral blue. To recolor a drawing that already exists — including the currently
selected one — mutate its `style` directly in your own `.drawings(...)` array instead.

```swift
CandlestickChart(candles).defaultDrawingStyle(DrawingStyle(color: .default, lineWidth: 2))
```

### `.drawingTool(_:)`

```swift
public func drawingTool(_ tool: Binding<DrawingTool?>) -> CandlestickChart
```

Which drawing tool is active, or `nil` for the chart's ordinary pan/zoom/crosshair behavior (the
default). While a tool is set, a one-finger drag creates a drawing of that kind instead of panning
the chart, and pinch/long-press are suppressed; releasing commits the drawing and the tool stays
selected for the next one. Requires `.drawings(...)` to also be attached.

```swift
CandlestickChart(candles)
    .drawings($drawings)
    .drawingTool($activeTool)
```

### `.selectedDrawing(_:)`

```swift
public func selectedDrawing(_ selection: Binding<UUID?>) -> CandlestickChart
```

Mirrors which drawing's `id` is currently selected (by tapping it, in cursor mode), or `nil` when
nothing is selected. One-way, chart → app: use it to show your own inspector or "Delete" button.
Deletion itself is just `drawings.removeAll { $0.id == id }` on your own `.drawings(...)` binding.
Optional — omit it if you don't need to react to selection.

```swift
CandlestickChart(candles)
    .drawings($drawings)
    .selectedDrawing($selectedDrawingID)
```

## A fuller example

```swift
CandlestickChart(candles, state: chartState)
    .candleChartStyle(CandleChartStyle(priceAxisMaterial: .ultraThinMaterial))
    .indicators([.sma(20), .ema(50), .rsi(14)])
    .volumeVisible(true)
    .drawings($drawings)
    .drawingTool($activeDrawingTool)
    .selectedDrawing($selectedDrawingID)
    .defaultDrawingStyle(DrawingStyle(color: drawingColor))
    .onReachOldestCandle { Task { await loadHistory() } }
    .onCrosshairChange { candle in selectedCandle = candle }
```
