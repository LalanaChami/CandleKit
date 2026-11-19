import Foundation
import Testing
@testable import CandleKitCore

@Suite("CrosshairTagFormat")
struct CrosshairTagFormatTests {
    // 2023-11-14 22:13:20 UTC. Fixed locale/timezone pins make the expectations deterministic.
    private let sampleTime = Date(timeIntervalSince1970: 1_700_000_000)
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let es = Locale(identifier: "es_ES")
    private let us = Locale(identifier: "en_US")

    @Test func rangeTimePutsRangeBeforeTime() {
        let tag = CrosshairTagFormat.rangeTime(
            low: 132.43, high: 138.83, time: sampleTime, interval: 60, digits: 2, locale: es, timeZone: utc)
        let low = CrosshairTagFormat.price(132.43, digits: 2, locale: es)
        let high = CrosshairTagFormat.price(138.83, digits: 2, locale: es)
        let time = CrosshairTagFormat.detailedTime(sampleTime, interval: 60, locale: es, timeZone: utc)
        #expect(tag == "\(low) - \(high) · \(time)")
        #expect(tag.hasPrefix("\(low) - \(high) · "))
    }

    @Test func localeControlsDecimalSeparator() {
        #expect(CrosshairTagFormat.price(132.43, digits: 2, locale: es) == "132,43")
        #expect(CrosshairTagFormat.price(132.43, digits: 2, locale: us) == "132.43")
    }

    @Test func timeZonePinsHour() {
        let plus5 = TimeZone(secondsFromGMT: 5 * 3_600)!
        let atUTC = CrosshairTagFormat.detailedTime(sampleTime, interval: 60, locale: es, timeZone: utc)
        let atPlus5 = CrosshairTagFormat.detailedTime(sampleTime, interval: 60, locale: es, timeZone: plus5)
        // 22:13 UTC is 3:13 at GMT+5 (no leading zero in this locale) — proves the
        // timeZone parameter is honored, not ignored.
        #expect(atUTC.contains("22:13"))
        #expect(atPlus5.contains("3:13"))
        #expect(atUTC != atPlus5)
    }

    @Test func intervalSelectsIntradayVsDailyFormat() {
        let intraday = CrosshairTagFormat.detailedTime(sampleTime, interval: 60, locale: es, timeZone: utc)
        let daily = CrosshairTagFormat.detailedTime(sampleTime, interval: 86_400, locale: es, timeZone: utc)
        #expect(intraday.contains("22:13"))
        #expect(!intraday.contains("2023"))
        #expect(daily.contains("2023"))
        #expect(!daily.contains("22:13"))
    }

    @Test func negativeDigitsClampToZero() {
        #expect(CrosshairTagFormat.price(132.6, digits: -1, locale: us)
            == CrosshairTagFormat.price(132.6, digits: 0, locale: us))
        #expect(CrosshairTagFormat.price(132.6, digits: 0, locale: us) == "133")
    }
}
