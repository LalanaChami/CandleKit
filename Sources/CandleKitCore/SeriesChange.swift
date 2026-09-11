import Foundation

/// A cheap fingerprint of a series, used to work out how the data changed between renders.
public struct SeriesSummary: Hashable, Sendable {
    public let count: Int
    public let firstTime: Date?
    public let lastTime: Date?

    public init(_ candles: [Candle]) {
        count = candles.count
        firstTime = candles.first?.time
        lastTime = candles.last?.time
    }
}

/// How a series changed since the previous render.
public enum SeriesChange: Hashable, Sendable {
    /// First time the chart has seen data.
    case initial
    /// Same range of candles. The last candle may have been updated in place.
    case unchanged
    /// The old series is still present, with older candles added before it and/or newer ones after it.
    case extended(prepended: Int, appended: Int)
    /// The old series is no longer a contiguous part of the new one (for example, a symbol switch).
    case replaced

    public static func between(_ previous: SeriesSummary?, _ candles: [Candle]) -> SeriesChange {
        guard let previous else { return .initial }
        guard previous.count > 0, let oldFirst = previous.firstTime, let oldLast = previous.lastTime else {
            return candles.isEmpty ? .unchanged : .replaced
        }
        guard !candles.isEmpty else { return .replaced }

        let prepended = candles.lowerBoundIndex(for: oldFirst)
        guard prepended < candles.count, candles[prepended].time == oldFirst else { return .replaced }

        let oldLastIndex = prepended + previous.count - 1
        guard oldLastIndex < candles.count, candles[oldLastIndex].time == oldLast else { return .replaced }

        let appended = candles.count - oldLastIndex - 1
        if prepended == 0 && appended == 0 { return .unchanged }
        return .extended(prepended: prepended, appended: appended)
    }
}

extension Viewport {
    /// Adjusts the viewport so the same candles stay under the user's finger when data changes.
    ///
    /// Prepending history shifts every index, so the right edge moves by the same amount.
    /// Appending only scrolls if the newest candle was already on screen, like TradingView.
    public mutating func apply(_ change: SeriesChange, previousCount: Int, newCount: Int, rightPadding: Double) {
        switch change {
        case .unchanged:
            break
        case .initial, .replaced:
            self = .latest(count: newCount, spacing: spacing, rightPadding: rightPadding)
        case let .extended(prepended, appended):
            let wasFollowing = isShowingLatest(count: previousCount)
            rightEdge += Double(prepended)
            if wasFollowing {
                rightEdge += Double(appended)
            }
        }
    }
}
