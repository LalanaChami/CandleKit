#if os(iOS)
import SwiftUI

/// Visual configuration for ``CandlestickChart``.
///
/// Defaults use semantic system colors, so the chart adapts to light mode, dark mode and increased contrast.
public struct CandleChartStyle {
    public var upColor: Color
    public var downColor: Color
    /// Draws rising candles as outlines.
    public var hollowUpCandles: Bool
    /// Candle body width as a fraction of the slot width.
    public var bodyWidthRatio: CGFloat
    public var volumeOpacity: Double
    public var gridColor: Color
    public var axisLabelColor: Color
    public var crosshairColor: Color
    /// Colours that `IndicatorColorRole.series(_:)` indexes into. Indicators cycle through it, so
    /// two overlays added back to back are visually distinct without the app choosing colours.
    public var indicatorPalette: [Color]

    public init(
        upColor: Color = .green,
        downColor: Color = .red,
        hollowUpCandles: Bool = false,
        bodyWidthRatio: CGFloat = 0.7,
        volumeOpacity: Double = 0.28,
        gridColor: Color = Color.secondary.opacity(0.14),
        axisLabelColor: Color = .secondary,
        crosshairColor: Color = Color.primary.opacity(0.55),
        indicatorPalette: [Color] = [.orange, .purple, .teal, .pink, .indigo, .brown]
    ) {
        self.upColor = upColor
        self.downColor = downColor
        self.hollowUpCandles = hollowUpCandles
        self.bodyWidthRatio = min(max(bodyWidthRatio, 0.1), 1)
        self.volumeOpacity = volumeOpacity
        self.gridColor = gridColor
        self.axisLabelColor = axisLabelColor
        self.crosshairColor = crosshairColor
        self.indicatorPalette = indicatorPalette
    }

    /// Green for rising, red for falling.
    public static var standard: CandleChartStyle { CandleChartStyle() }

    /// Red for rising, green for falling, the convention in markets such as mainland China, Taiwan and South Korea.
    public static var redUp: CandleChartStyle { CandleChartStyle(upColor: .red, downColor: .green) }

    /// Blue and orange, which stay distinguishable for the most common forms of color blindness.
    public static var colorBlindSafe: CandleChartStyle { CandleChartStyle(upColor: .blue, downColor: .orange) }
}

/// An indicator attached to a chart, with optional colour overrides.
///
/// Wraps any ``Indicator``, including one your app defines. The convenience factories below cover
/// the common cases:
///
/// ```swift
/// CandlestickChart(candles)
///     .indicators([.sma(20), .rsi(14), ChartIndicator(MyOwnIndicator())])
/// ```
public struct ChartIndicator: Identifiable {
    /// The indicator itself. Mutable so a settings UI can write edited parameters back.
    public var indicator: any Indicator
    /// Overrides for the palette this indicator's plots resolve `IndicatorColorRole.series(_:)`
    /// against. Empty uses the chart style's palette.
    public var colors: [Color]
    /// Overrides the width of every line plot. `nil` keeps each plot's own width.
    public var lineWidth: CGFloat?
    /// Hides the indicator without removing it, so a settings UI can offer a visibility toggle
    /// that preserves configuration.
    public var isVisible: Bool

    public init(
        _ indicator: any Indicator,
        colors: [Color] = [],
        lineWidth: CGFloat? = nil,
        isVisible: Bool = true
    ) {
        self.indicator = indicator
        self.colors = colors
        self.lineWidth = lineWidth
        self.isVisible = isVisible
    }

    /// Stable across renders, and distinct for two indicators of the same type with different
    /// settings, so SwiftUI and the indicator cache can both tell them apart.
    public var id: String { indicator.descriptor.id }

    /// Compact label for a legend — `"RSI 14"`.
    public var label: String { indicator.shortLabel }

    /// What a saved layout stores.
    public var descriptor: IndicatorDescriptor { indicator.descriptor }

    // MARK: Convenience factories

    public static func sma(_ period: Int, color: Color? = nil, lineWidth: CGFloat? = nil) -> ChartIndicator {
        ChartIndicator(
            MovingAverageIndicator(period: period, method: .simple),
            colors: color.map { [$0] } ?? [],
            lineWidth: lineWidth
        )
    }

    public static func ema(_ period: Int, color: Color? = nil, lineWidth: CGFloat? = nil) -> ChartIndicator {
        ChartIndicator(
            MovingAverageIndicator(period: period, method: .exponential),
            colors: color.map { [$0] } ?? [],
            lineWidth: lineWidth
        )
    }

    public static func wma(_ period: Int, color: Color? = nil, lineWidth: CGFloat? = nil) -> ChartIndicator {
        ChartIndicator(
            MovingAverageIndicator(period: period, method: .weighted),
            colors: color.map { [$0] } ?? [],
            lineWidth: lineWidth
        )
    }

    public static func bollingerBands(period: Int = 20, multiplier: Double = 2) -> ChartIndicator {
        ChartIndicator(BollingerBandsIndicator(period: period, multiplier: multiplier))
    }

    public static func vwap() -> ChartIndicator {
        ChartIndicator(VWAPIndicator())
    }

    public static func rsi(_ period: Int = 14) -> ChartIndicator {
        ChartIndicator(RSIIndicator(period: period))
    }

    public static func macd(fast: Int = 12, slow: Int = 26, signal: Int = 9) -> ChartIndicator {
        ChartIndicator(MACDIndicator(fastPeriod: fast, slowPeriod: slow, signalPeriod: signal))
    }

    public static func stochastic(period: Int = 14, smoothK: Int = 3, smoothD: Int = 3) -> ChartIndicator {
        ChartIndicator(StochasticIndicator(period: period, smoothK: smoothK, smoothD: smoothD))
    }

    public static func atr(_ period: Int = 14) -> ChartIndicator {
        ChartIndicator(ATRIndicator(period: period))
    }

    public static func obv() -> ChartIndicator {
        ChartIndicator(OBVIndicator())
    }
}

/// One indicator's computed output plus the colours its roles resolved to, ready to draw.
struct ResolvedIndicator: Identifiable {
    let id: String
    let label: String
    let pane: IndicatorPane
    let result: IndicatorResult
    let lineWidthOverride: CGFloat?
    /// Palette this indicator's `.series(_:)` roles index into.
    let palette: [Color]
    let style: CandleChartStyle

    func color(for role: IndicatorColorRole, value: Double? = nil) -> Color {
        switch role {
        case let .series(index):
            guard !palette.isEmpty else { return style.axisLabelColor }
            return palette[((index % palette.count) + palette.count) % palette.count]
        case .bullish:
            return style.upColor
        case .bearish:
            return style.downColor
        case .signed:
            return (value ?? 0) >= 0 ? style.upColor : style.downColor
        case .neutral:
            return style.gridColor
        case .custom:
            // Apps resolve their own roles by supplying `colors` on the ChartIndicator; without
            // that there is nothing sensible to map to, so fall back to the axis colour rather
            // than guessing.
            return style.axisLabelColor
        }
    }

    func width(for style: IndicatorPlotStyle) -> CGFloat {
        if let lineWidthOverride { return lineWidthOverride }
        switch style {
        case let .line(width, _): return CGFloat(width)
        case let .steppedLine(width): return CGFloat(width)
        default: return 1.5
        }
    }
}

#endif
