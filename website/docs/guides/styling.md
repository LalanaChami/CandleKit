---
id: styling
title: Styling
sidebar_label: Styling
---

# Styling

Everything about how a chart looks — candle colors, grid, axis labels, the crosshair, and the
palette indicators cycle through — lives in one `CandleChartStyle` value, attached with
`.candleChartStyle(_:)`. Its defaults use semantic system colors, so an unstyled chart already
adapts correctly to light mode, dark mode and increased contrast without you doing anything.

```swift
CandlestickChart(candles)
    .candleChartStyle(.standard)
```

## Every property

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

| Property | What it controls |
| --- | --- |
| `upColor` / `downColor` | The fill color for bullish (close ≥ open) and bearish candles. |
| `hollowUpCandles` | Draws rising candles as outlines instead of filled bodies. |
| `bodyWidthRatio` | Candle body width as a fraction of its slot width (clamped to `0.1...1`). |
| `volumeOpacity` | Opacity of the volume bars underneath the candles. |
| `gridColor` | Color of the background grid lines. |
| `axisLabelColor` | Color of the price/time axis tick labels. |
| `crosshairColor` | Color of the crosshair line and its floating labels. |
| `indicatorPalette` | Colors that `IndicatorColorRole.series(_:)` cycles through, so two overlays added back to back get visually distinct colors automatically. |
| `priceAxisMaterial` | `nil` keeps the classic fully-transparent axis. Set a `Material` (e.g. `.ultraThinMaterial`) to turn on a frosted price axis, with candles softly blurred behind it as they scroll toward the edge. |
| `crosshairDimOpacity` | How much every candle *other than* the focused one dims while the crosshair is showing (`0` disables dulling entirely). |

All parameters have defaults, so you only need to specify the ones you're actually changing:

```swift
CandlestickChart(candles)
    .candleChartStyle(CandleChartStyle(
        priceAxisMaterial: .ultraThinMaterial,
        bodyWidthRatio: 0.6
    ))
```

## Built-in presets

CandleKit ships three ready-made styles as static properties on `CandleChartStyle`:

| Preset | What it's for |
| --- | --- |
| `.standard` | Green for rising candles, red for falling — the convention most Western traders expect. This is the default if you don't set a style at all. |
| `.redUp` | Red for rising, green for falling — the convention used in mainland China, Taiwan and South Korea. |
| `.colorBlindSafe` | Blue and orange, chosen to stay distinguishable under the most common forms of color blindness. |

```swift
CandlestickChart(candles)
    .candleChartStyle(.redUp)
```

## A custom style

Since `CandleChartStyle` is a plain struct with memberwise defaults, building your own house style
is just constructing one with the properties you care about:

```swift
extension CandleChartStyle {
    static var midnight: CandleChartStyle {
        CandleChartStyle(
            upColor: .mint,
            downColor: .pink,
            hollowUpCandles: true,
            bodyWidthRatio: 0.65,
            volumeOpacity: 0.2,
            indicatorPalette: [.yellow, .cyan, .purple],
            priceAxisMaterial: .ultraThinMaterial
        )
    }
}

CandlestickChart(candles)
    .candleChartStyle(.midnight)
```

See the [style API reference](/api/style-and-configuration) for the full initializer signature and
every default value.
