import Foundation
import Testing
@testable import CandleKitCore

/// Fixtures and expectations for the indicator maths.
///
/// ## Where these numbers come from — read before changing one
///
/// Every expected array below was produced by an **independent reference implementation written
/// separately from the Swift code**, not by running the Swift and recording whatever it printed.
/// That makes these genuine cross-checks: the two implementations agreeing is evidence, the Swift
/// agreeing with itself would not be.
///
/// They are **not** transcribed from a published table, and the distinction matters. An attempt to
/// validate the RSI here against Wilder's widely reproduced worked example came out consistently
/// ~0.07 off, and no seeding or rounding variant accounted for the gap — most likely the recalled
/// table was inaccurate, but that could not be established without the primary source. Rather than
/// bake in numbers of uncertain provenance, these tests verify internal consistency and the
/// documented formulas, and validating against an authoritative published source is tracked
/// separately in the roadmap.
///
/// So: if one of these fails, the Swift has almost certainly changed behaviour — but a *passing*
/// test here is not proof the convention matches TradingView. That's a separate, still-open task.
enum IndicatorFixtures {
    static let highs: [Double] = [45.20, 45.90, 45.60, 46.40, 46.10, 45.30, 45.80, 46.90, 47.20, 46.80, 46.20, 47.40, 48.10, 47.60, 47.90, 48.80, 48.30, 47.50, 48.00, 49.10, 49.60, 49.00, 48.40, 49.30, 50.20, 49.70, 49.10, 50.00, 50.90, 50.40]
    static let lows: [Double] = [44.10, 44.70, 44.30, 45.00, 44.60, 43.90, 44.40, 45.50, 45.90, 45.40, 44.80, 46.00, 46.70, 46.20, 46.50, 47.30, 46.90, 46.10, 46.60, 47.70, 48.20, 47.60, 47.00, 47.90, 48.70, 48.30, 47.70, 48.60, 49.40, 49.00]
    static let closes: [Double] = [44.80, 45.40, 44.90, 46.00, 45.10, 44.20, 45.60, 46.50, 46.20, 45.70, 45.90, 47.10, 47.40, 46.90, 47.60, 48.20, 47.10, 46.80, 47.80, 48.90, 48.60, 47.90, 48.10, 49.00, 49.40, 48.60, 48.90, 49.80, 50.10, 49.30]
    static let volumes: [Double] = [1200.0, 1500.0, 1100.0, 1800.0, 1400.0, 900.0, 1600.0, 2100.0, 1700.0, 1300.0, 1250.0, 1900.0, 2200.0, 1450.0, 1750.0, 2300.0, 1600.0, 1150.0, 1850.0, 2400.0, 2050.0, 1500.0, 1350.0, 1950.0, 2500.0, 1700.0, 1600.0, 2150.0, 2600.0, 1800.0]

    static var candles: [Candle] {
        (0..<closes.count).map { index in
            Candle(
                time: Date(timeIntervalSince1970: 1_767_225_600 + Double(index) * 3_600),
                open: index == 0 ? closes[0] : closes[index - 1],
                high: highs[index],
                low: lows[index],
                close: closes[index],
                volume: volumes[index]
            )
        }
    }
}

/// Compares an optional series against expectations, with a tolerance.
private func expectSeries(
    _ actual: [Double?],
    _ expected: [Double?],
    tolerance: Double = 1e-7,
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

@Suite("Indicator maths")
struct IndicatorMathTests {
    private let closes = IndicatorFixtures.closes
    private let highs = IndicatorFixtures.highs
    private let lows = IndicatorFixtures.lows
    private let volumes = IndicatorFixtures.volumes

    @Test func simpleMovingAverage() {
        expectSeries(IndicatorMath.sma(closes, period: 5), [nil, nil, nil, nil, 45.240000000, 45.120000000, 45.160000000, 45.480000000, 45.520000000, 45.640000000, 45.980000000, 46.280000000, 46.460000000, 46.600000000, 46.980000000, 47.440000000, 47.440000000, 47.320000000, 47.500000000, 47.760000000, 47.840000000, 48.000000000, 48.260000000, 48.500000000, 48.600000000, 48.600000000, 48.800000000, 49.140000000, 49.360000000, 49.340000000], "SMA 5")
    }

    @Test func exponentialMovingAverage() {
        expectSeries(IndicatorMath.ema(closes, period: 5), [nil, nil, nil, nil, 45.240000000, 44.893333333, 45.128888889, 45.585925926, 45.790617284, 45.760411523, 45.806941015, 46.237960677, 46.625307118, 46.716871412, 47.011247608, 47.407498405, 47.304998937, 47.136665958, 47.357777305, 47.871851537, 48.114567691, 48.043045127, 48.062030085, 48.374686723, 48.716457816, 48.677638544, 48.751759029, 49.101172686, 49.434115124, 49.389410083], "EMA 5")
    }

    @Test func weightedMovingAverage() {
        expectSeries(IndicatorMath.wma(closes, period: 5), [nil, nil, nil, nil, 45.320000000, 44.973333333, 45.133333333, 45.580000000, 45.820000000, 45.880000000, 45.966666667, 46.340000000, 46.713333333, 46.860000000, 47.193333333, 47.600000000, 47.486666667, 47.273333333, 47.433333333, 47.900000000, 48.180000000, 48.200000000, 48.233333333, 48.480000000, 48.780000000, 48.780000000, 48.880000000, 49.213333333, 49.533333333, 49.513333333], "WMA 5")
    }

    /// The O(n) WMA recurrence is easy to get subtly wrong, so it's also checked against a direct
    /// O(n·period) computation of the definition across a range of periods.
    @Test func weightedMovingAverageMatchesDefinition() {
        for period in 1...8 {
            let fast = IndicatorMath.wma(closes, period: period)
            let denominator = Double(period * (period + 1)) / 2
            for index in (period - 1)..<closes.count {
                var sum = 0.0
                for offset in 0..<period {
                    sum += closes[index - period + 1 + offset] * Double(offset + 1)
                }
                let naive = sum / denominator
                #expect(abs(fast[index]! - naive) < 1e-9, "WMA \(period) at \(index)")
            }
        }
    }

    @Test func relativeStrengthIndex() {
        expectSeries(IndicatorMath.rsi(closes, period: 14), [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 64.000000000, 66.184971098, 59.102640461, 57.301707162, 61.511713500, 65.537048884, 63.583906285, 59.154017860, 60.011253101, 63.702897253, 65.238851634, 59.789487075, 61.101646853, 64.811477450, 65.976320911, 60.248779925], "RSI 14")
    }

    /// Properties that hold for any input, independent of the reference implementation.
    @Test func rsiStaysInBounds() {
        for period in [2, 7, 14] {
            for value in IndicatorMath.rsi(closes, period: period).compactMap({ $0 }) {
                #expect(value >= 0 && value <= 100)
            }
        }
    }

    @Test func rsiSaturatesOnMonotonicInput() {
        let rising = (0..<40).map { 100.0 + Double($0) }
        let falling = rising.reversed().map { $0 }
        #expect(IndicatorMath.rsi(rising, period: 14).last! == 100)
        #expect(IndicatorMath.rsi(falling, period: 14).last! == 0)
    }

    @Test func macdComponents() {
        let result = IndicatorMath.macd(closes, fastPeriod: 12, slowPeriod: 26, signalPeriod: 9)
        expectSeries(result.line, [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 1.209410877, 1.181971377, 1.218798307, 1.257693498, 1.210016586], "MACD line")
        expectSeries(result.signal, [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil], "MACD signal")
        expectSeries(result.histogram, [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil], "MACD histogram")
    }

    /// The histogram is defined as line − signal, so it must agree wherever both exist.
    @Test func macdHistogramIsLineMinusSignal() {
        let result = IndicatorMath.macd(closes, fastPeriod: 5, slowPeriod: 10, signalPeriod: 4)
        for index in closes.indices {
            guard let line = result.line[index], let signal = result.signal[index] else { continue }
            #expect(abs(result.histogram[index]! - (line - signal)) < 1e-9)
        }
    }

    @Test func bollingerBands() {
        let bands = IndicatorMath.bollingerBands(closes, period: 20, multiplier: 2)
        expectSeries(bands.lower, [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 43.987997724, 44.115907424, 44.242420536, 44.481166950, 44.498518220, 44.675583724, 45.246644753, 45.501996241, 45.535376137, 45.643172354, 46.008426499], "BB lower")
        expectSeries(bands.middle, [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 46.405000000, 46.595000000, 46.720000000, 46.880000000, 47.030000000, 47.245000000, 47.465000000, 47.630000000, 47.795000000, 47.990000000, 48.170000000], "BB middle")
        expectSeries(bands.upper, [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 48.822002276, 49.074092576, 49.197579464, 49.278833050, 49.561481780, 49.814416276, 49.683355247, 49.758003759, 50.054623863, 50.336827646, 50.331573501], "BB upper")
    }

    /// The bands must stay ordered and symmetric about the basis.
    @Test func bollingerBandsAreSymmetric() {
        let bands = IndicatorMath.bollingerBands(closes, period: 10, multiplier: 2)
        for index in closes.indices {
            guard let lower = bands.lower[index],
                  let middle = bands.middle[index],
                  let upper = bands.upper[index] else { continue }
            #expect(lower <= middle && middle <= upper)
            #expect(abs((upper - middle) - (middle - lower)) < 1e-9)
        }
    }

    @Test func averageTrueRange() {
        expectSeries(
            IndicatorMath.atr(highs: highs, lows: lows, closes: closes, period: 14),
            [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 1.385714286, 1.386734694, 1.394825073, 1.395194711, 1.395537945, 1.395856664, 1.396152616, 1.396427429, 1.396682613, 1.396919569, 1.397139600, 1.404486771, 1.404166288, 1.403868696, 1.403592360, 1.410478620, 1.409730147],
            "ATR 14"
        )
    }

    /// True range is never negative and is always at least the candle's own high−low.
    @Test func trueRangeProperties() {
        let ranges = IndicatorMath.trueRange(highs: highs, lows: lows, closes: closes)
        for index in ranges.indices {
            #expect(ranges[index] >= 0)
            #expect(ranges[index] >= highs[index] - lows[index] - 1e-12)
        }
    }

    @Test func stochasticOscillator() {
        let result = IndicatorMath.stochastic(
            highs: highs, lows: lows, closes: closes, period: 14, smoothK: 3, smoothD: 3
        )
        expectSeries(result.k, [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 82.426303855, 80.385487528, 70.748299320, 68.027210884, 78.173397018, 84.834394751, 79.831560284, 70.833333333, 73.611111111, 79.067460317, 76.475996903, 70.073557878, 73.170731707, 80.623306233, 80.081300813], "Stoch %K")
        expectSeries(result.d, [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 77.853363568, 73.053665911, 72.316302407, 77.011667551, 80.946450684, 78.499762789, 74.758668243, 74.503968254, 76.384856110, 75.205671700, 73.240095496, 74.622531940, 77.958446251], "Stoch %D")
    }

    @Test func stochasticStaysInBounds() {
        let result = IndicatorMath.stochastic(
            highs: highs, lows: lows, closes: closes, period: 5, smoothK: 1, smoothD: 3
        )
        for value in result.k.compactMap({ $0 }) {
            #expect(value >= 0 && value <= 100)
        }
    }

    /// A completely flat window would divide by zero; the convention is 50.
    @Test func stochasticHandlesFlatWindow() {
        let flat = [Double](repeating: 10, count: 20)
        let result = IndicatorMath.stochastic(
            highs: flat, lows: flat, closes: flat, period: 5, smoothK: 1, smoothD: 3
        )
        #expect(result.k.compactMap { $0 }.allSatisfy { $0 == 50 })
    }

    @Test func onBalanceVolume() {
        expectSeries(IndicatorMath.obv(closes: closes, volumes: volumes), [0.0, 1500.0, 400.0, 2200.0, 800.0, -100.0, 1500.0, 3600.0, 1900.0, 600.0, 1850.0, 3750.0, 5950.0, 4500.0, 6250.0, 8550.0, 6950.0, 5800.0, 7650.0, 10050.0, 8000.0, 6500.0, 7850.0, 9800.0, 12300.0, 10600.0, 12200.0, 14350.0, 16950.0, 15150.0], "OBV")
    }

    @Test func volumeWeightedAveragePrice() {
        expectSeries(
            IndicatorMath.vwap(
                highs: highs, lows: lows, closes: closes, volumes: volumes,
                sessionIDs: [Int](repeating: 0, count: closes.count)
            ),
            [44.700000000, 45.051851852, 45.017543860, 45.269047619, 45.268571429, 45.177215190, 45.192280702, 45.392816092, 45.525814536, 45.565068493, 45.570452156, 45.705633803, 45.892481203, 45.960747664, 46.064506839, 46.248461035, 46.318545903, 46.338179669, 46.407653910, 46.567334361, 46.700000000, 46.761111111, 46.799866131, 46.895801527, 47.047567783, 47.118659004, 47.170029564, 47.274532628, 47.423637579, 47.498322039],
            "VWAP"
        )
    }

    /// VWAP must reset when the session changes: the first candle of a session equals its own
    /// typical price, since nothing else has accumulated yet.
    @Test func vwapResetsPerSession() {
        let sessions = (0..<closes.count).map { $0 / 10 }
        let values = IndicatorMath.vwap(
            highs: highs, lows: lows, closes: closes, volumes: volumes, sessionIDs: sessions
        )
        for index in [0, 10, 20] {
            let typical = (highs[index] + lows[index] + closes[index]) / 3
            #expect(abs(values[index]! - typical) < 1e-9, "session start at \(index)")
        }
    }

    /// Degenerate inputs must return all-nil rather than crashing or producing garbage.
    @Test func degenerateInputsAreSafe() {
        #expect(IndicatorMath.sma([], period: 5).isEmpty)
        #expect(IndicatorMath.ema([1, 2], period: 5).allSatisfy { $0 == nil })
        #expect(IndicatorMath.wma([1, 2], period: 0).allSatisfy { $0 == nil })
        #expect(IndicatorMath.rsi([1, 2, 3], period: 14).allSatisfy { $0 == nil })
        #expect(IndicatorMath.atr(highs: [], lows: [], closes: [], period: 14).isEmpty)
        #expect(IndicatorMath.obv(closes: [1], volumes: [1, 2]).isEmpty)
        let mismatched = IndicatorMath.stochastic(
            highs: [1, 2], lows: [1], closes: [1, 2], period: 2, smoothK: 1, smoothD: 1
        )
        #expect(mismatched.k.allSatisfy { $0 == nil })
    }
}
