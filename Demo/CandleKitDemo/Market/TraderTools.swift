import CandleKit
import Foundation
import Observation

/// State for the demo's trader tools: series type, volume profile, anchored VWAP and event markers.
///
/// Kept in its own object so `MarketView` doesn't grow another `@State` per feature.
@MainActor
@Observable
final class TraderToolsModel {
    var seriesType: ChartSeriesType = .candles
    var showsVolumeProfile = false
    var showsEvents = false
    /// When non-nil, an anchored VWAP (with one-deviation bands) starts from this time.
    var vwapAnchor: Date?
    /// The marker the person tapped, shown in a sheet.
    var selectedCluster: ChartEventCluster?

    static func title(for type: ChartSeriesType) -> String {
        switch type {
        case .candles: return "Candles"
        case .ohlcBars: return "OHLC bars"
        case .line: return "Line"
        case .area: return "Area"
        case .heikinAshi: return "Heikin-Ashi"
        }
    }

    /// Simulated events for the demo: one roughly every 40 candles on a grid aligned to the clock,
    /// so markers stay put when a live tick arrives or older history is prepended. A real app
    /// would pass its own earnings, dividend and news calendar.
    nonisolated static func events(for candles: [Candle]) -> [ChartEvent] {
        guard candles.count > 2 else { return [] }
        let interval = max(candles[1].time.timeIntervalSince(candles[0].time), 1)
        let step = interval * 40
        let first = candles[0].time.timeIntervalSince1970
        let last = candles[candles.count - 1].time.timeIntervalSince1970
        let startIndex = Int((first / step).rounded(.down))
        let endIndex = Int((last / step).rounded(.down))
        guard endIndex >= startIndex else { return [] }
        let kinds: [ChartEvent.Kind] = [.earnings, .news, .dividend, .news, .split, .news]
        let titles: [ChartEvent.Kind: String] = [
            .earnings: "Quarterly earnings", .news: "Headline", .dividend: "Dividend", .split: "Stock split"
        ]
        var events: [ChartEvent] = []
        for index in startIndex...endIndex {
            let kind = kinds[abs(index) % kinds.count]
            let time = Date(timeIntervalSince1970: Double(index) * step + step / 3)
            events.append(ChartEvent(
                // A stable id per grid slot, so SwiftUI doesn't treat each refresh as new markers.
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llX", UInt64(bitPattern: Int64(index)) & 0xFFFFFFFFFFFF)) ?? UUID(),
                time: time,
                kind: kind,
                title: titles[kind] ?? "Event",
                detail: "Simulated \(kind.spokenName.lowercased()) for the demo."
            ))
        }
        return events
    }
}
