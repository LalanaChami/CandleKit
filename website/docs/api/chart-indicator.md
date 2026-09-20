---
id: chart-indicator
title: ChartIndicator & Indicator
sidebar_label: ChartIndicator
---

# `ChartIndicator`

An indicator attached to a chart, with optional color overrides.

```swift
public struct ChartIndicator: Identifiable {
    public var indicator: any Indicator
    public var colors: [Color]
    public var lineWidth: CGFloat?
    public var isVisible: Bool
}
```

| Property | Description |
| --- | --- |
| `indicator` | The indicator itself. Mutable so a settings UI can write edited parameters back. |
| `colors` | Overrides for the palette this indicator's plots resolve `IndicatorColorRole.series(_:)` against. Empty uses the chart style's palette. |
| `lineWidth` | Overrides the width of every line plot. `nil` keeps each plot's own width. |
| `isVisible` | Hides the indicator without removing it, so a settings UI can offer a visibility toggle that preserves configuration. |

## Initializer

```swift
public init(_ indicator: any Indicator, colors: [Color] = [], lineWidth: CGFloat? = nil, isVisible: Bool = true)
```

## Computed properties

```swift
public var id: String            // stable, distinct per configuration
public var label: String         // compact legend label, e.g. "RSI 14"
public var descriptor: IndicatorDescriptor  // what a saved layout stores
```

## Built-in factories

Every factory below returns a configured `ChartIndicator`. See the
[Indicators guide](/guides/indicators) for a friendlier walkthrough with descriptions and
screenshots — this table is the terse signature reference.

| Factory | Signature |
| --- | --- |
| Simple moving average | `static func sma(_ period: Int, color: Color? = nil, lineWidth: CGFloat? = nil) -> ChartIndicator` |
| Exponential moving average | `static func ema(_ period: Int, color: Color? = nil, lineWidth: CGFloat? = nil) -> ChartIndicator` |
| Weighted moving average | `static func wma(_ period: Int, color: Color? = nil, lineWidth: CGFloat? = nil) -> ChartIndicator` |
| Bollinger Bands | `static func bollingerBands(period: Int = 20, multiplier: Double = 2) -> ChartIndicator` |
| VWAP | `static func vwap() -> ChartIndicator` |
| RSI | `static func rsi(_ period: Int = 14) -> ChartIndicator` |
| MACD | `static func macd(fast: Int = 12, slow: Int = 26, signal: Int = 9) -> ChartIndicator` |
| Stochastic | `static func stochastic(period: Int = 14, smoothK: Int = 3, smoothD: Int = 3) -> ChartIndicator` |
| ATR | `static func atr(_ period: Int = 14) -> ChartIndicator` |
| On-Balance Volume | `static func obv() -> ChartIndicator` |
| Donchian Channels | `static func donchianChannels(period: Int = 20) -> ChartIndicator` |
| Keltner Channels | `static func keltnerChannels(period: Int = 20, atrPeriod: Int = 10, multiplier: Double = 2) -> ChartIndicator` |
| SuperTrend | `static func superTrend(period: Int = 10, multiplier: Double = 3) -> ChartIndicator` |
| Parabolic SAR | `static func parabolicSAR(step: Double = 0.02, maximum: Double = 0.2) -> ChartIndicator` |
| Ichimoku Cloud | `static func ichimokuCloud(conversionPeriod: Int = 9, basePeriod: Int = 26, spanBPeriod: Int = 52, displacement: Int = 26) -> ChartIndicator` |
| Pivot Points | `static func pivotPoints(method: IndicatorMath.PivotMethod = .classic) -> ChartIndicator` |
| ADX / DMI | `static func adx(_ period: Int = 14) -> ChartIndicator` |
| CCI | `static func cci(_ period: Int = 20) -> ChartIndicator` |
| Money Flow Index | `static func mfi(_ period: Int = 14) -> ChartIndicator` |
| Williams %R | `static func williamsR(_ period: Int = 14) -> ChartIndicator` |
| Rate of Change | `static func rateOfChange(period: Int = 12, mode: ROCIndicator.Mode = .percentage) -> ChartIndicator` |
| Chaikin Money Flow | `static func chaikinMoneyFlow(_ period: Int = 20) -> ChartIndicator` |

# `Indicator`

The protocol behind every indicator, built-in or custom. Conform your own type to add an indicator
CandleKit doesn't ship.

```swift
public protocol Indicator: Sendable {
    static var identifier: String { get }
    static var displayName: String { get }
    static var category: IndicatorCategory { get }

    var parameters: [IndicatorParameter] { get set }
    var pane: IndicatorPane { get }
    var shortLabel: String { get }

    func compute(_ candles: [Candle]) -> IndicatorResult
}
```

| Member | Description |
| --- | --- |
| `identifier` | Stable across releases — it's what saved layouts store. Changing it orphans existing layouts. |
| `displayName` | Shown in the picker, e.g. `"Relative Strength Index"`. |
| `category` | An `IndicatorCategory` used to group entries in a picker. |
| `parameters` | Configurable inputs. Settable so a picker can write edited values back. |
| `pane` | Where this indicator draws — `.price` (overlaid on the candles) or `.separate(preferredHeight:)` (its own pane below). |
| `shortLabel` | Compact label for the chart legend, usually name plus key parameters, e.g. `"RSI 14"`. |
| `compute(_:)` | Computes every plot, fill and level for `candles`. Called when the data changes, not on every frame. |

```swift
struct RangeIndicator: Indicator {
    static let identifier = "range"
    static let displayName = "High − Low"
    static let category = IndicatorCategory.volatility
    var parameters: [IndicatorParameter] = []
    var pane: IndicatorPane { .separate() }
    var shortLabel: String { "Range" }

    func compute(_ candles: [Candle]) -> IndicatorResult {
        IndicatorResult(plots: [
            IndicatorPlot(key: "range", name: "Range", values: candles.map { $0.high - $0.low })
        ])
    }
}
```

## `IndicatorDescriptor`

A serializable reference to a configured indicator: which one, and with what settings. This is what
a saved chart layout stores.

```swift
public struct IndicatorDescriptor: Hashable, Sendable, Codable, Identifiable {
    public var identifier: String
    public var parameters: [String: IndicatorParameterValue]

    public init(identifier: String, parameters: [String: IndicatorParameterValue] = [:])
}
```

## `IndicatorCatalog`

The set of indicators available to a chart — what a picker lists, and what saved layouts can
resolve against. Immutable by design; add your own indicators with `adding(_:)` rather than
mutating shared state.

```swift
public struct IndicatorCatalog: Sendable {
    public let entries: [IndicatorCatalogEntry]

    public init(entries: [IndicatorCatalogEntry])
    public func entry(for identifier: String) -> IndicatorCatalogEntry?
    public func makeIndicator(from descriptor: IndicatorDescriptor) -> (any Indicator)?
    public func groupedByCategory() -> [(category: IndicatorCategory, entries: [IndicatorCatalogEntry])]
    public func search(_ query: String) -> [IndicatorCatalogEntry]
    public func adding(_ entry: IndicatorCatalogEntry) -> IndicatorCatalog
    public func removing(identifier: String) -> IndicatorCatalog
}
```

## `IndicatorCatalogEntry`

One indicator type the picker can offer.

```swift
public struct IndicatorCatalogEntry: Sendable, Identifiable {
    public let identifier: String
    public let displayName: String
    public let category: IndicatorCategory
    public let defaultParameters: [IndicatorParameter]

    public init<T: Indicator>(_ type: T.Type, default makeDefault: @Sendable @escaping () -> T)
    public func makeDefault() -> any Indicator
    public func makeIndicator(parameters stored: [String: IndicatorParameterValue]) -> any Indicator
}
```
