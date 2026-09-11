import Foundation

/// An overlay computed from candle closes.
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

public enum MovingAverage {
    /// Simple moving average in a single O(n) pass using a running sum.
    public static func simple(_ values: [Double], period: Int) -> [Double?] {
        var result = [Double?](repeating: nil, count: values.count)
        guard period > 0, values.count >= period else { return result }
        var sum = 0.0
        for index in values.indices {
            sum += values[index]
            if index >= period {
                sum -= values[index - period]
            }
            if index >= period - 1 {
                result[index] = sum / Double(period)
            }
        }
        return result
    }

    /// Exponential moving average seeded with the simple average of the first `period` values.
    public static func exponential(_ values: [Double], period: Int) -> [Double?] {
        var result = [Double?](repeating: nil, count: values.count)
        guard period > 0, values.count >= period else { return result }
        let alpha = 2.0 / Double(period + 1)
        var average = values[0..<period].reduce(0, +) / Double(period)
        result[period - 1] = average
        for index in period..<values.count {
            average += alpha * (values[index] - average)
            result[index] = average
        }
        return result
    }
}

/// Keeps indicator values between renders so panning and zooming never recompute them.
///
/// Values are recomputed only when the candle array changes. Comparing an unchanged array is O(1)
/// because Swift arrays short-circuit equality when both share the same storage.
public struct IndicatorCache: Sendable {
    private var source: [Candle] = []
    private var storage: [IndicatorKind: [Double?]] = [:]
    /// Number of full computations performed. Exposed for tests.
    public private(set) var computations = 0

    public init() {}

    public mutating func series(for kinds: [IndicatorKind], candles: [Candle]) -> [[Double?]] {
        if candles != source {
            storage.removeAll(keepingCapacity: true)
            source = candles
        }
        if storage.count > kinds.count {
            let wanted = Set(kinds)
            storage = storage.filter { wanted.contains($0.key) }
        }
        return kinds.map { kind in
            if let cached = storage[kind] {
                return cached
            }
            let computed = kind.values(for: candles)
            storage[kind] = computed
            computations += 1
            return computed
        }
    }
}
