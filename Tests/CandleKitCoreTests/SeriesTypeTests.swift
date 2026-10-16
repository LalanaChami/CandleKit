import Foundation
import Testing
@testable import CandleKitCore

// Expected Heikin-Ashi values come from a short independent Python script implementing the usual
// definition, not from this implementation.
@Suite("Series types")
struct SeriesTypeTests {
    private func series() -> [Candle] {
        let rows: [(Double, Double, Double, Double)] = [
            (10, 12, 9, 11), (11, 13, 10, 10.5), (10.5, 11, 8, 8.5), (8.5, 9, 7, 8.8)
        ]
        var result: [Candle] = []
        for (index, row) in rows.enumerated() {
            result.append(Candle(
                time: Date(timeIntervalSince1970: Double(index) * 60),
                open: row.0, high: row.1, low: row.2, close: row.3, volume: Double(index + 1)
            ))
        }
        return result
    }

    @Test func heikinAshiMatchesReferenceValues() {
        let out = HeikinAshi.transform(series())
        let expected: [(Double, Double, Double, Double)] = [
            (10.5, 12, 9, 10.5), (10.5, 13, 10, 11.125), (10.8125, 11, 8, 9.5), (10.15625, 10.15625, 7, 8.325)
        ]
        #expect(out.count == 4)
        for (bar, want) in zip(out, expected) {
            #expect(abs(bar.open - want.0) < 1e-9)
            #expect(abs(bar.high - want.1) < 1e-9)
            #expect(abs(bar.low - want.2) < 1e-9)
            #expect(abs(bar.close - want.3) < 1e-9)
        }
    }

    @Test func timesAndVolumesAreKept() {
        let input = series()
        let out = HeikinAshi.transform(input)
        #expect(out.map(\.time) == input.map(\.time))
        #expect(out.map(\.volume) == input.map(\.volume))
    }

    @Test func emptyInputGivesEmptyOutput() {
        #expect(HeikinAshi.transform([]).isEmpty)
    }

    @Test func updatingTheLastCandleReusesEarlierBars() {
        let input = series()
        let first = HeikinAshi.transform(input)
        var changed = input
        changed[3].close = 9.6
        changed[3].high = 9.9
        let incremental = HeikinAshi.transform(changed, reusing: first, previousInput: input)
        #expect(incremental == HeikinAshi.transform(changed))
    }

    @Test func appendingACandleMatchesAFullTransform() {
        let input = series()
        let first = HeikinAshi.transform(input)
        var longer = input
        longer.append(Candle(time: Date(timeIntervalSince1970: 240), open: 8.8, high: 10, low: 8.7, close: 9.9, volume: 5))
        #expect(HeikinAshi.transform(longer, reusing: first, previousInput: input) == HeikinAshi.transform(longer))
    }

    @Test func aPrependFallsBackToAFullTransform() {
        let input = series()
        let first = HeikinAshi.transform(input)
        let older = Candle(time: Date(timeIntervalSince1970: -60), open: 9, high: 10, low: 8, close: 9.5, volume: 1)
        let longer = [older] + input
        #expect(HeikinAshi.transform(longer, reusing: first, previousInput: input) == HeikinAshi.transform(longer))
    }

    @Test func closeLineTypesAreFlagged() {
        #expect(ChartSeriesType.line.isCloseLine)
        #expect(ChartSeriesType.area.isCloseLine)
        #expect(!ChartSeriesType.candles.isCloseLine)
        #expect(!ChartSeriesType.heikinAshi.isCloseLine)
    }
}
