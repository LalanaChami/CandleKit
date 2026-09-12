import Foundation

/// The numerical routines behind the built-in indicators, separated from the `Indicator` types so
/// they can be tested directly and reused by app-defined indicators.
///
/// ## A note on conventions
///
/// Indicator definitions genuinely differ between platforms: RSI and ATR can use Wilder's smoothing
/// or a simple average, MACD's signal line differs by how it's seeded, Bollinger Bands can use a
/// population or sample standard deviation. A chart whose numbers disagree with the ones a user
/// sees elsewhere gets reported as a bug, so every function here documents which convention it
/// implements. Where a second convention is common it's exposed as a parameter rather than chosen
/// silently.
public enum IndicatorMath {

    // MARK: - Averages

    /// Simple moving average. O(n) via a running sum.
    public static func sma(_ values: [Double], period: Int) -> [Double?] {
        var result = [Double?](repeating: nil, count: values.count)
        guard period > 0, values.count >= period else { return result }
        var sum = 0.0
        for index in values.indices {
            sum += values[index]
            if index >= period { sum -= values[index - period] }
            if index >= period - 1 { result[index] = sum / Double(period) }
        }
        return result
    }

    /// Exponential moving average, `alpha = 2 / (period + 1)`, seeded with the simple average of the
    /// first `period` values. This seeding is what TradingView and StockCharts use; seeding with the
    /// first value instead produces noticeably different numbers for the first few hundred bars.
    public static func ema(_ values: [Double], period: Int) -> [Double?] {
        var result = [Double?](repeating: nil, count: values.count)
        guard period > 0, values.count >= period else { return result }
        let alpha = 2.0 / Double(period + 1)
        var average = values[0..<period].reduce(0, +) / Double(period)
        result[period - 1] = average
        for index in period..<values.count {
            average += alpha * (values[index] - average)
            result[index] = average
        }
        return result
    }

    /// Linearly weighted moving average — the most recent value carries weight `period`, the oldest
    /// weight 1.
    ///
    /// O(n), using the identity `weighted(t) = weighted(t-1) + period * v[t] - windowSum(t-1)`,
    /// where `windowSum(t-1)` is the plain sum of the `period` values ending at `t-1`. A naive
    /// implementation is O(n · period), which is slow enough to matter on a long series with a
    /// long period.
    public static func wma(_ values: [Double], period: Int) -> [Double?] {
        var result = [Double?](repeating: nil, count: values.count)
        guard period > 0, values.count >= period else { return result }
        let denominator = Double(period * (period + 1)) / 2

        var windowSum = 0.0
        var weightedSum = 0.0
        for offset in 0..<period {
            windowSum += values[offset]
            weightedSum += values[offset] * Double(offset + 1)
        }
        result[period - 1] = weightedSum / denominator

        for index in period..<values.count {
            // Order matters: the recurrence needs the window sum from the *previous* step.
            weightedSum += Double(period) * values[index] - windowSum
            windowSum += values[index] - values[index - period]
            result[index] = weightedSum / denominator
        }
        return result
    }

    /// Wilder's smoothing, also called RMA or SMMA: `avg = (prev * (period - 1) + value) / period`,
    /// seeded with the simple average of the first `period` values.
    ///
    /// This is *not* the same as an EMA of the same period — Wilder's is equivalent to an EMA of
    /// period `2 * period - 1`. Using an EMA here is a common source of RSI and ATR values that
    /// don't match other platforms.
    public static func wilderSmoothing(_ values: [Double], period: Int) -> [Double?] {
        var result = [Double?](repeating: nil, count: values.count)
        guard period > 0, values.count >= period else { return result }
        var average = values[0..<period].reduce(0, +) / Double(period)
        result[period - 1] = average
        for index in period..<values.count {
            average = (average * Double(period - 1) + values[index]) / Double(period)
            result[index] = average
        }
        return result
    }

    /// Rolling **population** standard deviation (divisor `n`), the convention Bollinger Bands use.
    /// A sample standard deviation (divisor `n - 1`) produces slightly wider bands.
    public static func rollingStandardDeviation(_ values: [Double], period: Int) -> [Double?] {
        var result = [Double?](repeating: nil, count: values.count)
        guard period > 1, values.count >= period else { return result }
        for index in (period - 1)..<values.count {
            let window = values[(index - period + 1)...index]
            let mean = window.reduce(0, +) / Double(period)
            let variance = window.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(period)
            result[index] = variance.squareRoot()
        }
        return result
    }

    // MARK: - Oscillators

    /// Wilder's Relative Strength Index. The first value lands at index `period`.
    ///
    /// When there are no losses in the window RSI is defined as 100, and when there are no gains,
    /// 0 — the ratio is otherwise a division by zero.
    public static func rsi(_ closes: [Double], period: Int) -> [Double?] {
        var result = [Double?](repeating: nil, count: closes.count)
        guard period > 0, closes.count > period else { return result }

        var gains = [Double](repeating: 0, count: closes.count)
        var losses = [Double](repeating: 0, count: closes.count)
        for index in 1..<closes.count {
            let change = closes[index] - closes[index - 1]
            gains[index] = max(change, 0)
            losses[index] = max(-change, 0)
        }

        var averageGain = gains[1...period].reduce(0, +) / Double(period)
        var averageLoss = losses[1...period].reduce(0, +) / Double(period)
        result[period] = rsiValue(averageGain: averageGain, averageLoss: averageLoss)

        for index in (period + 1)..<closes.count {
            averageGain = (averageGain * Double(period - 1) + gains[index]) / Double(period)
            averageLoss = (averageLoss * Double(period - 1) + losses[index]) / Double(period)
            result[index] = rsiValue(averageGain: averageGain, averageLoss: averageLoss)
        }
        return result
    }

    private static func rsiValue(averageGain: Double, averageLoss: Double) -> Double {
        if averageLoss == 0 { return averageGain == 0 ? 50 : 100 }
        if averageGain == 0 { return 0 }
        return 100 - 100 / (1 + averageGain / averageLoss)
    }

    /// MACD: `line = EMA(fast) - EMA(slow)`, `signal = EMA(line, signalPeriod)`,
    /// `histogram = line - signal`.
    ///
    /// The signal EMA is seeded from the first `signalPeriod` *available* MACD values — that is,
    /// starting where the slow EMA becomes defined rather than at index 0. Seeding it from the
    /// padded array including leading `nil`s is a common off-by-a-few-bars error.
    public static func macd(
        _ closes: [Double],
        fastPeriod: Int,
        slowPeriod: Int,
        signalPeriod: Int
    ) -> (line: [Double?], signal: [Double?], histogram: [Double?]) {
        let count = closes.count
        var line = [Double?](repeating: nil, count: count)
        var signal = [Double?](repeating: nil, count: count)
        var histogram = [Double?](repeating: nil, count: count)
        guard fastPeriod > 0, slowPeriod > 0, signalPeriod > 0, count > 0 else {
            return (line, signal, histogram)
        }

        let fast = ema(closes, period: fastPeriod)
        let slow = ema(closes, period: slowPeriod)
        for index in 0..<count {
            if let f = fast[index], let s = slow[index] { line[index] = f - s }
        }

        guard let start = line.firstIndex(where: { $0 != nil }) else {
            return (line, signal, histogram)
        }
        let compacted = line[start...].compactMap { $0 }
        let signalTail = ema(compacted, period: signalPeriod)
        for (offset, value) in signalTail.enumerated() {
            guard let value else { continue }
            let index = start + offset
            signal[index] = value
            if let lineValue = line[index] { histogram[index] = lineValue - value }
        }
        return (line, signal, histogram)
    }

    /// Stochastic oscillator. Raw %K is `100 * (close - lowestLow) / (highestHigh - lowestLow)`
    /// over `period` candles; %K is that smoothed by `smoothK` (use 1 for "fast" stochastic); %D is
    /// an SMA of %K over `smoothD`.
    ///
    /// When the high and low of the window are equal the formula divides by zero; 50 is returned,
    /// which is the usual convention for a completely flat window.
    public static func stochastic(
        highs: [Double],
        lows: [Double],
        closes: [Double],
        period: Int,
        smoothK: Int,
        smoothD: Int
    ) -> (k: [Double?], d: [Double?]) {
        let count = closes.count
        var k = [Double?](repeating: nil, count: count)
        var d = [Double?](repeating: nil, count: count)
        guard period > 0, smoothK > 0, smoothD > 0,
              count >= period, highs.count == count, lows.count == count else {
            return (k, d)
        }

        var raw = [Double?](repeating: nil, count: count)
        for index in (period - 1)..<count {
            let window = (index - period + 1)...index
            let highest = highs[window].max() ?? 0
            let lowest = lows[window].min() ?? 0
            raw[index] = highest == lowest ? 50 : 100 * (closes[index] - lowest) / (highest - lowest)
        }

        guard let rawStart = raw.firstIndex(where: { $0 != nil }) else { return (k, d) }
        let smoothedK = sma(raw[rawStart...].compactMap { $0 }, period: smoothK)
        for (offset, value) in smoothedK.enumerated() where value != nil {
            k[rawStart + offset] = value
        }

        guard let kStart = k.firstIndex(where: { $0 != nil }) else { return (k, d) }
        let smoothedD = sma(k[kStart...].compactMap { $0 }, period: smoothD)
        for (offset, value) in smoothedD.enumerated() where value != nil {
            d[kStart + offset] = value
        }
        return (k, d)
    }

    // MARK: - Volatility

    /// True range per candle: the greatest of the current range, and the gap from the previous
    /// close to this candle's high or low. The first candle has no previous close, so its true
    /// range is simply `high - low`.
    public static func trueRange(highs: [Double], lows: [Double], closes: [Double]) -> [Double] {
        let count = closes.count
        guard count > 0, highs.count == count, lows.count == count else { return [] }
        var result = [Double](repeating: 0, count: count)
        result[0] = highs[0] - lows[0]
        for index in 1..<count {
            let previousClose = closes[index - 1]
            result[index] = max(
                highs[index] - lows[index],
                max(abs(highs[index] - previousClose), abs(lows[index] - previousClose))
            )
        }
        return result
    }

    /// Average True Range, using Wilder's smoothing (the original definition).
    public static func atr(highs: [Double], lows: [Double], closes: [Double], period: Int) -> [Double?] {
        let ranges = trueRange(highs: highs, lows: lows, closes: closes)
        guard !ranges.isEmpty else { return [] }
        return wilderSmoothing(ranges, period: period)
    }

    /// Bollinger Bands: an SMA middle band with upper and lower bands `multiplier` population
    /// standard deviations away.
    public static func bollingerBands(
        _ closes: [Double],
        period: Int,
        multiplier: Double
    ) -> (lower: [Double?], middle: [Double?], upper: [Double?]) {
        let middle = sma(closes, period: period)
        let deviation = rollingStandardDeviation(closes, period: period)
        var lower = [Double?](repeating: nil, count: closes.count)
        var upper = [Double?](repeating: nil, count: closes.count)
        for index in closes.indices {
            guard let mid = middle[index], let sd = deviation[index] else { continue }
            upper[index] = mid + multiplier * sd
            lower[index] = mid - multiplier * sd
        }
        return (lower, middle, upper)
    }

    // MARK: - Volume

    /// On-Balance Volume: a running total that adds the candle's volume when the close rises and
    /// subtracts it when the close falls. The first candle seeds the running total at zero, which
    /// means OBV is only meaningful in relative terms — the absolute level depends on where the
    /// series starts.
    public static func obv(closes: [Double], volumes: [Double]) -> [Double?] {
        let count = closes.count
        guard count > 0, volumes.count == count else { return [] }
        var result = [Double?](repeating: nil, count: count)
        var total = 0.0
        result[0] = 0
        for index in 1..<count {
            if closes[index] > closes[index - 1] {
                total += volumes[index]
            } else if closes[index] < closes[index - 1] {
                total -= volumes[index]
            }
            result[index] = total
        }
        return result
    }

    /// Volume-weighted average price over the typical price `(high + low + close) / 3`,
    /// accumulated within each session and reset when `sessionIDs` changes.
    ///
    /// VWAP is session-anchored in practice — a VWAP accumulated since the beginning of a
    /// multi-year series is not a number anyone trades against. Callers supply the session
    /// boundaries because only they know the instrument's trading calendar; see
    /// ``dailySessionIDs(for:calendar:)`` for the common daily case.
    public static func vwap(
        highs: [Double],
        lows: [Double],
        closes: [Double],
        volumes: [Double],
        sessionIDs: [Int]
    ) -> [Double?] {
        let count = closes.count
        guard count > 0, highs.count == count, lows.count == count,
              volumes.count == count, sessionIDs.count == count else {
            return [Double?](repeating: nil, count: count)
        }
        var result = [Double?](repeating: nil, count: count)
        var cumulativePriceVolume = 0.0
        var cumulativeVolume = 0.0
        var currentSession: Int? = nil
        for index in 0..<count {
            if sessionIDs[index] != currentSession {
                currentSession = sessionIDs[index]
                cumulativePriceVolume = 0
                cumulativeVolume = 0
            }
            let typicalPrice = (highs[index] + lows[index] + closes[index]) / 3
            cumulativePriceVolume += typicalPrice * volumes[index]
            cumulativeVolume += volumes[index]
            result[index] = cumulativeVolume > 0 ? cumulativePriceVolume / cumulativeVolume : nil
        }
        return result
    }

    /// Session identifiers that change at each calendar day boundary — the usual anchor for VWAP on
    /// intraday charts.
    public static func dailySessionIDs(for candles: [Candle], calendar: Calendar = .current) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(candles.count)
        var currentDay: DateComponents? = nil
        var session = -1
        for candle in candles {
            let day = calendar.dateComponents([.year, .month, .day], from: candle.time)
            if day != currentDay {
                currentDay = day
                session += 1
            }
            result.append(session)
        }
        return result
    }
}
