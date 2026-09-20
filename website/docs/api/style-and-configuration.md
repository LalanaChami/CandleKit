---
id: style-and-configuration
title: CandleChartStyle
sidebar_label: CandleChartStyle
---

# `CandleChartStyle`

Visual configuration for `CandlestickChart`. Defaults use semantic system colors, so the chart
adapts to light mode, dark mode and increased contrast automatically. See the
[Styling guide](/guides/styling) for a friendlier walkthrough — this page is the terse full
reference.

```swift
public struct CandleChartStyle {
    public var upColor: Color
    public var downColor: Color
    public var hollowUpCandles: Bool
    public var bodyWidthRatio: CGFloat
    public var volumeOpacity: Double
    public var gridColor: Color
    public var axisLabelColor: Color
    public var crosshairColor: Color
    public var indicatorPalette: [Color]
    public var priceAxisMaterial: Material?
    public var crosshairDimOpacity: Double
}
```

## Initializer

```swift
public init(
    upColor: Color = .green,
    downColor: Color = .red,
    hollowUpCandles: Bool = false,
    bodyWidthRatio: CGFloat = 0.7,
    volumeOpacity: Double = 0.28,
    gridColor: Color = Color.secondary.opacity(0.14),
    axisLabelColor: Color = .secondary,
    crosshairColor: Color = Color.primary.opacity(0.55),
    indicatorPalette: [Color] = [.orange, .purple, .teal, .pink, .indigo, .brown],
    priceAxisMaterial: Material? = nil,
    crosshairDimOpacity: Double = 0.28
)
```

`bodyWidthRatio` is clamped to `0.1...1`, and `crosshairDimOpacity` is clamped to `0...1`.

## Properties

| Property | Type | Default | Description |
| --- | --- | --- | --- |
| `upColor` | `Color` | `.green` | Fill color for bullish candles. |
| `downColor` | `Color` | `.red` | Fill color for bearish candles. |
| `hollowUpCandles` | `Bool` | `false` | Draws rising candles as outlines instead of filled bodies. |
| `bodyWidthRatio` | `CGFloat` | `0.7` | Candle body width as a fraction of the slot width. |
| `volumeOpacity` | `Double` | `0.28` | Opacity of the volume bars. |
| `gridColor` | `Color` | `Color.secondary.opacity(0.14)` | Background grid line color. |
| `axisLabelColor` | `Color` | `.secondary` | Price/time axis tick label color. |
| `crosshairColor` | `Color` | `Color.primary.opacity(0.55)` | Crosshair line/label color. |
| `indicatorPalette` | `[Color]` | `[.orange, .purple, .teal, .pink, .indigo, .brown]` | Colors that `IndicatorColorRole.series(_:)` cycles through. |
| `priceAxisMaterial` | `Material?` | `nil` | `nil` keeps the classic transparent axis. A `Material` turns on a frosted axis with candles blurred behind it. |
| `crosshairDimOpacity` | `Double` | `0.28` | How much every non-focused candle dims while the crosshair is showing. `0` disables dulling. |

## Static presets

```swift
public static var standard: CandleChartStyle { get }       // CandleChartStyle()
public static var redUp: CandleChartStyle { get }           // upColor: .red, downColor: .green
public static var colorBlindSafe: CandleChartStyle { get }  // upColor: .blue, downColor: .orange
```

| Preset | `upColor` | `downColor` | Use case |
| --- | --- | --- | --- |
| `.standard` | `.green` | `.red` | Default — green for rising, red for falling. |
| `.redUp` | `.red` | `.green` | Convention in mainland China, Taiwan and South Korea. |
| `.colorBlindSafe` | `.blue` | `.orange` | Stays distinguishable under the most common forms of color blindness. |
