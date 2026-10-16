import Foundation

/// How a series is drawn (roadmap 4.6).
///
/// Everything except `.heikinAshi` is purely a drawing choice over the same candles. Heikin-Ashi
/// changes the *values* shown (see ``HeikinAshi``), so the header and crosshair read the smoothed
/// bars, as they do on most trading platforms.
public enum ChartSeriesType: String, Sendable, Codable, CaseIterable, Hashable {
    /// Open/high/low/close bodies and wicks. The default.
    case candles
    /// A vertical high-low bar with a tick to the left for the open and to the right for the close.
    case ohlcBars
    /// A line through the closing prices.
    case line
    /// A line through the closing prices with a fill beneath it.
    case area
    /// Smoothed candles that make trends easier to read. See ``HeikinAshi``.
    case heikinAshi

    /// `true` for the types drawn as a single close-price line rather than per-candle shapes.
    public var isCloseLine: Bool { self == .line || self == .area }
}

/// Heikin-Ashi ("average bar") transform.
///
/// - close = (open + high + low + close) / 4
/// - open = the midpoint of the previous Heikin-Ashi open and close (the first bar uses the real
///   open and close)
/// - high = the largest of the real high, the new open and the new close
/// - low = the smallest of the real low, the new open and the new close
///
/// Times and volumes are kept. Each bar depends on the one before it, so a change anywhere shifts
/// every later bar; `transform(_:reusing:)` exploits that the chart only ever changes the last
/// candle in place.
public enum HeikinAshi {
    /// Transforms a whole series. O(n).
    public static func transform(_ candles: [Candle]) -> [Candle] {
        var result: [Candle] = []
        result.reserveCapacity(candles.count)
        for candle in candles {
            result.append(bar(for: candle, after: result.last))
        }
        return result
    }

    /// Transforms `candles`, reusing `previous` (the output of an earlier call for `previousInput`)
    /// when only the last candle changed or candles were appended. Falls back to a full transform
    /// otherwise, so the result always equals `transform(candles)`.
    public static func transform(_ candles: [Candle], reusing previous: [Candle], previousInput: [Candle]) -> [Candle] {
        let shared = min(previousInput.count, candles.count)
        // The first `keep` bars are still valid when the inputs agree up to there. Spot-checks the
        // first and last shared candle instead of comparing everything, since the data contract says
        // only the last candle changes in place.
        var keep = 0
        if shared > 0, previous.count == previousInput.count, previousInput[0] == candles[0] {
            // The common case: everything but the in-progress last candle is unchanged.
            keep = shared - 1
            if keep > 0, previousInput[keep - 1] != candles[keep - 1] { keep = 0 }
        }
        guard keep > 0 else { return transform(candles) }
        var result = Array(previous.prefix(keep))
        result.reserveCapacity(candles.count)
        for index in keep..<candles.count {
            result.append(bar(for: candles[index], after: result.last))
        }
        return result
    }

    private static func bar(for candle: Candle, after previous: Candle?) -> Candle {
        let close = (candle.open + candle.high + candle.low + candle.close) / 4
        let open = previous.map { ($0.open + $0.close) / 2 } ?? (candle.open + candle.close) / 2
        return Candle(
            time: candle.time,
            open: open,
            high: max(candle.high, open, close),
            low: min(candle.low, open, close),
            close: close,
            volume: candle.volume
        )
    }
}
