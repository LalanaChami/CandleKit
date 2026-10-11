import Foundation

/// Turns elapsed time into whole candles to reveal during replay (roadmap 9.4).
///
/// Feed it the time since the previous tick and the current speed. It returns how many candles to
/// add now and keeps the fractional remainder, so 2.5 candles per second plays out as 2, 3, 2, 3…
/// per second rather than drifting or stalling, and changing the speed mid-play loses nothing.
public struct ReplayClock: Sendable, Equatable {
    /// The part of a candle already earned but not yet revealed, in `0..<1`.
    public private(set) var remainder: Double = 0

    public init() {}

    /// - Parameters:
    ///   - elapsed: Seconds since the last call. Non-positive or non-finite values add nothing.
    ///   - candlesPerSecond: The current speed. Non-positive or non-finite values add nothing.
    /// - Returns: Whole candles to reveal now.
    public mutating func advance(by elapsed: TimeInterval, candlesPerSecond: Double) -> Int {
        guard elapsed.isFinite, elapsed > 0, candlesPerSecond.isFinite, candlesPerSecond > 0 else { return 0 }
        let earned = remainder + elapsed * candlesPerSecond
        // A stalled app can hand over a huge `elapsed`; cap it so the conversion can't overflow.
        let whole = min(earned.rounded(.down), 1_000_000_000)
        remainder = earned - earned.rounded(.down)
        return Int(whole)
    }

    public mutating func reset() {
        remainder = 0
    }
}

public enum ReplayMath {
    /// How many candles to show: `position` limited to `minimum...count`, or all `count` when there
    /// are fewer than `minimum` candles. Returns 0 for an empty series.
    public static func visibleCount(position: Int, count: Int, minimum: Int = 2) -> Int {
        guard count > 0 else { return 0 }
        return min(max(position, min(minimum, count)), count)
    }
}
