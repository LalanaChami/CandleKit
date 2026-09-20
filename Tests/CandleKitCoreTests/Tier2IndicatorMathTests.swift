import Foundation
import Testing
@testable import CandleKitCore

/// Cross-checks for the Tier 2 indicator maths, against the same 30-candle fixture
/// `IndicatorMathTests.swift` uses (`IndicatorFixtures`), so a failure here and a failure there
/// are directly comparable.
///
/// Same policy as the Tier 1 tests, restated because it matters just as much here: every expected
/// array below comes from an independently written Python reference implementation, checked against
/// the standard definition of each indicator — not from running this Swift and recording its output,
/// and not transcribed from a published table. A passing test means this Swift agrees with a second,
/// separately reasoned-through implementation of the same formula; it is not yet confirmed against
/// an authoritative published source or another platform (see roadmap 5.9, which applies to Tier 1
/// too and is still open).
private func expectSeries(
    _ actual: [Double?],
    _ expected: [Double?],
    tolerance: Double = 1e-6,
    _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(actual.count == expected.count, "\(label): count", sourceLocation: sourceLocation)
    for index in 0..<min(actual.count, expected.count) {
        switch (actual[index], expected[index]) {
        case (nil, nil):
            continue
        case let (value?, expectedValue?):
            #expect(
                abs(value - expectedValue) < tolerance,
                "\(label)[\(index)]: got \(value), expected \(expectedValue)",
                sourceLocation: sourceLocation
            )
        case let (value, expectedValue):
            Issue.record(
                "\(label)[\(index)]: nil mismatch — got \(String(describing: value)), expected \(String(describing: expectedValue))",
                sourceLocation: sourceLocation
            )
        }
    }
}

private func expectBools(
    _ actual: [Bool?],
    _ expected: [Bool?],
    _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(actual.count == expected.count, "\(label): count", sourceLocation: sourceLocation)
    for index in 0..<min(actual.count, expected.count) {
        #expect(actual[index] == expected[index], "\(label)[\(index)]", sourceLocation: sourceLocation)
    }
}

@Suite("Tier 2 indicator maths")
struct Tier2IndicatorMathTests {
    private let highs = IndicatorFixtures.highs
    private let lows = IndicatorFixtures.lows
    private let closes = IndicatorFixtures.closes
    private let volumes = IndicatorFixtures.volumes

    @Test func donchianChannels() {
        let bands = IndicatorMath.donchianChannels(highs: highs, lows: lows, period: 10)
        expectSeries(bands.lower, [nil, nil, nil, nil, nil, nil, nil, nil, nil, 43.9, 43.9, 43.9, 43.9, 43.9, 43.9, 44.4, 44.8, 44.8, 44.8, 44.8, 46.0, 46.1, 46.1, 46.1, 46.1, 46.1, 46.1, 46.6, 47.0, 47.0], "Donchian lower")
        expectSeries(bands.middle, [nil, nil, nil, nil, nil, nil, nil, nil, nil, 45.55, 45.55, 45.65, 46.0, 46.0, 46.0, 46.6, 46.8, 46.8, 46.8, 46.95, 47.8, 47.85, 47.85, 47.85, 48.15, 48.15, 48.15, 48.4, 48.95, 48.95], "Donchian middle")
        expectSeries(bands.upper, [nil, nil, nil, nil, nil, nil, nil, nil, nil, 47.2, 47.2, 47.4, 48.1, 48.1, 48.1, 48.8, 48.8, 48.8, 48.8, 49.1, 49.6, 49.6, 49.6, 49.6, 50.2, 50.2, 50.2, 50.2, 50.9, 50.9], "Donchian upper")
    }

    @Test func keltnerChannels() {
        let bands = IndicatorMath.keltnerChannels(highs: highs, lows: lows, closes: closes, period: 20, atrPeriod: 10, multiplier: 2)
        expectSeries(bands.upper, [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 49.205810638, 49.414777193, 49.537175891, 49.666965537, 49.870108862, 50.112000723, 50.234569804, 50.374046818, 50.585963370, 50.826276721, 50.947424481], "Keltner upper", tolerance: 1e-5)
        expectSeries(bands.lower, [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 43.604189362, 43.813318045, 43.935862658, 44.065783627, 44.269045143, 44.471043376, 44.597708191, 44.740871367, 44.956105464, 45.159404606, 45.287239577], "Keltner lower", tolerance: 1e-5)
    }

    @Test func superTrend() {
        let result = IndicatorMath.superTrend(highs: highs, lows: lows, closes: closes, period: 10, multiplier: 3)
        expectSeries(result.uptrend, [nil, nil, nil, nil, nil, nil, nil, nil, nil, 41.99, 41.99, 42.5429, 43.23861, 43.23861, 43.23861, 43.84814669, 43.84814669, 43.84814669, 43.84814669, 44.198784043, 44.698905639, 44.698905639, 44.698905639, 44.698905639, 45.21928199, 45.21928199, 45.21928199, 45.21928199, 45.899845913, 45.899845913], "SuperTrend up", tolerance: 1e-5)
        // The fixture data trends up throughout, so `downtrend` never fires here — this test still
        // confirms the uptrend arithmetic; the flip branch is exercised by parabolicSAR's test below,
        // which does cross both ways on this same data.
        #expect(result.downtrend.allSatisfy { $0 == nil })
    }

    @Test func parabolicSAR() {
        let result = IndicatorMath.parabolicSAR(highs: highs, lows: lows)
        expectSeries(result.bullish, [44.1, 44.1, 44.1, 44.172, 44.3, nil, nil, 43.9, 43.96, 44.0896, 44.214016, 44.33345536, 44.517448038, 44.804052195, 45.06772802, 45.310309778, 45.6592788, 45.97335092, 46.1, 46.1, 46.46, 46.8996, nil, nil, 47.0, 47.064, 47.12672, 47.1881856, 47.248421888, 47.394485012], "PSAR bullish", tolerance: 1e-5)
        expectSeries(result.bearish, [nil, nil, nil, nil, nil, 46.4, 46.35, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 49.6, 49.548, nil, nil, nil, nil, nil, nil], "PSAR bearish", tolerance: 1e-5)
        expectBools(result.isBullish, [true, true, true, true, true, false, false, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, false, false, true, true, true, true, true, true], "PSAR direction")
    }

    @Test func ichimoku() {
        // Short periods so several components land inside the 30-candle fixture.
        let result = IndicatorMath.ichimoku(highs: highs, lows: lows, closes: closes, conversionPeriod: 3, basePeriod: 6, spanBPeriod: 9, displacement: 4)
        expectSeries(result.conversion, [nil, nil, 45.0, 45.35, 45.35, 45.15, 45.0, 45.4, 45.8, 46.3, 46.0, 46.1, 46.45, 47.05, 47.15, 47.5, 47.65, 47.45, 47.2, 47.6, 48.1, 48.6, 48.3, 48.15, 48.6, 49.05, 48.95, 48.85, 49.3, 49.75], "Ichimoku conversion")
        expectSeries(result.base, [nil, nil, nil, nil, nil, 45.15, 45.15, 45.4, 45.55, 45.55, 45.55, 45.9, 46.45, 46.45, 46.45, 46.8, 47.4, 47.45, 47.45, 47.6, 47.85, 47.85, 47.85, 48.1, 48.6, 48.6, 48.6, 48.6, 49.3, 49.3], "Ichimoku base")
        expectSeries(result.spanA, [nil, nil, nil, nil, nil, nil, nil, nil, nil, 45.15, 45.075, 45.4, 45.675, 45.925, 45.775, 46.0, 46.45, 46.75, 46.8, 47.15, 47.525, 47.45, 47.325, 47.6, 47.975, 48.225, 48.075, 48.125, 48.6, 48.825], "Ichimoku span A")
        expectSeries(result.spanB, [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 45.55, 45.55, 45.55, 45.65, 46.0, 46.0, 46.25, 46.8, 46.8, 46.8, 46.8, 47.55, 47.85, 47.85, 47.85, 47.85, 48.15, 48.15], "Ichimoku span B")
        expectSeries(result.laggingSpan, [45.1, 44.2, 45.6, 46.5, 46.2, 45.7, 45.9, 47.1, 47.4, 46.9, 47.6, 48.2, 47.1, 46.8, 47.8, 48.9, 48.6, 47.9, 48.1, 49.0, 49.4, 48.6, 48.9, 49.8, 50.1, 49.3, nil, nil, nil, nil], "Ichimoku lagging span")
    }

    @Test func adx() {
        let result = IndicatorMath.adx(highs: highs, lows: lows, closes: closes, period: 7)
        expectSeries(result.plusDI, [nil, nil, nil, nil, nil, nil, 20.833333333, 29.228486647, 28.391369366, 24.245925566, 20.716889955, 29.842522425, 32.736210377, 28.040067004, 27.092186739, 32.093354453, 27.53650412, 23.623265177, 25.342814776, 32.917681059, 33.315879334, 28.569919064, 24.498393117, 30.170485262, 34.6821376, 29.777942967, 25.561093821, 31.051728952, 35.40991237, 30.422637522], "ADX +DI", tolerance: 1e-5)
        expectSeries(result.minusDI, [nil, nil, nil, nil, nil, nil, 15.625, 13.353115727, 11.535996582, 15.066285575, 19.111292013, 16.169431729, 13.84824399, 16.985017177, 14.549900584, 12.338678208, 14.643523406, 20.683144379, 17.741648041, 15.216866689, 13.050192875, 17.29629423, 20.938994729, 17.953925515, 15.238431457, 17.123771214, 20.767869343, 17.823262226, 15.139957038, 17.031699651], "ADX -DI", tolerance: 1e-5)
        expectSeries(result.adx, [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 27.3467116, 26.947622922, 27.400713112, 29.837816639, 29.941921916, 26.612487559, 25.331057576, 26.965708963, 29.35746594, 28.674880358, 25.697559363, 25.652960886, 27.552436168, 27.470686762, 25.024312174, 25.315970643, 27.42782158, 27.540786397], "ADX", tolerance: 1e-5)
    }

    @Test func commodityChannelIndex() {
        expectSeries(
            IndicatorMath.cci(highs: highs, lows: lows, closes: closes, period: 10),
            [nil, nil, nil, nil, nil, nil, nil, nil, nil, 63.882063882, 12.785388128, 132.177263969, 150.085470085, 78.287461774, 97.826086957, 141.945773525, 66.666666667, -10.101010101, 57.142857143, 156.028368794, 148.459383754, 55.035128806, 11.24497992, 98.181818182, 142.857142857, 65.339966833, 26.798825257, 124.349881797, 172.057502246, 73.317307692],
            tolerance: 1e-5,
            "CCI"
        )
    }

    @Test func moneyFlowIndex() {
        expectSeries(
            IndicatorMath.mfi(highs: highs, lows: lows, closes: closes, volumes: volumes, period: 14),
            [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 66.66282675, 68.009412062, 66.345611684, 60.32110745, 67.101555516, 72.75048157, 73.387167287, 66.567066125, 60.494625005, 66.751573969, 73.113860842, 66.277360867, 59.125442862, 65.818954082, 67.070465769, 59.527344765],
            tolerance: 1e-5,
            "MFI"
        )
    }

    @Test func williamsPercentR() {
        expectSeries(
            IndicatorMath.williamsR(highs: highs, lows: lows, closes: closes, period: 14),
            [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, -28.571428571, -11.904761905, -12.244897959, -34.693877551, -40.816326531, -20.408163265, -4.255319149, -20.833333333, -35.416666667, -31.25, -12.5, -19.047619048, -39.024390244, -31.707317073, -9.756097561, -16.666666667, -33.333333333],
            tolerance: 1e-5,
            "Williams %R"
        )
    }

    @Test func rateOfChangeAndMomentum() {
        expectSeries(
            IndicatorMath.rateOfChange(closes, period: 12),
            [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 5.803571429, 3.303964758, 6.013363029, 4.782608696, 4.4345898, 5.882352941, 4.824561404, 5.161290323, 5.194805195, 4.814004376, 4.793028322, 4.033970276, 4.219409283, 3.624733475, 2.731092437, 3.319502075, 6.369426752, 5.341880342],
            tolerance: 1e-5,
            "ROC"
        )
        expectSeries(
            IndicatorMath.momentum(closes, period: 12),
            [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 2.6, 1.5, 2.7, 2.2, 2.0, 2.6, 2.2, 2.4, 2.4, 2.2, 2.2, 1.9, 2.0, 1.7, 1.3, 1.6, 3.0, 2.5],
            "Momentum"
        )
    }

    @Test func chaikinMoneyFlow() {
        expectSeries(
            IndicatorMath.chaikinMoneyFlow(highs: highs, lows: lows, closes: closes, volumes: volumes, period: 20),
            [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 0.179371527, 0.138581439, 0.105333905, 0.130064471, 0.139659352, 0.143865521, 0.127791497, 0.127791497, 0.145444364, 0.162165331, 0.152265279],
            tolerance: 1e-5,
            "CMF"
        )
    }

    /// A small, hand-computed fixture rather than the shared 30-candle one — pivot points only
    /// depend on the *previous session's* aggregated high/low/close, so a couple of tiny sessions
    /// is enough to check the formula, and hand arithmetic is easy to double check independently.
    ///
    /// Session 0: candles (h:10,l:8,c:9) and (h:12,l:9,c:11) → aggregated H=12, L=8, C=11 (last close).
    /// Session 1's two candles both use that: PP = (12+8+11)/3 = 10.333...
    @Test func pivotPointsClassic() {
        let highs: [Double] = [10, 12, 13, 14]
        let lows: [Double] = [8, 9, 10, 11]
        let closes: [Double] = [9, 11, 12, 13]
        let sessions = [0, 0, 1, 1]
        let levels = IndicatorMath.pivotPoints(highs: highs, lows: lows, closes: closes, sessionIDs: sessions, method: .classic)
        expectSeries(levels.pivot, [nil, nil, 10.333333333, 10.333333333], tolerance: 1e-6, "Pivot")
        expectSeries(levels.r1, [nil, nil, 12.666666667, 12.666666667], tolerance: 1e-6, "R1")
        expectSeries(levels.s1, [nil, nil, 8.666666667, 8.666666667], tolerance: 1e-6, "S1")
        expectSeries(levels.r2, [nil, nil, 14.333333333, 14.333333333], tolerance: 1e-6, "R2")
        expectSeries(levels.s2, [nil, nil, 6.333333333, 6.333333333], tolerance: 1e-6, "S2")
        expectSeries(levels.r3, [nil, nil, 16.666666667, 16.666666667], tolerance: 1e-6, "R3")
        expectSeries(levels.s3, [nil, nil, 4.666666667, 4.666666667], tolerance: 1e-6, "S3")
    }

    @Test func pivotPointsFibonacciAndCamarilla() {
        let highs: [Double] = [10, 12, 13, 14]
        let lows: [Double] = [8, 9, 10, 11]
        let closes: [Double] = [9, 11, 12, 13]
        let sessions = [0, 0, 1, 1]

        let fib = IndicatorMath.pivotPoints(highs: highs, lows: lows, closes: closes, sessionIDs: sessions, method: .fibonacci)
        expectSeries(fib.r1, [nil, nil, 11.861333333, 11.861333333], tolerance: 1e-6, "Fib R1")
        expectSeries(fib.s1, [nil, nil, 8.805333333, 8.805333333], tolerance: 1e-6, "Fib S1")
        expectSeries(fib.r2, [nil, nil, 12.805333333, 12.805333333], tolerance: 1e-6, "Fib R2")
        expectSeries(fib.s2, [nil, nil, 7.861333333, 7.861333333], tolerance: 1e-6, "Fib S2")
        expectSeries(fib.r3, [nil, nil, 14.333333333, 14.333333333], tolerance: 1e-6, "Fib R3")
        expectSeries(fib.s3, [nil, nil, 6.333333333, 6.333333333], tolerance: 1e-6, "Fib S3")

        let cam = IndicatorMath.pivotPoints(highs: highs, lows: lows, closes: closes, sessionIDs: sessions, method: .camarilla)
        expectSeries(cam.r1, [nil, nil, 11.366666667, 11.366666667], tolerance: 1e-6, "Cam R1")
        expectSeries(cam.s1, [nil, nil, 10.633333333, 10.633333333], tolerance: 1e-6, "Cam S1")
        expectSeries(cam.r2, [nil, nil, 11.733333333, 11.733333333], tolerance: 1e-6, "Cam R2")
        expectSeries(cam.s2, [nil, nil, 10.266666667, 10.266666667], tolerance: 1e-6, "Cam S2")
        expectSeries(cam.r3, [nil, nil, 12.1, 12.1], tolerance: 1e-6, "Cam R3")
        expectSeries(cam.s3, [nil, nil, 9.9, 9.9], tolerance: 1e-6, "Cam S3")
    }
}
