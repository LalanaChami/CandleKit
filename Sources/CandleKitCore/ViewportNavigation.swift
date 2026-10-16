import Foundation

/// Where a candle sits in the plot after a programmatic scroll (roadmap 4.5).
public enum ViewportAlignment: String, Sendable, Hashable, CaseIterable {
    /// The candle's slot starts at the left edge of the plot.
    case leading
    /// The candle is in the middle of the plot.
    case center
    /// The candle's slot ends at the right edge of the plot.
    case trailing
}

/// Pure maths behind `CandleChartState.scroll(to:)` and friends, kept in Core so it is tested without a screen.
public enum ViewportNavigation {
    /// Index of the candle closest in time to `date`, or `nil` for an empty series. Dates before the
    /// first candle give 0 and after the last give `count - 1`. Binary search, so it's cheap on long
    /// series. Requires the sorted-ascending contract the chart already relies on.
    public static func nearestIndex(to date: Date, in candles: [Candle]) -> Int? {
        guard !candles.isEmpty else { return nil }
        let upper = candles.lowerBoundIndex(for: date)   // first candle not before `date`
        if upper == 0 { return 0 }
        if upper == candles.count { return candles.count - 1 }
        let before = date.timeIntervalSince(candles[upper - 1].time)
        let after = candles[upper].time.timeIntervalSince(date)
        return before <= after ? upper - 1 : upper
    }

    /// The `rightEdge` that puts candle `index` at `alignment` in a plot `width` points wide.
    public static func rightEdge(
        forCandle index: Int,
        alignment: ViewportAlignment,
        width: Double,
        spacing: Double
    ) -> Double {
        guard spacing > 0, width > 0 else { return Double(index) + 1 }
        let slots = width / spacing
        switch alignment {
        case .leading: return Double(index) + slots
        case .center: return Double(index) + 0.5 + slots / 2
        case .trailing: return Double(index) + 1
        }
    }

    /// The candle spacing that shows `count` candles across `width` points, clamped to `limits`.
    public static func spacing(forVisibleCount count: Int, width: Double, limits: ZoomLimits) -> Double {
        guard count > 0, width > 0 else { return limits.minimumSpacing }
        return limits.clamp(width / Double(count))
    }

    /// Times of the first and last candles at least partly visible, or `nil` when none are.
    public static func visibleTimes(candles: [Candle], viewport: Viewport, width: Double) -> ClosedRange<Date>? {
        let range = viewport.visibleRange(width: width, count: candles.count)
        guard let first = range.first, let last = range.last else { return nil }
        return candles[first].time...candles[last].time
    }
}
