import Foundation

/// How much of a date a time-axis label should show.
public enum TimeLabelUnit: Int, Hashable, Sendable, Comparable {
    case time
    case day
    case month
    case year

    public static func < (lhs: TimeLabelUnit, rhs: TimeLabelUnit) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct TimeTick: Hashable, Sendable {
    public let index: Int
    public let date: Date
    public let unit: TimeLabelUnit
}

public enum TimeScale {
    /// The typical gap between candles (median of recent gaps), so weekend gaps don't skew it.
    public static func estimatedInterval(of candles: [Candle]) -> TimeInterval {
        guard candles.count > 1 else { return 60 }
        let end = candles.count - 1
        let start = max(0, end - 50)
        var gaps: [TimeInterval] = []
        gaps.reserveCapacity(end - start)
        for index in start..<end {
            let gap = candles[index + 1].time.timeIntervalSince(candles[index].time)
            if gap > 0 { gaps.append(gap) }
        }
        guard !gaps.isEmpty else { return 60 }
        gaps.sort()
        return gaps[gaps.count / 2]
    }

    /// The default label unit for a candle interval.
    public static func baseUnit(forInterval interval: TimeInterval) -> TimeLabelUnit {
        switch interval {
        case ..<86_400: return .time
        case ..<(28 * 86_400): return .day
        case ..<(365 * 86_400): return .month
        default: return .year
        }
    }

    private static let strideSteps = [1, 2, 3, 5, 10, 15, 20, 30, 50, 60, 100, 120, 200, 250, 500]

    /// The smallest "nice" number of candles between labels that keeps labels `minimumLabelSpacing` apart.
    public static func labelStride(spacing: Double, minimumLabelSpacing: Double) -> Int {
        guard spacing > 0, minimumLabelSpacing.isFinite else { return 1 }
        let needed = minimumLabelSpacing / spacing
        var multiplier = 1
        while multiplier < 1_000_000_000 {
            for step in strideSteps where Double(step * multiplier) >= needed {
                return step * multiplier
            }
            multiplier *= 10
        }
        return strideSteps[strideSteps.count - 1] * multiplier
    }

    /// Label positions for the visible candles.
    ///
    /// Ticks sit on absolute multiples of the stride, so they stay put while panning. A label is promoted
    /// to a coarser unit when it crosses a boundary: a new day on an intraday chart, a new month on a daily chart.
    public static func ticks(
        for candles: [Candle],
        in visible: Range<Int>,
        spacing: Double,
        minimumLabelSpacing: Double = 90,
        calendar: Calendar = .current
    ) -> [TimeTick] {
        let visible = visible.clamped(to: 0..<candles.count)
        guard !visible.isEmpty else { return [] }

        let labelEvery = labelStride(spacing: spacing, minimumLabelSpacing: minimumLabelSpacing)
        let base = baseUnit(forInterval: estimatedInterval(of: candles))
        let firstTick = (visible.lowerBound + labelEvery - 1) / labelEvery * labelEvery

        var ticks: [TimeTick] = []
        for index in stride(from: firstTick, to: visible.upperBound, by: labelEvery) {
            let date = candles[index].time
            var unit = base
            if index - labelEvery >= 0 {
                unit = max(base, changedUnit(from: candles[index - labelEvery].time, to: date, calendar: calendar))
            }
            ticks.append(TimeTick(index: index, date: date, unit: unit))
        }
        return ticks
    }

    static func changedUnit(from previous: Date, to date: Date, calendar: Calendar) -> TimeLabelUnit {
        let before = calendar.dateComponents([.year, .month, .day], from: previous)
        let after = calendar.dateComponents([.year, .month, .day], from: date)
        if before.year != after.year { return .year }
        if before.month != after.month { return .month }
        if before.day != after.day { return .day }
        return .time
    }
}
