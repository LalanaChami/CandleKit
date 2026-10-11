import Foundation

/// How a comparison chart's price axis is expressed (roadmap 7.6).
public enum ComparisonNormalization: Hashable, Sendable {
    /// Each value as the percent change from the first visible candle's close: `+2.5` means +2.5%.
    case percentChange
    /// Each value as an index that starts at 100 on the first visible candle: `102.5` means +2.5%.
    case indexed100
}

/// Lines up another series with the primary series' candles.
public enum SeriesAlignment {
    /// One value per primary candle: the most recent close of `other` at or before that candle's
    /// time, or `nil` where `other` has nothing honest to say.
    ///
    /// `nil` is returned before `other` starts and when the latest `other` close is more than
    /// `maxGap` seconds old, so a market that was closed (a holiday, a different trading calendar)
    /// shows as a break rather than a flat invented line. By default `maxGap` is three times
    /// `other`'s typical candle interval.
    ///
    /// Both series must be sorted by time. Runs in O(primary + other).
    public static func align(
        primary: [Candle],
        other: [Candle],
        maxGap: TimeInterval? = nil
    ) -> [Double?] {
        guard !primary.isEmpty else { return [] }
        guard !other.isEmpty else { return Array(repeating: nil, count: primary.count) }
        let limit = maxGap ?? 3 * TimeScale.estimatedInterval(of: other)
        var result: [Double?] = []
        result.reserveCapacity(primary.count)
        var cursor = 0
        for candle in primary {
            while cursor + 1 < other.count, other[cursor + 1].time <= candle.time {
                cursor += 1
            }
            let source = other[cursor]
            if source.time > candle.time || candle.time.timeIntervalSince(source.time) > limit {
                result.append(nil)
            } else {
                result.append(source.close)
            }
        }
        return result
    }
}

/// How aligned comparison series map onto the primary series' price scale for one visible range.
///
/// Each comparison series is multiplied by a constant so that it starts exactly on the primary's
/// price where it first appears on screen. Because that is a single multiplication, the chart's
/// ordinary linear price scale can draw everything, and only the axis labels need converting.
public struct ComparisonScaling: Hashable, Sendable {
    public var normalization: ComparisonNormalization
    /// The primary series' close at the first visible candle: 0% (or 100) on the axis.
    public var base: Double
    /// One multiplier per comparison series, or `nil` for a series with no value in view.
    public var factors: [Double?]

    public init(normalization: ComparisonNormalization, base: Double, factors: [Double?]) {
        self.normalization = normalization
        self.base = base
        self.factors = factors
    }

    /// The axis number (percent change or index) that a primary-scale price stands for.
    public func axisValue(forPrice price: Double) -> Double {
        switch normalization {
        case .percentChange: return (price / base - 1) * 100
        case .indexed100: return price / base * 100
        }
    }

    /// The inverse of ``axisValue(forPrice:)``.
    public func price(forAxisValue value: Double) -> Double {
        switch normalization {
        case .percentChange: return base * (1 + value / 100)
        case .indexed100: return base * value / 100
        }
    }
}

public enum ComparisonMath {
    /// Works out the scaling for the candles currently on screen.
    ///
    /// The axis base is the primary close at `visible.lowerBound`. A comparison series is anchored
    /// at its first value inside `visible`, where it is made equal to the primary's close; a series
    /// with no value inside `visible` gets a `nil` factor. Returns `nil` when there is no usable
    /// positive base, in which case the chart should fall back to plain prices.
    ///
    /// Cost is O(visible), not O(series length).
    public static func scaling(
        primary: [Candle],
        aligned: [[Double?]],
        visible: Range<Int>,
        normalization: ComparisonNormalization
    ) -> ComparisonScaling? {
        let range = visible.clamped(to: 0..<primary.count)
        guard let first = range.first else { return nil }
        let base = primary[first].close
        guard base.isFinite, base > 0 else { return nil }

        var factors: [Double?] = []
        factors.reserveCapacity(aligned.count)
        for values in aligned {
            var factor: Double?
            for index in range where index < values.count {
                guard let value = values[index], value.isFinite, value > 0 else { continue }
                let anchor = primary[index].close
                if anchor.isFinite, anchor > 0 {
                    factor = anchor / value
                }
                break
            }
            factors.append(factor)
        }
        return ComparisonScaling(normalization: normalization, base: base, factors: factors)
    }

    /// The lowest and highest rescaled value of one series over `range`, or `nil` if it has none.
    public static func extent(of values: [Double?], factor: Double, in range: Range<Int>) -> ClosedRange<Double>? {
        var low = Double.infinity
        var high = -Double.infinity
        for index in range.clamped(to: 0..<values.count) {
            guard let value = values[index], value.isFinite else { continue }
            let scaled = value * factor
            low = min(low, scaled)
            high = max(high, scaled)
        }
        guard low.isFinite, high.isFinite else { return nil }
        return low...high
    }
}
