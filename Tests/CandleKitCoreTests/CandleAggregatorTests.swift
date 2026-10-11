import Foundation
import Testing
@testable import CandleKitCore

@Suite("CandleAggregator")
struct CandleAggregatorTests {
    /// Candle i: time i seconds, open 10+i, high 20+(i*2%7), low 5-(i%3), close 11+i, volume 100+i.
    private func series(_ n: Int) -> [Candle] {
        var result: [Candle] = []
        for i in 0..<n {
            let time = Date(timeIntervalSince1970: TimeInterval(i))
            let open = Double(10 + i)
            let high = Double(20 + (i * 2) % 7)
            let low = Double(5 - i % 3)
            let close = Double(11 + i)
            let volume = Double(100 + i)
            result.append(Candle(time: time, open: open, high: high, low: low, close: close, volume: volume))
        }
        return result
    }

    @Test func mergesTenCandlesIntoFourBuckets() {
        let out = CandleAggregator.downsample(series(10), maxCount: 4)
        // Per bucket: first index, open, high, low, close, volume (independent script).
        let expected: [[Double]] = [
            [0, 10, 22, 4, 12, 201],
            [2, 12, 26, 3, 15, 309],
            [5, 15, 25, 3, 17, 211],
            [7, 17, 24, 3, 20, 324],
        ]
        #expect(out.count == 4)
        for (candle, e) in zip(out, expected) {
            let actual: [Double] = [candle.time.timeIntervalSince1970, candle.open, candle.high,
                                    candle.low, candle.close, candle.volume]
            #expect(actual == e)
        }
    }

    @Test func shortSeriesIsUnchanged() {
        let input = series(5)
        #expect(CandleAggregator.downsample(input, maxCount: 5) == input)
        #expect(CandleAggregator.downsample(input, maxCount: 50) == input)
    }

    @Test func invalidCountGivesEmpty() {
        #expect(CandleAggregator.downsample(series(5), maxCount: 0).isEmpty)
        #expect(CandleAggregator.downsample(series(5), maxCount: -3).isEmpty)
        #expect(CandleAggregator.downsample([], maxCount: 3).isEmpty)
    }

    @Test func largeSeriesRespectsBoundAndKeepsExtremes() {
        let input = series(1000)
        let out = CandleAggregator.downsample(input, maxCount: 30)
        #expect(out.count == 30)
        #expect(out.first?.open == input.first?.open)
        #expect(out.last?.close == input.last?.close)
        #expect(out.map(\.volume).reduce(0, +) == input.map(\.volume).reduce(0, +))
        #expect(out.map(\.high).max() == input.map(\.high).max())
        #expect(out.map(\.low).min() == input.map(\.low).min())
    }
}
