import Foundation

/// One OHLCV bar.
///
/// Series passed to the chart must be sorted by `time` in ascending order, with no duplicate times.
public struct Candle: Hashable, Sendable, Identifiable {
    public var time: Date
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double
    public var volume: Double

    public init(time: Date, open: Double, high: Double, low: Double, close: Double, volume: Double = 0) {
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }

    public var id: Date { time }

    /// `true` when the candle closed at or above its open.
    public var isBullish: Bool { close >= open }
}

extension Array where Element == Candle {
    /// Index of the first candle whose time is not earlier than `time`, found by binary search.
    func lowerBoundIndex(for time: Date) -> Int {
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            if self[mid].time < time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
