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
    /// Turns on the frosted price axis, and lets candles show through it, softly blurred, as they
    /// scroll toward the edge. `nil` (the default) keeps the classic fully transparent axis,
    /// unchanged from earlier versions.
    ///
    /// The panel is a `Material` fill (`.ultraThinMaterial` is a reasonable starting point),
    /// blended toward the system background colour and dimmed slightly further for extra
    /// translucency, then feathered on three edges so it dissolves into the chart rather than
    /// presenting a hard-edged, distinctly-coloured box — `Material` alone carries its own neutral
    /// tint regardless of what's behind it, which read as a panel that didn't belong with its
    /// surroundings. An iOS 26 build using the real Liquid Glass API (`glassEffect`) was tried and
    /// reverted after real device screenshots showed it producing visible colour-tinted glow
    /// artefacts on this tall, edge-spanning shape — not something safely tunable without a device
    /// in hand, so this fell back to the simpler, well-understood primitive. Worth revisiting later.
    ///
    /// Setting this also lets candles extend further underneath the axis (see
    /// `ChartMetrics.priceAxisOverlap`) — with nothing set there'd be nothing keeping the tick
    /// labels legible against candles moving underneath, so the two always change together.
    public var priceAxisMaterial: Material?
    /// How much duller every candle *other than* the focused one gets while the crosshair is
    /// showing, so the focused candle's glow actually draws the eye instead of competing with a
    /// full-brightness chart around it. `0` disables dulling entirely, keeping only the glow.
    /// Only candles are affected — the reduction lowers each non-focused candle's own fill opacity
    /// (so it blends toward whatever's behind it) rather than laying a gray overlay across the
    /// background, grid, volume bars, or indicator lines, none of which dim.
    public var crosshairDimOpacity: Double

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
        self.priceAxisMaterial = priceAxisMaterial
        self.crosshairDimOpacity = min(max(crosshairDimOpacity, 0), 1)
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

    // MARK: Tier 2

    public static func donchianChannels(period: Int = 20) -> ChartIndicator {
        ChartIndicator(DonchianChannelsIndicator(period: period))
    }

    public static func keltnerChannels(period: Int = 20, atrPeriod: Int = 10, multiplier: Double = 2) -> ChartIndicator {
        ChartIndicator(KeltnerChannelsIndicator(period: period, atrPeriod: atrPeriod, multiplier: multiplier))
    }

    public static func superTrend(period: Int = 10, multiplier: Double = 3) -> ChartIndicator {
        ChartIndicator(SuperTrendIndicator(period: period, multiplier: multiplier))
    }

    public static func parabolicSAR(step: Double = 0.02, maximum: Double = 0.2) -> ChartIndicator {
        ChartIndicator(ParabolicSARIndicator(step: step, maximum: maximum))
    }

    public static func ichimokuCloud(
        conversionPeriod: Int = 9,
        basePeriod: Int = 26,
        spanBPeriod: Int = 52,
        displacement: Int = 26
    ) -> ChartIndicator {
        ChartIndicator(IchimokuCloudIndicator(
            conversionPeriod: conversionPeriod, basePeriod: basePeriod,
            spanBPeriod: spanBPeriod, displacement: displacement
        ))
    }

    public static func pivotPoints(method: IndicatorMath.PivotMethod = .classic) -> ChartIndicator {
        ChartIndicator(PivotPointsIndicator(method: method))
    }

    public static func adx(_ period: Int = 14) -> ChartIndicator {
        ChartIndicator(ADXIndicator(period: period))
    }

    public static func cci(_ period: Int = 20) -> ChartIndicator {
        ChartIndicator(CCIIndicator(period: period))
    }

    public static func mfi(_ period: Int = 14) -> ChartIndicator {
        ChartIndicator(MFIIndicator(period: period))
    }

    public static func williamsR(_ period: Int = 14) -> ChartIndicator {
        ChartIndicator(WilliamsRIndicator(period: period))
    }

    public static func rateOfChange(period: Int = 12, mode: ROCIndicator.Mode = .percentage) -> ChartIndicator {
        ChartIndicator(ROCIndicator(period: period, mode: mode))
    }

    public static func chaikinMoneyFlow(_ period: Int = 20) -> ChartIndicator {
        ChartIndicator(ChaikinMoneyFlowIndicator(period: period))
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
