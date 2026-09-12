import Foundation
import Testing
@testable import CandleKitCore

@Suite("Price scale")
struct PriceScaleTests {
    @Test func niceTicksUseRoundSteps() {
        let ticks = PriceScale.niceTicks(in: 0...10, approximateCount: 5)
        #expect(ticks.step == 2)
        #expect(ticks.values == [0, 2, 4, 6, 8, 10])

        let narrow = PriceScale.niceTicks(in: 101.3...104.9, approximateCount: 4)
        #expect(narrow.step == 1)
        #expect(narrow.values == [102, 103, 104])
    }

    @Test func degenerateRangesProduceNoTicks() {
        #expect(PriceScale.niceTicks(in: 5...5, approximateCount: 4).values.isEmpty)
        #expect(PriceScale.niceTicks(in: 0...10, approximateCount: 0).values.isEmpty)
    }

    @Test func fractionDigitsFollowStep() {
        #expect(PriceScale.fractionDigits(forStep: 50) == 0)
        #expect(PriceScale.fractionDigits(forStep: 1) == 0)
        #expect(PriceScale.fractionDigits(forStep: 0.5) == 1)
        #expect(PriceScale.fractionDigits(forStep: 0.1) == 1)
        #expect(PriceScale.fractionDigits(forStep: 0.02) == 2)
    }

    @Test func suggestedDigitsScaleWithPrice() {
        #expect(PriceScale.suggestedFractionDigits(forPrice: 64_250) == 2)
        #expect(PriceScale.suggestedFractionDigits(forPrice: 0.5) == 4)
        #expect(PriceScale.suggestedFractionDigits(forPrice: 0.000_012_3) == 8)
    }

    @Test func autoRangeCoversVisibleCandlesWithPadding() throws {
        let candles = (0..<10).map { index in
            Candle(time: Date(timeIntervalSince1970: Double(index)), open: 15, high: 20, low: 10, close: 15)
        }
        let range = try #require(PriceScale.autoRange(for: candles, in: 0..<10))
        #expect(abs(range.lowerBound - 9.2) < 1e-9)
        #expect(abs(range.upperBound - 20.8) < 1e-9)
    }

    @Test func autoRangeIncludesIndicatorValues() throws {
        let candles = (0..<3).map { index in
            Candle(time: Date(timeIntervalSince1970: Double(index)), open: 15, high: 20, low: 10, close: 15)
        }
        let range = try #require(PriceScale.autoRange(for: candles, in: 0..<3, including: [[nil, 30, nil]], paddingFraction: 0))
        #expect(range == 10...30)
    }

    @Test func autoRangeHandlesFlatAndEmptyData() throws {
        let flat = [Candle(time: .init(timeIntervalSince1970: 0), open: 5, high: 5, low: 5, close: 5)]
        let range = try #require(PriceScale.autoRange(for: flat, in: 0..<1))
        #expect(abs(range.lowerBound - 4.95) < 1e-9)
        #expect(abs(range.upperBound - 5.05) < 1e-9)
        #expect(PriceScale.autoRange(for: flat, in: 1..<1) == nil)
        #expect(PriceScale.autoRange(for: [], in: 0..<10) == nil)
    }

    @Test func linearScaleMapsInvertedRanges() {
        let scale = LinearScale(domain: 0...100, rangeStart: 200, rangeEnd: 0)
        #expect(scale.map(25) == 150)
        #expect(scale.invert(150) == 25)
    }
}

@Suite("Time scale")
struct TimeScaleTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func candles(start: TimeInterval, interval: TimeInterval, count: Int) -> [Candle] {
        (0..<count).map { index in
            Candle(time: Date(timeIntervalSince1970: start + Double(index) * interval), open: 1, high: 1, low: 1, close: 1)
        }
    }

    @Test func strideKeepsLabelsApart() {
        #expect(TimeScale.labelStride(spacing: 10, minimumLabelSpacing: 90) == 10)
        #expect(TimeScale.labelStride(spacing: 30, minimumLabelSpacing: 90) == 3)
        #expect(TimeScale.labelStride(spacing: 1, minimumLabelSpacing: 90) == 100)
        #expect(TimeScale.labelStride(spacing: 0.01, minimumLabelSpacing: 90) == 10_000)
    }

    @Test func ticksSitOnMultiplesOfStride() {
        let series = candles(start: 1_767_225_600, interval: 3_600, count: 60)
        let ticks = TimeScale.ticks(for: series, in: 3..<50, spacing: 9, minimumLabelSpacing: 90, calendar: utc)
        #expect(ticks.map(\.index) == [10, 20, 30, 40])
    }

    @Test func dailyChartPromotesMonthBoundaries() {
        // Starts 2026-01-25 00:00 UTC; ticks every 5 days land on Jan 25, Jan 30, Feb 4, Feb 9.
        let series = candles(start: 1_769_299_200, interval: 86_400, count: 20)
        let ticks = TimeScale.ticks(for: series, in: 0..<20, spacing: 20, minimumLabelSpacing: 90, calendar: utc)
        #expect(ticks.map(\.index) == [0, 5, 10, 15])
        #expect(ticks.map(\.unit) == [.day, .day, .month, .day])
    }

    @Test func intradayChartPromotesDayBoundaries() {
        // Starts 2026-01-01 20:00 UTC; ticks every 3 hours land on 20:00, 23:00, 02:00 (next day), 05:00.
        let series = candles(start: 1_767_297_600, interval: 3_600, count: 12)
        let ticks = TimeScale.ticks(for: series, in: 0..<12, spacing: 30, minimumLabelSpacing: 90, calendar: utc)
        #expect(ticks.map(\.unit) == [.time, .time, .day, .time])
    }

    @Test func yearBoundaryWins() {
        let lastDayOf2025 = Date(timeIntervalSince1970: 1_767_139_200)
        let firstDayOf2026 = Date(timeIntervalSince1970: 1_767_225_600)
        #expect(TimeScale.changedUnit(from: lastDayOf2025, to: firstDayOf2026, calendar: utc) == .year)
    }

    @Test func intervalEstimateIgnoresWeekendGaps() {
        var times: [TimeInterval] = []
        var day = 0.0
        while times.count < 40 {
            if Int(day) % 7 < 5 { times.append(day * 86_400) }
            day += 1
        }
        let series = times.map { Candle(time: Date(timeIntervalSince1970: $0), open: 1, high: 1, low: 1, close: 1) }
        #expect(TimeScale.estimatedInterval(of: series) == 86_400)
        #expect(TimeScale.baseUnit(forInterval: 86_400) == .day)
        #expect(TimeScale.baseUnit(forInterval: 300) == .time)
    }
}

@Suite("Indicators")
struct IndicatorTests {
    @Test func simpleMovingAverage() {
        #expect(IndicatorMath.sma([2, 4, 6, 8, 20], period: 3) == [nil, nil, 4, 6, 34.0 / 3.0])
    }

    @Test func exponentialMovingAverageIsSeededWithSMA() {
        // alpha = 0.5: seed 4, then 4 + 0.5 * (8 - 4) = 6, then 6 + 0.5 * (20 - 6) = 13.
        #expect(IndicatorMath.ema([2, 4, 6, 8, 20], period: 3) == [nil, nil, 4, 6, 13])
    }

    @Test func periodsLongerThanDataYieldNil() {
        #expect(IndicatorMath.sma([1, 2], period: 3) == [nil, nil])
        #expect(IndicatorMath.ema([1, 2], period: 0) == [nil, nil])
    }

    @Test func runningSumMatchesNaiveAverage() {
        let closes = CandleSampleData.randomWalk(count: 2_000, seed: 9).map(\.close)
        let fast = IndicatorMath.sma(closes, period: 50)
        for index in 49..<closes.count {
            let naive = closes[(index - 49)...index].reduce(0, +) / 50
            #expect(abs(fast[index]! - naive) < 1e-8)
        }
    }
}

@Suite("Indicator cache")
struct IndicatorCacheTests {
    private let candles = CandleSampleData.randomWalk(count: 200, seed: 4)

    @Test func recomputesOnlyWhenCandlesChange() {
        var cache = IndicatorCache()
        let indicators: [any Indicator] = [RSIIndicator(), MACDIndicator()]

        let first = cache.results(for: indicators, candles: candles)
        #expect(cache.computations == 2)

        let second = cache.results(for: indicators, candles: candles)
        #expect(cache.computations == 2, "a second render with the same data must not recompute")
        #expect(first[0].plot("rsi")?.values == second[0].plot("rsi")?.values)

        var changed = candles
        changed[changed.count - 1].close += 1
        _ = cache.results(for: indicators, candles: changed)
        #expect(cache.computations == 4, "changed data must recompute both")
    }

    /// Changing one indicator's parameters must not invalidate the others — the descriptor id
    /// folds in parameter values precisely so this holds.
    @Test func recomputesOnlyTheIndicatorThatChanged() {
        var cache = IndicatorCache()
        _ = cache.results(for: [RSIIndicator(period: 14), MACDIndicator()], candles: candles)
        #expect(cache.computations == 2)

        _ = cache.results(for: [RSIIndicator(period: 21), MACDIndicator()], candles: candles)
        #expect(cache.computations == 3, "only the re-parameterised RSI should recompute")
    }

    @Test func evictsIndicatorsNoLongerRequested() {
        var cache = IndicatorCache()
        _ = cache.results(for: [RSIIndicator(), MACDIndicator(), OBVIndicator()], candles: candles)
        #expect(cache.computations == 3)

        _ = cache.results(for: [RSIIndicator()], candles: candles)
        #expect(cache.computations == 3)

        // MACD was evicted, so asking for it again is a fresh computation.
        _ = cache.results(for: [RSIIndicator(), MACDIndicator()], candles: candles)
        #expect(cache.computations == 4)
    }

    @Test func twoIndicatorsOfTheSameTypeCoexist() {
        var cache = IndicatorCache()
        let results = cache.results(
            for: [MovingAverageIndicator(period: 20), MovingAverageIndicator(period: 50)],
            candles: candles
        )
        #expect(cache.computations == 2)
        #expect(results[0].plot("ma")?.values != results[1].plot("ma")?.values)
    }

    @Test func handlesAnEmptyIndicatorList() {
        var cache = IndicatorCache()
        #expect(cache.results(for: [], candles: candles).isEmpty)
        #expect(cache.computations == 0)
    }
}

@Suite("Sample data")
struct SampleDataTests {
    @Test func isDeterministic() {
        #expect(CandleSampleData.randomWalk(count: 50, seed: 1) == CandleSampleData.randomWalk(count: 50, seed: 1))
        #expect(CandleSampleData.randomWalk(count: 50, seed: 1) != CandleSampleData.randomWalk(count: 50, seed: 2))
    }

    @Test func candlesAreWellFormedAndContinuous() {
        let candles = CandleSampleData.randomWalk(count: 1_000, interval: 300)
        for (index, candle) in candles.enumerated() {
            #expect(candle.low <= min(candle.open, candle.close))
            #expect(candle.high >= max(candle.open, candle.close))
            if index > 0 {
                #expect(candle.open == candles[index - 1].close)
                #expect(candle.time.timeIntervalSince(candles[index - 1].time) == 300)
            }
        }
    }
}
