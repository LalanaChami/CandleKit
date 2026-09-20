import Foundation
import Testing
@testable import CandleKitCore

@Suite("Price crossing")
struct PriceCrossingTests {
    private func candle(close: Double, at offset: TimeInterval) -> Candle {
        Candle(
            time: Date(timeIntervalSince1970: offset),
            open: close, high: close, low: close, close: close
        )
    }

    @Test func detectsUpwardCross() {
        let candles = [candle(close: 95, at: 0), candle(close: 105, at: 60)]
        let result = priceCrossings(in: candles, levels: [100])
        #expect(result.count == 1)
        #expect(result[0].direction == .upward)
        #expect(result[0].level == 100)
        #expect(result[0].candle == candles.last!)
    }

    @Test func detectsDownwardCross() {
        let candles = [candle(close: 105, at: 0), candle(close: 95, at: 60)]
        let result = priceCrossings(in: candles, levels: [100])
        #expect(result.count == 1)
        #expect(result[0].direction == .downward)
    }

    @Test func noCrossWhenBothSidesAgree() {
        let candles = [candle(close: 90, at: 0), candle(close: 95, at: 60)]
        #expect(priceCrossings(in: candles, levels: [100]).isEmpty)
    }

    /// Landing exactly on the level counts as reaching it.
    @Test func exactTouchCounts() {
        let candles = [candle(close: 95, at: 0), candle(close: 100, at: 60)]
        let result = priceCrossings(in: candles, levels: [100])
        #expect(result.count == 1)
        #expect(result[0].direction == .upward)
    }

    /// No movement at all across a level that both closes happen to sit on either side of isn't
    /// possible to construct meaningfully here — this instead covers the level sitting exactly at
    /// both closes, which is "didn't move," not a cross.
    @Test func noMovementIsNotACross() {
        let candles = [candle(close: 100, at: 0), candle(close: 100, at: 60)]
        #expect(priceCrossings(in: candles, levels: [100]).isEmpty)
    }

    /// A tick jumps straight past the level entirely — still counts.
    @Test func gapThroughLevelCounts() {
        let candles = [candle(close: 50, at: 0), candle(close: 500, at: 60)]
        let result = priceCrossings(in: candles, levels: [100])
        #expect(result.count == 1)
        #expect(result[0].direction == .upward)
    }

    @Test func multipleLevelsCheckedIndependently() {
        let candles = [candle(close: 95, at: 0), candle(close: 105, at: 60)]
        let result = priceCrossings(in: candles, levels: [90, 100, 110])
        #expect(result.count == 1)
        #expect(result[0].level == 100)
    }

    @Test func fewerThanTwoCandlesReturnsEmpty() {
        #expect(priceCrossings(in: [], levels: [100]).isEmpty)
        #expect(priceCrossings(in: [candle(close: 100, at: 0)], levels: [100]).isEmpty)
    }

    @Test func emptyLevelsReturnsEmpty() {
        let candles = [candle(close: 95, at: 0), candle(close: 105, at: 60)]
        #expect(priceCrossings(in: candles, levels: []).isEmpty)
    }

    /// Re-crossing on a later tick is reported again — this is a stateless check, not a
    /// fire-once alert; the caller decides whether to debounce.
    @Test func reCrossingReportsAgain() {
        let first = [candle(close: 95, at: 0), candle(close: 105, at: 60)]
        #expect(priceCrossings(in: first, levels: [100]).count == 1)
        let second = first + [candle(close: 95, at: 120)]
        let result = priceCrossings(in: second, levels: [100])
        #expect(result.count == 1)
        #expect(result[0].direction == .downward)
    }
}
