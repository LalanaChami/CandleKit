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

    public init(
        upColor: Color = .green,
        downColor: Color = .red,
        hollowUpCandles: Bool = false,
        bodyWidthRatio: CGFloat = 0.7,
        volumeOpacity: Double = 0.28,
        gridColor: Color = Color.secondary.opacity(0.14),
        axisLabelColor: Color = .secondary,
        crosshairColor: Color = Color.primary.opacity(0.55)
    ) {
        self.upColor = upColor
        self.downColor = downColor
        self.hollowUpCandles = hollowUpCandles
        self.bodyWidthRatio = min(max(bodyWidthRatio, 0.1), 1)
        self.volumeOpacity = volumeOpacity
        self.gridColor = gridColor
        self.axisLabelColor = axisLabelColor
        self.crosshairColor = crosshairColor
    }

    /// Green for rising, red for falling.
    public static var standard: CandleChartStyle { CandleChartStyle() }

    /// Red for rising, green for falling, the convention in markets such as mainland China, Taiwan and South Korea.
    public static var redUp: CandleChartStyle { CandleChartStyle(upColor: .red, downColor: .green) }

    /// Blue and orange, which stay distinguishable for the most common forms of color blindness.
    public static var colorBlindSafe: CandleChartStyle { CandleChartStyle(upColor: .blue, downColor: .orange) }
}

/// A line overlay drawn on top of the candles.
public struct ChartIndicator: Hashable {
    public var kind: IndicatorKind
    public var color: Color
    public var lineWidth: CGFloat

    public init(_ kind: IndicatorKind, color: Color, lineWidth: CGFloat = 1.5) {
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
    }

    public static func sma(_ period: Int, color: Color = .orange, lineWidth: CGFloat = 1.5) -> ChartIndicator {
        ChartIndicator(.sma(period: period), color: color, lineWidth: lineWidth)
    }

    public static func ema(_ period: Int, color: Color = .purple, lineWidth: CGFloat = 1.5) -> ChartIndicator {
        ChartIndicator(.ema(period: period), color: color, lineWidth: lineWidth)
    }
}
#endif
