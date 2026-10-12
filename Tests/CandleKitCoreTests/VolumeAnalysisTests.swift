import Foundation
import Testing
@testable import CandleKitCore

// Expected values come from a short independent Python script (volume-weighted mean and variance;
// even spreading of each candle's volume over its high-low range), not from this implementation.
@Suite("Volume analysis")
struct VolumeAnalysisTests {
    private func candle(_ i: Int, high: Double, low: Double, close: Double, volume: Double) -> Candle {
        Candle(time: Date(timeIntervalSince1970: Double(i) * 60), open: close, high: high, low: low, close: close, volume: volume)
    }

    private var vwapSeries: [Candle] {
        [
            candle(0, high: 10, low: 9, close: 9.5, volume: 100),
            candle(1, high: 11, low: 9.5, close: 10.5, volume: 200),
            candle(2, high: 12, low: 10, close: 11, volume: 0),
            candle(3, high: 13, low: 11, close: 12, volume: 300),
        ]
    }

    @Test func vwapStartsAtTheAnchor() {
        let out = AnchoredVWAP.compute(candles: vwapSeries, anchorIndex: 1)
        #expect(out.vwap[0] == nil)
        #expect(abs(out.vwap[1]! - 10.333333333333334) < 1e-9)
        #expect(abs(out.vwap[2]! - 10.333333333333334) < 1e-9)   // no volume: unchanged
        #expect(abs(out.vwap[3]! - 11.333333333333334) < 1e-9)
    }

    @Test func bandsUseVolumeWeightedDeviation() {
        let out = AnchoredVWAP.compute(candles: vwapSeries, anchorIndex: 1, bandMultiplier: 1)
        #expect(abs(out.upper[1]! - 10.333333333333334) < 1e-9)   // one price: zero deviation
        #expect(abs(out.upper[3]! - 12.149829914261055) < 1e-9)
        #expect(abs(out.lower[3]! - 10.516836752405613) < 1e-9)
    }

    @Test func noBandsByDefault() {
        let out = AnchoredVWAP.compute(candles: vwapSeries, anchorIndex: 0)
        #expect(out.upper.allSatisfy { $0 == nil })
        #expect(out.lower.allSatisfy { $0 == nil })
    }

    @Test func anchorBeyondTheDataGivesNothing() {
        let out = AnchoredVWAP.compute(candles: vwapSeries, anchorIndex: 10)
        #expect(out.vwap.allSatisfy { $0 == nil })
    }

    @Test func zeroVolumeSeriesGivesNil() {
        let flat = (0..<3).map { candle($0, high: 2, low: 1, close: 1.5, volume: 0) }
        #expect(AnchoredVWAP.compute(candles: flat, anchorIndex: 0).vwap.allSatisfy { $0 == nil })
    }

    @Test func indicatorAnchorsToTheFirstCandleAtOrAfterItsTime() {
        let indicator = AnchoredVWAPIndicator(anchor: Date(timeIntervalSince1970: 30))   // between candle 0 and 1
        let plot = indicator.compute(vwapSeries).plots[0]
        #expect(plot.values[0] == nil)
        #expect(plot.values[1] != nil)
    }

    @Test func indicatorWithBandsAddsTwoPlotsAndAFill() {
        let result = AnchoredVWAPIndicator(anchor: Date(timeIntervalSince1970: 0), bandMultiplier: 2).compute(vwapSeries)
        #expect(result.plots.map(\.key) == ["vwap", "upper", "lower"])
        #expect(result.fills.count == 1)
    }

    @Test func indicatorSurvivesADescriptorRoundTrip() {
        let original = AnchoredVWAPIndicator(anchor: Date(timeIntervalSince1970: 1_700_000_000), bandMultiplier: 1.5)
        let entry = IndicatorCatalogEntry(AnchoredVWAPIndicator.self) { AnchoredVWAPIndicator(anchor: Date(timeIntervalSince1970: 0)) }
        let restored = entry.makeIndicator(parameters: original.descriptor.parameters) as? AnchoredVWAPIndicator
        #expect(restored?.anchor == original.anchor)
        #expect(restored?.bandMultiplier == 1.5)
    }

    // Profile: candles (high, low, volume) = (2,0,100), (4,2,200), (3,3,30), (8,4,150), four buckets of 2.
    private var profileSeries: [Candle] {
        [(2.0, 0.0, 100.0), (4.0, 2.0, 200.0), (3.0, 3.0, 30.0), (8.0, 4.0, 150.0)].enumerated().map {
            candle($0.offset, high: $0.element.0, low: $0.element.1, close: $0.element.1, volume: $0.element.2)
        }
    }

    @Test func profileSpreadsVolumeAcrossBuckets() {
        let profile = VolumeProfile.compute(candles: profileSeries, range: 0..<4, bucketCount: 4)!
        #expect(profile.volumes.count == 4)
        let expected: [Double] = [100, 230, 75, 75]
        for (got, want) in zip(profile.volumes, expected) { #expect(abs(got - want) < 1e-9) }
        #expect(profile.lowPrice == 0)
        #expect(profile.bucketHeight == 2)
        #expect(abs(profile.totalVolume - 480) < 1e-9)
    }

    @Test func profileFindsPointOfControlAndValueArea() {
        let profile = VolumeProfile.compute(candles: profileSeries, range: 0..<4, bucketCount: 4)!
        #expect(profile.pointOfControl == 1)
        #expect(profile.valueArea == 0...2)
        #expect(abs(profile.price(ofBucket: 1) - 3) < 1e-9)
    }

    @Test func profileOnlyCoversTheRequestedRange() {
        let profile = VolumeProfile.compute(candles: profileSeries, range: 3..<4, bucketCount: 4)!
        #expect(profile.lowPrice == 4)
        #expect(abs(profile.totalVolume - 150) < 1e-9)
    }

    @Test func profileHandlesAFlatPrice() {
        let flat = (0..<3).map { candle($0, high: 5, low: 5, close: 5, volume: 10) }
        let profile = VolumeProfile.compute(candles: flat, range: 0..<3, bucketCount: 4)!
        #expect(abs(profile.totalVolume - 30) < 1e-9)
        #expect(profile.volumes.filter { $0 > 0 }.count == 1)
    }

    @Test func profileIsNilWithoutVolumeOrCandles() {
        #expect(VolumeProfile.compute(candles: [], range: 0..<0) == nil)
        let silent = (0..<3).map { candle($0, high: 2, low: 1, close: 1.5, volume: 0) }
        #expect(VolumeProfile.compute(candles: silent, range: 0..<3) == nil)
        #expect(VolumeProfile.compute(candles: profileSeries, range: 0..<4, bucketCount: 1) == nil)
    }

    @Test func rangeIsClampedToTheData() {
        let profile = VolumeProfile.compute(candles: profileSeries, range: -5..<99, bucketCount: 4)
        #expect(profile != nil)
        #expect(abs(profile!.totalVolume - 480) < 1e-9)
    }
}
