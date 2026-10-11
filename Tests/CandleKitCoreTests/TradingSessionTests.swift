import Foundation
import Testing
@testable import CandleKitCore

// Expected region boundaries below were computed independently with a short Python script that
// classifies each timestamp using `zoneinfo` and `datetime`, not this library's integer
// arithmetic. The epoch constants are:
//   1704700800  Mon 2024-01-08 08:00 UTC  (03:00 in a fixed UTC-5 zone)
//   1705132800  Sat 2024-01-13 08:00 UTC
//   1705114800  Sat 2024-01-13 03:00 UTC  (Fri 22:00 in UTC-5)
//   1709908140  Fri 2024-03-08 14:29 UTC  (09:29 New York, EST)
//   1710163740  Mon 2024-03-11 13:29 UTC  (09:29 New York, EDT — clocks went forward on 03-10)
@Suite("Trading sessions")
struct TradingSessionTests {
    private let minusFive = TimeZone(secondsFromGMT: -5 * 3_600)!

    private func candles(from start: TimeInterval, count: Int, every step: TimeInterval) -> [Candle] {
        (0..<count).map { index in
            Candle(
                time: Date(timeIntervalSince1970: start + step * Double(index)),
                open: 1, high: 1, low: 1, close: 1
            )
        }
    }

    private func usEquities(in zone: TimeZone) -> [TradingSession] {
        [
            TradingSession(kind: .preMarket, startMinute: TradingSession.minute(hour: 4), endMinute: TradingSession.minute(hour: 9, minute: 30), timeZone: zone),
            TradingSession(kind: .regular, startMinute: TradingSession.minute(hour: 9, minute: 30), endMinute: TradingSession.minute(hour: 16), timeZone: zone),
            TradingSession(kind: .afterHours, startMinute: TradingSession.minute(hour: 16), endMinute: TradingSession.minute(hour: 20), timeZone: zone),
        ]
    }

    @Test func splitsAWeekdayIntoPreRegularAndAfterHours() {
        // 36 half-hour candles from 03:00 to 20:30 local on a Monday.
        let series = candles(from: 1_704_700_800, count: 36, every: 1_800)
        let regions = SessionClassifier.regions(for: series, sessions: usEquities(in: minusFive))
        #expect(regions == [
            SessionRegion(kind: .preMarket, range: 2..<13),
            SessionRegion(kind: .regular, range: 13..<26),
            SessionRegion(kind: .afterHours, range: 26..<34),
        ])
    }

    @Test func weekendCandlesAreNotInAnySession() {
        let series = candles(from: 1_705_132_800, count: 6, every: 3_600)
        #expect(SessionClassifier.regions(for: series, sessions: usEquities(in: minusFive)).isEmpty)
    }

    /// A 20:00–04:00 session starts on a weekday and runs into the next morning, which belongs to the
    /// day it started on: Friday night covers early Saturday, but Saturday night starts nothing.
    @Test func overnightSessionRunsPastMidnight() {
        let overnight = TradingSession(
            kind: .overnight,
            startMinute: TradingSession.minute(hour: 20),
            endMinute: TradingSession.minute(hour: 4),
            timeZone: minusFive
        )
        // 30 hourly candles from Friday 22:00 local.
        let series = candles(from: 1_705_114_800, count: 30, every: 3_600)
        let regions = SessionClassifier.regions(for: series, sessions: [overnight])
        // Fri 22:00, 23:00, then Sat 00:00 to 03:00 local. Sat 04:00 onward is outside.
        #expect(regions == [SessionRegion(kind: .overnight, range: 0..<6)])
    }

    @Test func intervalsLongerThanAnHourGetNoRegions() {
        let twoHourly = candles(from: 1_704_700_800, count: 12, every: 7_200)
        #expect(SessionClassifier.regions(for: twoHourly, sessions: usEquities(in: minusFive)).isEmpty)
        let daily = candles(from: 1_704_700_800, count: 12, every: 86_400)
        #expect(SessionClassifier.regions(for: daily, sessions: usEquities(in: minusFive)).isEmpty)
    }

    @Test func emptyInputsGiveNoRegions() {
        #expect(SessionClassifier.regions(for: [], sessions: usEquities(in: minusFive)).isEmpty)
        let series = candles(from: 1_704_700_800, count: 5, every: 1_800)
        #expect(SessionClassifier.regions(for: series, sessions: []).isEmpty)
    }

    @Test func nonFiniteTimesDoNotCrash() {
        var series = candles(from: 1_704_700_800, count: 3, every: 1_800)
        series[1].time = Date(timeIntervalSince1970: .infinity)
        _ = SessionClassifier.regions(for: series, sessions: usEquities(in: minusFive))
    }

    /// Clocks went forward in New York on 2024-03-10, so 09:30 local is 14:30 UTC before and
    /// 13:30 UTC after. The classifier has to notice the offset change partway through the series.
    @Test(.enabled(if: TimeZone(identifier: "America/New_York") != nil))
    func followsDaylightSavingTransitions() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let sessions = usEquities(in: newYork)
        // One candle each side of the open, on a Friday before the change and a Monday after it.
        let series = [
            Candle(time: Date(timeIntervalSince1970: 1_709_908_140), open: 1, high: 1, low: 1, close: 1), // Fri 09:29 EST
            Candle(time: Date(timeIntervalSince1970: 1_709_908_200), open: 1, high: 1, low: 1, close: 1), // Fri 09:30 EST
            Candle(time: Date(timeIntervalSince1970: 1_710_163_740), open: 1, high: 1, low: 1, close: 1), // Mon 09:29 EDT
            Candle(time: Date(timeIntervalSince1970: 1_710_163_800), open: 1, high: 1, low: 1, close: 1), // Mon 09:30 EDT
        ]
        // Each pair is a minute apart across a weekend, so the typical gap is one minute and the
        // classifier applies. Fri 09:29 is pre-market, 09:30 regular; the same on Monday.
        let regions = SessionClassifier.regions(for: series, sessions: sessions)
        #expect(regions == [
            SessionRegion(kind: .preMarket, range: 0..<1),
            SessionRegion(kind: .regular, range: 1..<2),
            SessionRegion(kind: .preMarket, range: 2..<3),
            SessionRegion(kind: .regular, range: 3..<4),
        ])
    }

    @Test func intersectingFindsOnlyOverlappingRegions() {
        let regions = [
            SessionRegion(kind: .preMarket, range: 2..<13),
            SessionRegion(kind: .regular, range: 13..<26),
            SessionRegion(kind: .afterHours, range: 26..<34),
        ]
        #expect(Array(SessionClassifier.regions(regions, intersecting: 0..<2)).isEmpty)
        #expect(Array(SessionClassifier.regions(regions, intersecting: 0..<3)) == [regions[0]])
        // A boundary candle: index 13 is the first regular candle, so 12..<13 is only pre-market.
        #expect(Array(SessionClassifier.regions(regions, intersecting: 12..<13)) == [regions[0]])
        #expect(Array(SessionClassifier.regions(regions, intersecting: 12..<14)) == [regions[0], regions[1]])
        #expect(Array(SessionClassifier.regions(regions, intersecting: 30..<100)) == [regions[2]])
        #expect(Array(SessionClassifier.regions(regions, intersecting: 34..<40)).isEmpty)
        #expect(Array(SessionClassifier.regions(regions, intersecting: 5..<5)).isEmpty)
        #expect(Array(SessionClassifier.regions([], intersecting: 0..<10)).isEmpty)
    }

    @Test func initClampsOutOfRangeMinutes() {
        let session = TradingSession(kind: .regular, startMinute: -30, endMinute: 5_000)
        #expect(session.startMinute == 0)
        #expect(session.endMinute == 1_440)
    }
}
