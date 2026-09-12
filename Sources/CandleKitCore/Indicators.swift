import Foundation

/// An overlay computed from candle closes.
///
/// Superseded by the ``Indicator`` protocol, which can express multi-line indicators, histograms,
/// fills, reference levels and separate panes. Kept so existing code keeps working; new indicators
/// should conform to ``Indicator`` and be registered in an ``IndicatorCatalog``.
@available(*, deprecated, message: "Conform to `Indicator` instead; see `MovingAverageIndicator`.")
public enum IndicatorKind: Hashable, Sendable {
    case sma(period: Int)
    case ema(period: Int)

    public var label: String {
        switch self {
        case let .sma(period): return "SMA \(period)"
        case let .ema(period): return "EMA \(period)"
        }
    }

    /// One value per candle; `nil` until enough candles exist for the period.
    public func values(for candles: [Candle]) -> [Double?] {
        let closes = candles.map(\.close)
        switch self {
        case let .sma(period): return MovingAverage.simple(closes, period: period)
        case let .ema(period): return MovingAverage.exponential(closes, period: period)
        }
    }
}

/// Superseded by ``IndicatorMath``, which documents the convention each function implements.
@available(*, deprecated, message: "Use `IndicatorMath` instead.")
public enum MovingAverage {
    /// Simple moving average. Delegates to ``IndicatorMath/sma(_:period:)``.
    public static func simple(_ values: [Double], period: Int) -> [Double?] {
        IndicatorMath.sma(values, period: period)
    }

    /// Exponential moving average. Delegates to ``IndicatorMath/ema(_:period:)``.
    public static func exponential(_ values: [Double], period: Int) -> [Double?] {
        IndicatorMath.ema(values, period: period)
    }
}
