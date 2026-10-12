import Foundation
import Testing
@testable import CandleKitCore

@Suite("Event markers")
struct EventMarkerTests {
    // 10 candles opening every 100 s from t = 1000.
    private let candles: [Candle] = (0..<10).map { i in
        Candle(time: Date(timeIntervalSince1970: 1000 + Double(i) * 100), open: 1, high: 2, low: 0.5, close: 1.5)
    }

    private func event(_ t: Double, _ kind: ChartEvent.Kind = .news, _ title: String = "x") -> ChartEvent {
        ChartEvent(time: Date(timeIntervalSince1970: t), kind: kind, title: title)
    }

    @Test func eventMapsToTheCandleThatWasTrading() {
        func index(_ t: Double) -> Int? {
            EventMarkerLayout.candleIndex(for: Date(timeIntervalSince1970: t), in: candles, interval: 100)
        }
        #expect(index(1000) == 0)
        #expect(index(1099) == 0)
        #expect(index(1100) == 1)
        #expect(index(1450) == 4)
    }

    @Test func eventsOutsideTheSeriesAreIgnored() {
        func index(_ t: Double) -> Int? {
            EventMarkerLayout.candleIndex(for: Date(timeIntervalSince1970: t), in: candles, interval: 100)
        }
        #expect(index(999) == nil)           // before the first candle
        #expect(index(1900) == 9)            // inside the last candle
        #expect(index(1999) == 9)
        #expect(index(2000) == nil)          // after the last candle closed
    }

    @Test func eventsOnTheSameCandleStack() {
        let clusters = EventMarkerLayout.clusters(
            events: [event(1010, .earnings, "a"), event(1050, .news, "b")],
            candles: candles, visible: 0..<10, interval: 100, spacing: 20, minimumGap: 10
        )
        #expect(clusters.count == 1)
        #expect(clusters[0].events.map(\.title) == ["a", "b"])
        #expect(clusters[0].candleIndex == 0)
    }

    @Test func nearbyMarkersMergeWhenZoomedOut() {
        // spacing 5 pt, gap 20 pt -> markers closer than 4 candles merge.
        let events = [event(1000), event(1200), event(1900)]
        let merged = EventMarkerLayout.clusters(
            events: events, candles: candles, visible: 0..<10, interval: 100, spacing: 5, minimumGap: 20
        )
        #expect(merged.count == 2)
        #expect(merged[0].events.count == 2)   // candles 0 and 2 are 2 apart (< 4)
        #expect(merged[1].candleIndex == 9)
    }

    @Test func farApartMarkersStaySeparateWhenZoomedIn() {
        let events = [event(1000), event(1200), event(1900)]
        let separate = EventMarkerLayout.clusters(
            events: events, candles: candles, visible: 0..<10, interval: 100, spacing: 30, minimumGap: 20
        )
        #expect(separate.count == 3)
    }

    @Test func onlyVisibleCandlesGetMarkers() {
        let clusters = EventMarkerLayout.clusters(
            events: [event(1000), event(1500), event(1900)],
            candles: candles, visible: 4..<8, interval: 100, spacing: 30, minimumGap: 20
        )
        #expect(clusters.map(\.candleIndex) == [5])
    }

    @Test func emptyInputsGiveNoMarkers() {
        #expect(EventMarkerLayout.clusters(events: [], candles: candles, visible: 0..<10, interval: 100, spacing: 10, minimumGap: 10).isEmpty)
        #expect(EventMarkerLayout.clusters(events: [event(1000)], candles: [], visible: 0..<10, interval: 100, spacing: 10, minimumGap: 10).isEmpty)
    }

    @Test func unsortedEventsStillClusterInOrder() {
        let clusters = EventMarkerLayout.clusters(
            events: [event(1900, .news, "late"), event(1000, .earnings, "early")],
            candles: candles, visible: 0..<10, interval: 100, spacing: 30, minimumGap: 20
        )
        #expect(clusters.map(\.primary.title) == ["early", "late"])
    }
}
