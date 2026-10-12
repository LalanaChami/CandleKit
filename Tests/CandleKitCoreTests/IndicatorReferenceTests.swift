import Foundation
import Testing
@testable import CandleKitCore

// Golden-value tests against TA-Lib 0.8.1 (the C library behind much Python and server-side
// technical-analysis code) on a fixed 150-candle series. Closes, highs, lows and volumes were
// generated once from a seeded random walk (Python `random.seed(7)`) and are embedded here.
//
// Roadmap 5.9. What this shows: SMA, EMA, WMA, RSI, Bollinger Bands and the stochastic oscillator
// match TA-Lib to floating-point precision. MACD, ATR and OBV agree with TA-Lib once warmed up but
// differ in their first bars, because the two libraries seed them differently; CandleKit's choice
// is documented on each function and pinned below. This is a cross-check against an independent
// implementation, not a comparison with a live trading platform.
@Suite("Indicator reference values (TA-Lib)")
struct IndicatorReferenceTests {
    private let closes: [Double] = [
        100.0, 99.36, 98.0, 98.72, 97.05, 97.29,
        96.84, 95.14, 95.26, 93.5, 93.33, 91.74,
        90.25, 90.05, 91.38, 90.03, 89.07, 89.64,
        91.42, 91.81, 91.5, 93.42, 91.73, 93.2,
        92.47, 91.18, 89.81, 89.18, 90.45, 89.33,
        89.73, 90.34, 89.95, 90.22, 88.65, 87.1,
        86.11, 86.85, 86.67, 86.08, 86.48, 86.4,
        85.76, 86.91, 87.72, 86.86, 87.22, 87.4,
        88.86, 89.81, 89.1, 90.99, 89.62, 89.4,
        90.45, 89.22, 89.27, 87.63, 88.34, 89.41,
        89.77, 91.28, 90.66, 91.49, 91.94, 92.34,
        92.26, 93.67, 95.51, 95.5, 96.25, 94.57,
        95.46, 96.15, 98.24, 99.67, 98.87, 98.49,
        99.29, 97.4, 97.34, 96.08, 94.63, 92.97,
        94.11, 92.74, 91.85, 91.52, 93.04, 91.49,
        91.39, 91.67, 93.24, 94.58, 96.12, 95.32,
        95.08, 94.61, 96.23, 98.18, 96.84, 95.62,
        94.64, 93.67, 93.7, 94.14, 93.3, 91.45,
        91.23, 90.82, 91.16, 92.99, 93.83, 93.98,
        94.54, 95.33, 93.64, 95.3, 96.52, 98.13,
        99.46, 99.11, 98.79, 97.24, 97.89, 96.19,
        94.54, 93.48, 92.25, 91.72, 90.09, 88.29,
        87.09, 85.72, 85.31, 83.7, 85.1, 85.59,
        84.41, 83.62, 83.17, 82.78, 81.55, 82.83,
        84.63, 84.59, 84.62, 83.23, 81.92, 81.46,
    ]

    private let highs: [Double] = [
        101.08, 99.93, 98.84, 99.5, 97.75, 98.35,
        97.96, 95.44, 96.35, 93.98, 94.42, 93.23,
        91.36, 90.22, 91.85, 90.59, 89.72, 89.89,
        92.08, 92.61, 91.52, 94.39, 92.75, 93.61,
        93.18, 92.22, 90.62, 89.25, 91.54, 90.18,
        90.78, 90.45, 90.24, 90.26, 89.68, 87.86,
        86.24, 87.75, 88.13, 87.4, 86.75, 86.55,
        86.71, 87.51, 88.46, 87.08, 87.7, 88.48,
        89.31, 90.05, 90.43, 91.68, 90.65, 89.93,
        91.69, 89.56, 90.19, 88.11, 89.01, 90.0,
        91.09, 92.1, 90.8, 92.07, 92.69, 92.71,
        92.44, 93.73, 95.74, 96.32, 96.95, 95.43,
        96.16, 97.28, 98.64, 100.09, 98.95, 98.79,
        99.31, 98.81, 98.15, 96.33, 95.66, 94.01,
        94.65, 94.01, 92.33, 92.06, 93.97, 91.92,
        92.04, 92.43, 94.34, 94.97, 97.55, 96.13,
        95.81, 95.16, 97.1, 98.24, 97.48, 95.7,
        95.52, 93.99, 93.88, 94.24, 94.24, 92.41,
        92.3, 91.13, 91.42, 93.57, 94.41, 94.16,
        95.07, 95.69, 95.04, 96.41, 97.22, 98.42,
        100.61, 99.8, 99.22, 97.31, 98.65, 97.22,
        95.11, 93.84, 92.82, 91.74, 90.59, 88.39,
        87.54, 85.76, 85.78, 84.21, 85.72, 86.64,
        84.95, 84.43, 84.27, 83.83, 82.41, 83.22,
        84.96, 85.59, 84.77, 83.95, 82.72, 81.78,
    ]

    private let lows: [Double] = [
        98.72, 98.3, 96.87, 97.3, 96.1, 97.13,
        95.82, 94.56, 93.77, 92.6, 92.4, 91.1,
        89.28, 89.05, 90.47, 89.42, 89.04, 89.5,
        91.02, 91.5, 90.29, 92.79, 91.04, 92.5,
        91.71, 90.64, 89.81, 88.04, 89.64, 88.64,
        88.65, 89.12, 89.64, 89.16, 88.38, 87.02,
        85.79, 86.09, 86.46, 85.32, 85.33, 85.6,
        85.09, 86.09, 86.69, 86.06, 86.57, 86.73,
        88.76, 89.65, 88.83, 89.73, 89.29, 88.79,
        90.44, 89.16, 88.96, 86.59, 87.61, 88.51,
        89.46, 90.71, 90.05, 90.87, 91.81, 91.35,
        91.67, 92.16, 94.04, 95.48, 95.72, 93.24,
        94.35, 95.63, 97.92, 99.24, 97.75, 97.8,
        98.02, 97.23, 96.73, 94.98, 94.48, 91.99,
        93.54, 91.75, 90.76, 91.0, 91.81, 90.68,
        91.36, 91.41, 92.6, 93.65, 95.77, 94.99,
        94.64, 94.25, 95.26, 98.09, 95.97, 94.66,
        94.5, 92.63, 92.36, 93.05, 92.63, 90.5,
        90.8, 89.38, 90.49, 92.59, 93.35, 93.47,
        94.49, 95.21, 92.7, 94.52, 95.44, 97.54,
        98.87, 98.5, 98.56, 96.8, 96.77, 95.17,
        93.56, 92.77, 91.24, 90.68, 89.5, 87.48,
        87.04, 84.95, 84.85, 82.94, 84.44, 85.3,
        84.12, 82.69, 83.04, 82.31, 80.86, 82.16,
        83.82, 83.17, 84.1, 82.15, 81.62, 80.92,
    ]

    private let volumes: [Double] = [
        4230.0, 1980.0, 2370.0, 6269.0, 2324.0, 1615.0,
        2702.0, 5100.0, 8421.0, 7650.0, 5072.0, 5508.0,
        2802.0, 4710.0, 8424.0, 3726.0, 7219.0, 4686.0,
        4501.0, 2143.0, 5487.0, 2576.0, 2999.0, 1743.0,
        2431.0, 3801.0, 5553.0, 1746.0, 3615.0, 2958.0,
        4017.0, 3116.0, 7630.0, 5666.0, 2655.0, 8268.0,
        1164.0, 7141.0, 8132.0, 4381.0, 4136.0, 4390.0,
        7109.0, 5293.0, 2720.0, 4087.0, 3213.0, 3770.0,
        7161.0, 1508.0, 5080.0, 3273.0, 5704.0, 8927.0,
        3950.0, 2031.0, 6625.0, 5123.0, 5335.0, 6157.0,
        7474.0, 8068.0, 7951.0, 2769.0, 1758.0, 3220.0,
        8346.0, 3035.0, 4150.0, 4274.0, 6290.0, 4652.0,
        4537.0, 8814.0, 3556.0, 7952.0, 7671.0, 8150.0,
        8930.0, 1178.0, 2042.0, 1264.0, 4483.0, 6812.0,
        7256.0, 8337.0, 7588.0, 4877.0, 8932.0, 5810.0,
        5012.0, 1001.0, 1599.0, 4207.0, 8620.0, 8592.0,
        8603.0, 7763.0, 5324.0, 8007.0, 4835.0, 8964.0,
        4677.0, 3035.0, 7415.0, 1893.0, 2833.0, 2264.0,
        2245.0, 5279.0, 8961.0, 6587.0, 1892.0, 8712.0,
        7761.0, 6912.0, 6742.0, 6303.0, 7934.0, 7265.0,
        8330.0, 4746.0, 1696.0, 5517.0, 7364.0, 1323.0,
        1011.0, 7408.0, 2029.0, 2905.0, 5664.0, 8535.0,
        1307.0, 6287.0, 6857.0, 3488.0, 8884.0, 2048.0,
        6132.0, 3062.0, 5327.0, 6212.0, 4583.0, 6722.0,
        7257.0, 1918.0, 1814.0, 1576.0, 3460.0, 5296.0,
    ]

    private let samples = [40, 75, 100, 125, 148, 149]
    private let tail = [125, 148, 149]

    private func expect(
        _ actual: [Double?], at indices: [Int], equal expected: [Double], tolerance: Double = 1e-9,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for (index, want) in zip(indices, expected) {
            guard let got = actual[index] else {
                Issue.record("nil at index \(index)", sourceLocation: sourceLocation)
                continue
            }
            #expect(abs(got - want) <= tolerance, "index \(index): got \(got), want \(want)", sourceLocation: sourceLocation)
        }
    }

    @Test func simpleMovingAverage() {
        expect(IndicatorMath.sma(closes, period: 20), at: samples, equal: [89.44750000000002, 92.97050000000003, 94.08449999999999, 95.045, 84.99799999999998, 84.48499999999999])
    }

    @Test func exponentialMovingAverage() {
        expect(IndicatorMath.ema(closes, period: 20), at: samples, equal: [89.0483149392182, 93.93787295396773, 94.91001767602519, 96.05706846521689, 85.59144325054382, 85.19797246477773])
    }

    @Test func weightedMovingAverage() {
        expect(IndicatorMath.wma(closes, period: 20), at: samples, equal: [88.3011428571428, 94.70952380952374, 94.63828571428554, 96.34790476190445, 83.90423809523769, 83.5672857142853])
    }

    @Test func relativeStrengthIndex() {
        expect(IndicatorMath.rsi(closes, period: 14), at: samples, equal: [32.79746359044531, 75.35461807635127, 57.86301509241078, 51.98755276637886, 31.4141773848842, 30.339658375115906])
    }

    @Test func bollingerBands() {
        let bands = IndicatorMath.bollingerBands(closes, period: 20, multiplier: 2)
        expect(bands.upper, at: samples, equal: [93.96523339186815, 99.52087243215992, 98.00054124084517, 100.49721606321688, 90.07995080653096, 88.75582895934743])
        expect(bands.middle, at: samples, equal: [89.44750000000002, 92.97050000000003, 94.08449999999999, 95.045, 84.99799999999998, 84.48499999999999])
        expect(bands.lower, at: samples, equal: [84.92976660813189, 86.42012756784014, 90.16845875915482, 89.59278393678312, 79.916049193469, 80.21417104065254])
    }

    @Test func stochasticOscillator() {
        let result = IndicatorMath.stochastic(highs: highs, lows: lows, closes: closes, period: 14, smoothK: 3, smoothD: 3)
        expect(result.k, at: samples, equal: [14.85133826399904, 92.2366759249639, 87.15795229623482, 58.968586044437195, 41.46482122260678, 23.24106113033452])
        expect(result.d, at: samples, equal: [12.99153850289286, 86.92925989084166, 77.85659090850754, 70.06883304583748, 50.80497531920116, 39.55681485932407])
    }

    // MACD: TA-Lib seeds its fast EMA later, so its line starts at bar 33 and its first bars differ
    // from CandleKit's, which seeds each EMA from its own first window (the definition Pine Script
    // documents for ta.ema). The two converge, so compare at the end of the series.
    @Test func macdAgreesOnceWarmedUp() {
        let result = IndicatorMath.macd(closes, fastPeriod: 12, slowPeriod: 26, signalPeriod: 9)
        expect(result.line, at: tail, equal: [1.038958087688684, -2.4853535124057657, -2.512757792733609], tolerance: 1e-5)
        expect(result.signal, at: tail, equal: [0.8188811069548466, -2.6187701225530735, -2.5975676565891805], tolerance: 1e-5)
        expect(result.histogram, at: tail, equal: [0.2200769807338373, 0.13341661014730777, 0.08480986385557143], tolerance: 1e-5)
        // CandleKit's MACD line starts at the first bar both EMAs exist (index 25). TA-Lib starts it
        // at index 33 because it seeds the fast EMA later, which is why the early bars differ.
        #expect(result.line[24] == nil)
        #expect(result.line[25] != nil)
    }

    // ATR: both use Wilder smoothing. CandleKit counts the first candle's high minus low as its true
    // range, as Pine Script's ta.tr does; TA-Lib leaves it out. The difference fades quickly.
    @Test func averageTrueRangeAgreesOnceWarmedUp() {
        let atr = IndicatorMath.atr(highs: highs, lows: lows, closes: closes, period: 14)
        expect(atr, at: tail, equal: [1.8077981275021657, 1.793253336825505, 1.7365923841951119], tolerance: 1e-4)
        // CandleKit includes the first candle's high-low as the first true range and so has a value
        // from index 13; TA-Lib starts at index 14.
        #expect(atr[12] == nil)
        #expect(atr[13] != nil)
    }

    // OBV: identical except for the starting value of the running total.
    @Test func onBalanceVolumeDiffersOnlyByItsStartingValue() {
        let obv = IndicatorMath.obv(closes: closes, volumes: volumes)
        let reference: [Double] = [-36069.0, 6885.0, -32256.0, 5752.0, -45284.0, -50580.0]
        // TA-Lib starts the running total at the first candle's volume; CandleKit starts at zero.
        let offset = volumes[0]
        for (index, want) in zip(samples, reference) {
            #expect(abs((obv[index] ?? .nan) - (want - offset)) <= 1e-6)
        }
    }

}
