import Foundation

// The output model an indicator produces.
//
// The old `IndicatorKind.values(for:) -> [Double?]` returned one number per candle, which is enough
// for a moving average and nothing else. Bollinger Bands need three lines and a fill between two of
// them; MACD needs two lines plus a histogram and a zero line; Ichimoku needs five lines and a
// shaded cloud; Parabolic SAR needs discrete dots rather than a connected line; RSI needs its own
// 0–100 pane with reference levels at 30 and 70. Everything here exists to describe those cases in
// a way the renderer can draw generically, without a special case per indicator.
//
// Deliberately free of any UI framework: this file is pure Foundation so it builds and tests on
// Linux, which means colours are expressed as roles the rendering layer resolves, not as `Color`.

/// How a plot's colour is chosen. Core has no `Color` type, so indicators name a role and the
/// rendering layer maps it onto the chart's style.
public enum IndicatorColorRole: Hashable, Sendable {
    /// Position in the chart's indicator palette. Distinct indices get visually distinct colours.
    case series(Int)
    /// Follows the chart's up colour.
    case bullish
    /// Follows the chart's down colour.
    case bearish
    /// Colour depends on the value's sign — rising histogram bars bullish, falling bearish.
    case signed
    /// Muted, for reference levels and gridline-like elements.
    case neutral
    /// Resolved by the host app. The string is an app-defined key.
    case custom(String)
}

/// How a series of values is drawn.
public enum IndicatorPlotStyle: Hashable, Sendable {
    /// A connected line. `dash` is a dash pattern in points, `nil` for solid.
    case line(width: Double = 1.5, dash: [Double]? = nil)
    /// A line that holds its value until the next change, for step-like series such as SuperTrend.
    case steppedLine(width: Double = 1.5)
    /// Vertical bars from `baseline` to the value, for MACD histograms and volume deltas.
    case histogram(baseline: Double = 0)
    /// Unconnected dots, for Parabolic SAR.
    case points(radius: Double = 1.5)
    /// Not drawn. Useful for a series that only exists to anchor a fill or feed the crosshair
    /// readout.
    case hidden
}

/// One drawable series produced by an indicator.
public struct IndicatorPlot: Hashable, Sendable {
    /// Stable identifier, unique within one indicator's output — `"upper"`, `"macd"`, `"signal"`.
    /// Fills reference plots by this key, and it's what a saved layout stores for per-plot styling.
    public var key: String
    /// Shown in the crosshair readout and any legend, for example `"Upper"`.
    public var name: String
    /// One entry per candle, `nil` where the indicator has no value yet (warm-up) or is undefined.
    public var values: [Double?]
    public var style: IndicatorPlotStyle
    public var colorRole: IndicatorColorRole

    public init(
        key: String,
        name: String,
        values: [Double?],
        style: IndicatorPlotStyle = .line(),
        colorRole: IndicatorColorRole = .series(0)
    ) {
        self.key = key
        self.name = name
        self.values = values
        self.style = style
        self.colorRole = colorRole
    }
}

/// A shaded region between two plots — Bollinger's band, Ichimoku's cloud, Keltner's channel.
public struct IndicatorFill: Hashable, Sendable {
    public var lowerPlotKey: String
    public var upperPlotKey: String
    public var colorRole: IndicatorColorRole
    public var opacity: Double
    /// When true, the fill is coloured by which plot is on top — how Ichimoku's cloud flips colour
    /// as the leading spans cross.
    public var colorFollowsCrossover: Bool

    public init(
        lowerPlotKey: String,
        upperPlotKey: String,
        colorRole: IndicatorColorRole = .series(0),
        opacity: Double = 0.12,
        colorFollowsCrossover: Bool = false
    ) {
        self.lowerPlotKey = lowerPlotKey
        self.upperPlotKey = upperPlotKey
        self.colorRole = colorRole
        self.opacity = opacity
        self.colorFollowsCrossover = colorFollowsCrossover
    }
}

/// A horizontal reference line — RSI's 30 and 70, MACD's zero.
public struct IndicatorLevel: Hashable, Sendable {
    public var value: Double
    public var label: String?
    public var colorRole: IndicatorColorRole
    public var dash: [Double]?

    public init(
        value: Double,
        label: String? = nil,
        colorRole: IndicatorColorRole = .neutral,
        dash: [Double]? = [3, 3]
    ) {
        self.value = value
        self.label = label
        self.colorRole = colorRole
        self.dash = dash
    }
}

/// Where an indicator is drawn.
public enum IndicatorPane: Hashable, Sendable {
    /// Overlaid on the candles, sharing the price scale.
    case price
    /// A separate pane below the price, with its own vertical scale.
    case separate(preferredHeight: Double = 90)
}

/// Grouping for the indicator picker.
public enum IndicatorCategory: String, Hashable, Sendable, CaseIterable, Codable {
    case movingAverage = "Moving Averages"
    case oscillator = "Oscillators"
    case volatility = "Volatility"
    case volume = "Volume"
    case trend = "Trend"
    case other = "Other"
}

/// Everything an indicator produces for one candle series.
public struct IndicatorResult: Hashable, Sendable {
    public var plots: [IndicatorPlot]
    public var fills: [IndicatorFill]
    public var levels: [IndicatorLevel]
    /// A scale range the pane should always include, regardless of the data — RSI pins to 0...100
    /// so the 30/70 levels stay meaningful even when the values never approach them. `nil` lets the
    /// pane autoscale to the values alone.
    public var preferredRange: ClosedRange<Double>?

    public init(
        plots: [IndicatorPlot],
        fills: [IndicatorFill] = [],
        levels: [IndicatorLevel] = [],
        preferredRange: ClosedRange<Double>? = nil
    ) {
        self.plots = plots
        self.fills = fills
        self.levels = levels
        self.preferredRange = preferredRange
    }

    /// The plot with this key, or `nil`.
    public func plot(_ key: String) -> IndicatorPlot? {
        plots.first { $0.key == key }
    }

    /// Every plot's value at `index`, for the crosshair readout.
    public func values(at index: Int) -> [(name: String, value: Double?)] {
        plots.compactMap { plot in
            guard case .hidden = plot.style else {
                return (plot.name, index < plot.values.count ? plot.values[index] : nil)
            }
            return nil
        }
    }
}
