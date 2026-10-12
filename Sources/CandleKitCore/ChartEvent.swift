import Foundation

/// Something that happened at a point in time and might explain a move: earnings, a dividend, a
/// split, a news item or anything of your own (roadmap 9.2).
public struct ChartEvent: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case earnings
        case dividend
        case split
        case news
        case custom

        /// A one-letter glyph for the marker: E, D, S, N, or a dot for custom.
        public var symbol: String {
            switch self {
            case .earnings: return "E"
            case .dividend: return "D"
            case .split: return "S"
            case .news: return "N"
            case .custom: return "•"
            }
        }

        /// Spoken name, used for accessibility.
        public var spokenName: String {
            switch self {
            case .earnings: return "Earnings"
            case .dividend: return "Dividend"
            case .split: return "Split"
            case .news: return "News"
            case .custom: return "Event"
            }
        }
    }

    public var id: UUID
    public var time: Date
    public var kind: Kind
    /// Short text, e.g. "Q3 earnings".
    public var title: String
    /// Optional longer text for the app to show when the marker is tapped.
    public var detail: String?

    public init(id: UUID = UUID(), time: Date, kind: Kind, title: String, detail: String? = nil) {
        self.id = id
        self.time = time
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

/// One marker on screen: the events it stands for and the candle it sits over.
public struct ChartEventCluster: Hashable, Sendable, Identifiable {
    /// Candle index the marker is drawn over (the first candle of a merged group).
    public var candleIndex: Int
    /// Events behind this marker, oldest first. More than one when events share a candle or are
    /// merged because the chart is zoomed out.
    public var events: [ChartEvent]

    public var id: Int { candleIndex }
    /// The event whose glyph is drawn: the first one.
    public var primary: ChartEvent { events[0] }
}

/// Maps events onto candles and merges ones that would overlap. Pure and tested.
public enum EventMarkerLayout {
    /// The candle that was trading at `time`: the last candle that opened at or before it. `nil` when
    /// the time is before the first candle or after the end of the last (one `interval` past its
    /// open), since such an event isn't on this chart.
    public static func candleIndex(for time: Date, in candles: [Candle], interval: TimeInterval) -> Int? {
        guard let first = candles.first, let last = candles.last, time >= first.time else { return nil }
        if time >= last.time {
            return time < last.time.addingTimeInterval(max(interval, 0)) ? candles.count - 1 : nil
        }
        // First candle strictly after `time`, minus one.
        var low = 0
        var high = candles.count
        while low < high {
            let mid = (low + high) / 2
            if candles[mid].time <= time { low = mid + 1 } else { high = mid }
        }
        return low - 1
    }

    /// Markers for the events on candles in `visible`.
    ///
    /// - Parameters:
    ///   - events: any order; sorted internally.
    ///   - candles: the series.
    ///   - visible: candle indices to place markers for (extend by a couple of candles at the edges
    ///     so a marker doesn't pop in).
    ///   - interval: the candle interval, to decide whether an event after the last candle still counts.
    ///   - spacing: points per candle.
    ///   - minimumGap: smallest distance in points between two markers; nearer ones merge.
    public static func clusters(
        events: [ChartEvent],
        candles: [Candle],
        visible: Range<Int>,
        interval: TimeInterval,
        spacing: Double,
        minimumGap: Double
    ) -> [ChartEventCluster] {
        guard !events.isEmpty, !candles.isEmpty, !visible.isEmpty, spacing > 0 else { return [] }
        // Group by candle first (events sharing a candle always stack).
        var byCandle: [Int: [ChartEvent]] = [:]
        for event in events {
            guard let index = candleIndex(for: event.time, in: candles, interval: interval), visible.contains(index) else { continue }
            byCandle[index, default: []].append(event)
        }
        let indices = byCandle.keys.sorted()
        let minimumSlots = max(1, Int((minimumGap / spacing).rounded(.up)))
        var result: [ChartEventCluster] = []
        var lastIndexInCluster = Int.min
        for index in indices {
            let group = (byCandle[index] ?? []).sorted { $0.time < $1.time }
            if !result.isEmpty, index - lastIndexInCluster < minimumSlots {
                result[result.count - 1].events.append(contentsOf: group)
            } else {
                result.append(ChartEventCluster(candleIndex: index, events: group))
            }
            lastIndexInCluster = index
        }
        return result
    }
}
