import Foundation
import Testing
@testable import CandleKitCore

// Expected values were checked with an independent Python script (bisect over timestamps for the
// alignment cases, plain arithmetic for the scaling ones), not this library's two-pointer merge.
@Suite("Multi-symbol comparison")
struct ComparisonTests {
    private func candle(_ time: TimeInterval, close: Double) -> Candle {
        Candle(time: Date(timeIntervalSince1970: time), open: close, high: close, low: close, close: close)
    }

    private var primary: [Candle] { (0..<10).map { candle(60 * Double($0), close: 100) } }

    @Test func otherSeriesStartingLaterLeavesLeadingGaps() {
        let other = (0..<8).map { candle(120 + 60 * Double($0), close: 10 + Double($0)) }
        let aligned = SeriesAlignment.align(primary: primary, other: other)
        let expected: [Double?] = [nil, nil, 10, 11, 12, 13, 14, 15, 16, 17]
        #expect(aligned == expected)
    }

    @Test func staleValuesBecomeGapsPastMaxGap() {
        let other = [candle(0, close: 1), candle(60, close: 2), candle(120, close: 3), candle(600, close: 4)]
        // Default limit is 3x the other series' 60 s interval = 180 s.
        let aligned = SeriesAlignment.align(primary: primary, other: other)
        let expected: [Double?] = [1, 2, 3, 3, 3, 3, nil, nil, nil, nil]
        #expect(aligned == expected)
    }

    @Test func explicitMaxGapCarriesValuesForward() {
        let other = [candle(0, close: 1), candle(60, close: 2), candle(120, close: 3), candle(600, close: 4)]
        let aligned = SeriesAlignment.align(primary: primary, other: other, maxGap: 1_000)
        let expected: [Double?] = [1, 2, 3, 3, 3, 3, 3, 3, 3, 3]
        #expect(aligned == expected)
    }

    @Test func emptyInputs() {
        #expect(SeriesAlignment.align(primary: [], other: primary).isEmpty)
        #expect(SeriesAlignment.align(primary: primary, other: []).allSatisfy { $0 == nil })
    }

    @Test func seriesIsAnchoredAtItsFirstVisibleValue() throws {
        let closes: [Double] = [100, 110, 120, 130]
        let prim = closes.enumerated().map { candle(Double($0.offset), close: $0.element) }
        let aligned: [[Double?]] = [[nil, 50, 55, 60]]

        let full = try #require(ComparisonMath.scaling(
            primary: prim, aligned: aligned, visible: 0..<4, normalization: .percentChange))
        #expect(full.base == 100)
        let fullFactor = try #require(full.factors[0])
        #expect(abs(fullFactor - 2.2) < 1e-9)

        let zoomed = try #require(ComparisonMath.scaling(
            primary: prim, aligned: aligned, visible: 2..<4, normalization: .percentChange))
        #expect(zoomed.base == 120)
        let zoomedFactor = try #require(zoomed.factors[0])
        #expect(abs(zoomedFactor - 120.0 / 55.0) < 1e-9)
    }

    @Test func seriesWithNothingVisibleHasNoFactor() throws {
        let prim = (0..<4).map { candle(Double($0), close: 100) }
        let aligned: [[Double?]] = [[5, nil, nil, nil]]
        let scaling = try #require(ComparisonMath.scaling(
            primary: prim, aligned: aligned, visible: 2..<4, normalization: .percentChange))
        #expect(scaling.factors == [nil])
    }

    @Test func nonPositiveBaseDisablesComparison() {
        let prim = [candle(0, close: 0), candle(1, close: 5)]
        #expect(ComparisonMath.scaling(primary: prim, aligned: [], visible: 0..<2, normalization: .percentChange) == nil)
        #expect(ComparisonMath.scaling(primary: [], aligned: [], visible: 0..<0, normalization: .percentChange) == nil)
    }

    @Test func axisConversionRoundTrips() {
        let percent = ComparisonScaling(normalization: .percentChange, base: 100, factors: [])
        #expect(abs(percent.axisValue(forPrice: 110) - 10) < 1e-9)
        #expect(abs(percent.price(forAxisValue: -5) - 95) < 1e-9)

        let indexed = ComparisonScaling(normalization: .indexed100, base: 100, factors: [])
        #expect(abs(indexed.axisValue(forPrice: 110) - 110) < 1e-9)
        #expect(abs(indexed.price(forAxisValue: 95) - 95) < 1e-9)
        #expect(abs(indexed.price(forAxisValue: indexed.axisValue(forPrice: 37.5)) - 37.5) < 1e-9)
    }

    @Test func extentCoversOnlyTheRequestedRange() throws {
        let values: [Double?] = [nil, 50, 55, 60]
        let all = try #require(ComparisonMath.extent(of: values, factor: 2.2, in: 0..<4))
        #expect(abs(all.lowerBound - 110) < 1e-9)
        #expect(abs(all.upperBound - 132) < 1e-9)
        let tail = try #require(ComparisonMath.extent(of: values, factor: 2.2, in: 3..<10))
        #expect(abs(tail.lowerBound - 132) < 1e-9)
        #expect(ComparisonMath.extent(of: values, factor: 2.2, in: 0..<1) == nil)
    }
}
