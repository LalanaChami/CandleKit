import Foundation

// The primitive roadmap 9.3 asks for, and stops there deliberately — see docs/ROADMAP.md's "What
// CandleKit deliberately will not become": no built-in alerting system, no notification
// scheduling, no persisted watchlist. This just answers "did the price cross this level," between
// the two most recent candles a series holds; an app wires its own notification, persistence and
// UI to it. Pure Foundation, so it costs nothing to test and works whether or not a
// `CandlestickChart` is even on screen.

/// Which way a level was crossed.
public enum PriceCrossDirection: Sendable, Equatable {
    /// The close moved from below the level to at-or-above it.
    case upward
    /// The close moved from above the level to at-or-below it.
    case downward
}

/// One detected crossing: which level, which way, and the candle it happened on.
public struct PriceCrossing: Sendable, Equatable {
    public let level: Double
    public let direction: PriceCrossDirection
    /// The more recent of the two candles compared — the one where the cross became true.
    public let candle: Candle

    public init(level: Double, direction: PriceCrossDirection, candle: Candle) {
        self.level = level
        self.direction = direction
        self.candle = candle
    }
}

/// Which of `levels`, if any, were crossed between the last two candles in `candles`, comparing
/// closing prices: `level` is crossed **upward** when `previous.close < level <= current.close`,
/// and **downward** when `previous.close > level >= current.close`. A `level` sitting exactly on
/// both closes (no movement at all) never counts, and a `level` outside both closes' range never
/// counts either — only one that the price actually moved through.
///
/// Works the same way for a newly appended candle and for a live tick updating the last candle in
/// place, because it only ever looks at the two most recent entries — matching the data contract
/// documented on `Candle` and `CandlestickChart` ("only the last candle is expected to change in
/// place"). Call this again after every update to `candles`, not just once; a level that was
/// crossed on the previous tick and isn't anymore should be reported again on the tick that
/// re-crosses it.
///
/// Returns an empty array (never crashes) when `candles` has fewer than two entries.
public func priceCrossings(in candles: [Candle], levels: [Double]) -> [PriceCrossing] {
    guard candles.count >= 2, !levels.isEmpty else { return [] }
    let previous = candles[candles.count - 2]
    let current = candles[candles.count - 1]

    var crossings: [PriceCrossing] = []
    for level in levels {
        if previous.close < level, current.close >= level {
            crossings.append(PriceCrossing(level: level, direction: .upward, candle: current))
        } else if previous.close > level, current.close <= level {
            crossings.append(PriceCrossing(level: level, direction: .downward, candle: current))
        }
    }
    return crossings
}
