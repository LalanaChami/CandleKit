import Foundation

/// Tier 2 indicator maths — see `IndicatorMath`'s own doc comment for the convention policy this
/// follows. Split into its own file purely for size; these are `IndicatorMath` static members like
/// everything else, sharing the same "document the convention, test against an independent
/// implementation" bar.
extension IndicatorMath {

    // MARK: - Trend (overlays)

    /// Rolling highest high / lowest low over `period`, with the midpoint as a third line —
    /// Donchian Channels.
    ///
    /// O(n · period) via a per-window `max`/`min`, the same approach `stochastic` already uses for
    /// its rolling high/low. A monotonic-deque O(n) version exists but isn't worth the complexity
    /// at the window sizes (typically 20–55) this is actually used at.
    public static func donchianChannels(
        highs: [Double],
        lows: [Double],
        period: Int
    ) -> (lower: [Double?], middle: [Double?], upper: [Double?]) {
        let count = highs.count
        var lower = [Double?](repeating: nil, count: count)
        var middle = [Double?](repeating: nil, count: count)
        var upper = [Double?](repeating: nil, count: count)
        guard period > 0, count >= period, lows.count == count else { return (lower, middle, upper) }
        for index in (period - 1)..<count {
            let window = (index - period + 1)...index
            let highest = highs[window].max() ?? 0
            let lowest = lows[window].min() ?? 0
            upper[index] = highest
            lower[index] = lowest
            middle[index] = (highest + lowest) / 2
        }
        return (lower, middle, upper)
    }

    /// Keltner Channels: an EMA of the close as the middle line, with upper and lower bands
    /// `multiplier` ATRs away.
    ///
    /// Uses the close for the middle line (TradingView's default) rather than the typical price
    /// `(H+L+C)/3` some other platforms seed it with — a second common convention, exposed here as
    /// nothing more than "compute your own middle series and pass it in" would require; callers who
    /// need the typical-price variant can average their own inputs before calling this, or this may
    /// grow an explicit parameter if it turns out to matter in practice.
    public static func keltnerChannels(
        highs: [Double],
        lows: [Double],
        closes: [Double],
        period: Int,
        atrPeriod: Int,
        multiplier: Double
    ) -> (lower: [Double?], middle: [Double?], upper: [Double?]) {
        let count = closes.count
        var lower = [Double?](repeating: nil, count: count)
        var upper = [Double?](repeating: nil, count: count)
        guard count > 0, highs.count == count, lows.count == count else {
            return (lower, [Double?](repeating: nil, count: count), upper)
        }
        let middle = ema(closes, period: period)
        let atrValues = atr(highs: highs, lows: lows, closes: closes, period: atrPeriod)
        for index in 0..<count {
            guard let mid = middle[index], index < atrValues.count, let atrValue = atrValues[index] else { continue }
            upper[index] = mid + multiplier * atrValue
            lower[index] = mid - multiplier * atrValue
        }
        return (lower, middle, upper)
    }

    /// SuperTrend: an ATR-band trend-following overlay that flips between hugging price from below
    /// (uptrend) and above (downtrend).
    ///
    /// Returned as two separate series — `uptrend` non-`nil` only while in an uptrend, `downtrend`
    /// only while in a downtrend — rather than one signed series, so the renderer can colour the two
    /// halves independently without inferring direction from the numbers after the fact.
    ///
    /// The very first trend direction (at the first index where ATR becomes available) is seeded by
    /// comparing the close to the initial lower band — a reasonable, but not universally agreed-on,
    /// starting rule; different platforms seed this differently, and it only affects the first few
    /// bars before the algorithm's own flip logic takes over.
    public static func superTrend(
        highs: [Double],
        lows: [Double],
        closes: [Double],
        period: Int,
        multiplier: Double
    ) -> (uptrend: [Double?], downtrend: [Double?], isBullish: [Bool?]) {
        let count = closes.count
        var uptrend = [Double?](repeating: nil, count: count)
        var downtrend = [Double?](repeating: nil, count: count)
        var isBullish = [Bool?](repeating: nil, count: count)
        guard period > 0, count > period, highs.count == count, lows.count == count else {
            return (uptrend, downtrend, isBullish)
        }

        let atrValues = atr(highs: highs, lows: lows, closes: closes, period: period)
        guard let start = atrValues.firstIndex(where: { $0 != nil }) else { return (uptrend, downtrend, isBullish) }

        var finalUpper = [Double](repeating: 0, count: count)
        var finalLower = [Double](repeating: 0, count: count)
        var bullish = [Bool](repeating: true, count: count)

        for index in start..<count {
            guard let atrValue = atrValues[index] else { continue }
            let midpoint = (highs[index] + lows[index]) / 2
            let basicUpper = midpoint + multiplier * atrValue
            let basicLower = midpoint - multiplier * atrValue

            if index == start {
                finalUpper[index] = basicUpper
                finalLower[index] = basicLower
                bullish[index] = closes[index] > basicLower
            } else {
                finalUpper[index] = closes[index - 1] <= finalUpper[index - 1]
                    ? min(basicUpper, finalUpper[index - 1])
                    : basicUpper
                finalLower[index] = closes[index - 1] >= finalLower[index - 1]
                    ? max(basicLower, finalLower[index - 1])
                    : basicLower

                bullish[index] = bullish[index - 1]
                    ? closes[index] >= finalLower[index]
                    : closes[index] > finalUpper[index]
            }

            isBullish[index] = bullish[index]
            if bullish[index] {
                uptrend[index] = finalLower[index]
            } else {
                downtrend[index] = finalUpper[index]
            }
        }
        return (uptrend, downtrend, isBullish)
    }

    /// Wilder's Parabolic SAR — dots that trail price and flip sides when it's crossed.
    ///
    /// The very first trend direction is not well-defined by Wilder's original description (it
    /// assumes a chartist picks it by eye); this seeds it from whether the second bar's high rose
    /// versus the first, which only affects the first handful of bars before a flip corrects it.
    /// Returned as two series (`bullish`/`bearish` dots) for the same reason `superTrend` is: so the
    /// renderer can colour each side without re-deriving direction from the numbers.
    public static func parabolicSAR(
        highs: [Double],
        lows: [Double],
        accelerationStep: Double = 0.02,
        accelerationMax: Double = 0.2
    ) -> (bullish: [Double?], bearish: [Double?], isBullish: [Bool?]) {
        let count = highs.count
        var bullishOut = [Double?](repeating: nil, count: count)
        var bearishOut = [Double?](repeating: nil, count: count)
        var isBullish = [Bool?](repeating: nil, count: count)
        guard count > 1, lows.count == count, accelerationStep > 0, accelerationMax > 0 else {
            return (bullishOut, bearishOut, isBullish)
        }

        var bullish = highs[1] >= highs[0]
        var extremePoint = bullish ? highs[0] : lows[0]
        var sar = bullish ? lows[0] : highs[0]
        var acceleration = accelerationStep

        func record(_ index: Int) {
            isBullish[index] = bullish
            if bullish { bullishOut[index] = sar } else { bearishOut[index] = sar }
        }
        record(0)

        for index in 1..<count {
            var nextSAR = sar + acceleration * (extremePoint - sar)

            if bullish {
                let priorLow1 = lows[index - 1]
                let priorLow2 = index >= 2 ? lows[index - 2] : priorLow1
                nextSAR = min(nextSAR, priorLow1, priorLow2)

                if lows[index] < nextSAR {
                    bullish = false
                    nextSAR = extremePoint
                    extremePoint = lows[index]
                    acceleration = accelerationStep
                } else if highs[index] > extremePoint {
                    extremePoint = highs[index]
                    acceleration = min(acceleration + accelerationStep, accelerationMax)
                }
            } else {
                let priorHigh1 = highs[index - 1]
                let priorHigh2 = index >= 2 ? highs[index - 2] : priorHigh1
                nextSAR = max(nextSAR, priorHigh1, priorHigh2)

                if highs[index] > nextSAR {
                    bullish = true
                    nextSAR = extremePoint
                    extremePoint = highs[index]
                    acceleration = accelerationStep
                } else if lows[index] < extremePoint {
                    extremePoint = lows[index]
                    acceleration = min(acceleration + accelerationStep, accelerationMax)
                }
            }

            sar = nextSAR
            record(index)
        }
        return (bullishOut, bearishOut, isBullish)
    }

    /// Ichimoku Kinko Hyo's five components.
    ///
    /// `spanA` and `spanB` are computed from data ending `displacement` bars before the position
    /// they're plotted at (the standard "shift forward"), and `laggingSpan` (Chikou) is the close
    /// shifted `displacement` bars backward — both implemented as index arithmetic within the
    /// existing candle range.
    ///
    /// **Known gap:** real Ichimoku clouds project `displacement` bars *past* the most recent
    /// candle, into blank space with no price data yet. This per-candle array model has no
    /// representation for a position beyond the last candle, so that forward-projecting tail is not
    /// produced here — `spanA`/`spanB` stop at the last real candle. Extending the pane past the
    /// data is a renderer-level change, tracked as follow-up rather than done as part of this pass.
    public static func ichimoku(
        highs: [Double],
        lows: [Double],
        closes: [Double],
        conversionPeriod: Int = 9,
        basePeriod: Int = 26,
        spanBPeriod: Int = 52,
        displacement: Int = 26
    ) -> (conversion: [Double?], base: [Double?], spanA: [Double?], spanB: [Double?], laggingSpan: [Double?]) {
        let count = closes.count
        func midpoint(period: Int) -> [Double?] {
            var result = [Double?](repeating: nil, count: count)
            guard period > 0, count >= period else { return result }
            for index in (period - 1)..<count {
                let window = (index - period + 1)...index
                let highest = highs[window].max() ?? 0
                let lowest = lows[window].min() ?? 0
                result[index] = (highest + lowest) / 2
            }
            return result
        }

        let conversion = midpoint(period: conversionPeriod)
        let base = midpoint(period: basePeriod)
        let spanBRaw = midpoint(period: spanBPeriod)
        var spanA = [Double?](repeating: nil, count: count)
        var spanB = [Double?](repeating: nil, count: count)
        var laggingSpan = [Double?](repeating: nil, count: count)

        guard displacement >= 0, count > 0, highs.count == count, lows.count == count else {
            return (conversion, base, spanA, spanB, laggingSpan)
        }

        for index in 0..<count {
            let sourceIndex = index - displacement
            guard sourceIndex >= 0 else { continue }
            if let c = conversion[sourceIndex], let b = base[sourceIndex] {
                spanA[index] = (c + b) / 2
            }
            spanB[index] = spanBRaw[sourceIndex]
        }

        for index in 0..<count {
            let targetIndex = index - displacement
            guard targetIndex >= 0 else { continue }
            laggingSpan[targetIndex] = closes[index]
        }

        return (conversion, base, spanA, spanB, laggingSpan)
    }

    // MARK: - Pivot points

    /// Which formula converts a session's high/low/close into its next session's reference levels.
    /// All three agree on the pivot itself; only the resistance/support offsets differ.
    public enum PivotMethod: String, CaseIterable, Sendable {
        case classic = "Classic"
        case fibonacci = "Fibonacci"
        case camarilla = "Camarilla"
    }

    /// Classic/Fibonacci/Camarilla pivot points: a fixed set of levels for a session, derived from
    /// the *previous* session's high, low and close, and held constant across every candle in the
    /// current session — a stepped series, not a smoothly varying one.
    ///
    /// `sessionIDs` groups candles into sessions (see `dailySessionIDs(for:calendar:)` for the usual
    /// daily case); the first session has no prior session to derive levels from, so its candles get
    /// `nil` throughout.
    public static func pivotPoints(
        highs: [Double],
        lows: [Double],
        closes: [Double],
        sessionIDs: [Int],
        method: PivotMethod
    ) -> (
        pivot: [Double?],
        r1: [Double?], r2: [Double?], r3: [Double?],
        s1: [Double?], s2: [Double?], s3: [Double?]
    ) {
        let count = closes.count
        var pivot = [Double?](repeating: nil, count: count)
        var r1 = [Double?](repeating: nil, count: count)
        var r2 = [Double?](repeating: nil, count: count)
        var r3 = [Double?](repeating: nil, count: count)
        var s1 = [Double?](repeating: nil, count: count)
        var s2 = [Double?](repeating: nil, count: count)
        var s3 = [Double?](repeating: nil, count: count)
        guard count > 0, highs.count == count, lows.count == count, sessionIDs.count == count else {
            return (pivot, r1, r2, r3, s1, s2, s3)
        }

        struct SessionStats { var high = -Double.infinity; var low = Double.infinity; var close = 0.0 }
        var sessionStats: [Int: SessionStats] = [:]
        for index in 0..<count {
            let session = sessionIDs[index]
            var stats = sessionStats[session] ?? SessionStats()
            stats.high = max(stats.high, highs[index])
            stats.low = min(stats.low, lows[index])
            stats.close = closes[index] // candles arrive in order, so the last write is the session close
            sessionStats[session] = stats
        }

        var currentSession: Int? = nil
        var priorStats: SessionStats? = nil
        for index in 0..<count {
            let session = sessionIDs[index]
            if session != currentSession {
                if let previousSession = currentSession {
                    priorStats = sessionStats[previousSession]
                }
                currentSession = session
            }
            guard let stats = priorStats, stats.high.isFinite, stats.low.isFinite else { continue }
            let high = stats.high, low = stats.low, close = stats.close
            let range = high - low
            let pp = (high + low + close) / 3
            pivot[index] = pp

            switch method {
            case .classic:
                r1[index] = 2 * pp - low
                s1[index] = 2 * pp - high
                r2[index] = pp + range
                s2[index] = pp - range
                r3[index] = high + 2 * (pp - low)
                s3[index] = low - 2 * (high - pp)
            case .fibonacci:
                r1[index] = pp + 0.382 * range
                s1[index] = pp - 0.382 * range
                r2[index] = pp + 0.618 * range
                s2[index] = pp - 0.618 * range
                r3[index] = pp + range
                s3[index] = pp - range
            case .camarilla:
                r1[index] = close + range * 1.1 / 12
                s1[index] = close - range * 1.1 / 12
                r2[index] = close + range * 1.1 / 6
                s2[index] = close - range * 1.1 / 6
                r3[index] = close + range * 1.1 / 4
                s3[index] = close - range * 1.1 / 4
            }
        }
        return (pivot, r1, r2, r3, s1, s2, s3)
    }

    // MARK: - Oscillators

    /// Per-candle directional movement: how much of today's high/low move counts toward `+DM` or
    /// `-DM`, the inputs to `adx(highs:lows:closes:period:)`.
    ///
    /// Index 0 has no previous bar to compare against, so — like `trueRange`'s own documented
    /// handling of its first index — it's treated as zero movement rather than left undefined.
    public static func directionalMovement(highs: [Double], lows: [Double]) -> (plusDM: [Double], minusDM: [Double]) {
        let count = highs.count
        var plusDM = [Double](repeating: 0, count: count)
        var minusDM = [Double](repeating: 0, count: count)
        guard count > 1, lows.count == count else { return (plusDM, minusDM) }
        for index in 1..<count {
            let upMove = highs[index] - highs[index - 1]
            let downMove = lows[index - 1] - lows[index]
            if upMove > downMove, upMove > 0 { plusDM[index] = upMove }
            if downMove > upMove, downMove > 0 { minusDM[index] = downMove }
        }
        return (plusDM, minusDM)
    }

    /// Wilder's ADX/DMI: `+DI` and `-DI` (directional indicators) and `ADX` (their smoothed,
    /// direction-agnostic strength).
    ///
    /// Wilder's original recurrence smooths a running *sum* of `+DM`/`-DM`/true range
    /// (`sum -= sum/period; sum += today's value`). `+DI`/`-DI` are a ratio of two such sums, and
    /// `wilderSmoothing`'s *average* recurrence is that same sum divided by `period` at every step —
    /// so the ratio is identical either way, and reusing `wilderSmoothing` here (rather than a
    /// second, sum-flavoured smoothing function) changes nothing about the result.
    public static func adx(
        highs: [Double],
        lows: [Double],
        closes: [Double],
        period: Int
    ) -> (plusDI: [Double?], minusDI: [Double?], adx: [Double?]) {
        let count = closes.count
        var plusDI = [Double?](repeating: nil, count: count)
        var minusDI = [Double?](repeating: nil, count: count)
        var adxResult = [Double?](repeating: nil, count: count)
        guard period > 0, count > period * 2, highs.count == count, lows.count == count else {
            return (plusDI, minusDI, adxResult)
        }

        let (plusDMRaw, minusDMRaw) = directionalMovement(highs: highs, lows: lows)
        let trueRanges = trueRange(highs: highs, lows: lows, closes: closes)
        let smoothedPlusDM = wilderSmoothing(plusDMRaw, period: period)
        let smoothedMinusDM = wilderSmoothing(minusDMRaw, period: period)
        let smoothedTR = wilderSmoothing(trueRanges, period: period)

        var directionalIndex = [Double?](repeating: nil, count: count)
        for index in 0..<count {
            guard let plusSmoothed = smoothedPlusDM[index],
                  let minusSmoothed = smoothedMinusDM[index],
                  let trSmoothed = smoothedTR[index],
                  trSmoothed > 0 else { continue }
            let plus = 100 * plusSmoothed / trSmoothed
            let minus = 100 * minusSmoothed / trSmoothed
            plusDI[index] = plus
            minusDI[index] = minus
            let sum = plus + minus
            directionalIndex[index] = sum == 0 ? 0 : 100 * abs(plus - minus) / sum
        }

        guard let dxStart = directionalIndex.firstIndex(where: { $0 != nil }) else {
            return (plusDI, minusDI, adxResult)
        }
        let compactedDX = directionalIndex[dxStart...].compactMap { $0 }
        let smoothedDX = wilderSmoothing(compactedDX, period: period)
        for (offset, value) in smoothedDX.enumerated() {
            guard let value else { continue }
            adxResult[dxStart + offset] = value
        }
        return (plusDI, minusDI, adxResult)
    }

    /// Commodity Channel Index: how far the typical price `(H+L+C)/3` sits from its own moving
    /// average, scaled by mean absolute deviation and the conventional `0.015` constant (chosen
    /// historically so ~70–80% of values fall within ±100).
    public static func cci(highs: [Double], lows: [Double], closes: [Double], period: Int) -> [Double?] {
        let count = closes.count
        var result = [Double?](repeating: nil, count: count)
        guard period > 0, count >= period, highs.count == count, lows.count == count else { return result }

        let typical = (0..<count).map { (highs[$0] + lows[$0] + closes[$0]) / 3 }
        let basis = sma(typical, period: period)
        for index in (period - 1)..<count {
            guard let mean = basis[index] else { continue }
            let window = typical[(index - period + 1)...index]
            let meanDeviation = window.reduce(0) { $0 + abs($1 - mean) } / Double(period)
            result[index] = meanDeviation == 0 ? 0 : (typical[index] - mean) / (0.015 * meanDeviation)
        }
        return result
    }

    /// Money Flow Index: RSI's formula applied to volume-weighted typical price instead of raw
    /// price — a "volume-weighted RSI," pinned 0–100.
    public static func mfi(
        highs: [Double],
        lows: [Double],
        closes: [Double],
        volumes: [Double],
        period: Int
    ) -> [Double?] {
        let count = closes.count
        var result = [Double?](repeating: nil, count: count)
        guard period > 0, count > period, highs.count == count, lows.count == count, volumes.count == count else {
            return result
        }

        let typical = (0..<count).map { (highs[$0] + lows[$0] + closes[$0]) / 3 }
        var positiveFlow = [Double](repeating: 0, count: count)
        var negativeFlow = [Double](repeating: 0, count: count)
        for index in 1..<count {
            let rawFlow = typical[index] * volumes[index]
            if typical[index] > typical[index - 1] {
                positiveFlow[index] = rawFlow
            } else if typical[index] < typical[index - 1] {
                negativeFlow[index] = rawFlow
            }
        }

        for index in period..<count {
            let window = (index - period + 1)...index
            let positiveSum = window.reduce(0.0) { $0 + positiveFlow[$1] }
            let negativeSum = window.reduce(0.0) { $0 + negativeFlow[$1] }
            if negativeSum == 0 {
                result[index] = positiveSum == 0 ? 50 : 100
            } else {
                result[index] = 100 - 100 / (1 + positiveSum / negativeSum)
            }
        }
        return result
    }

    /// Williams %R: like Stochastic's %K, but expressed on a −100…0 scale instead of 0…100 (and
    /// inverted — 0 is "at the high," −100 is "at the low").
    public static func williamsR(highs: [Double], lows: [Double], closes: [Double], period: Int) -> [Double?] {
        let count = closes.count
        var result = [Double?](repeating: nil, count: count)
        guard period > 0, count >= period, highs.count == count, lows.count == count else { return result }
        for index in (period - 1)..<count {
            let window = (index - period + 1)...index
            let highest = highs[window].max() ?? 0
            let lowest = lows[window].min() ?? 0
            result[index] = highest == lowest ? -50 : -100 * (highest - closes[index]) / (highest - lowest)
        }
        return result
    }

    /// Rate of Change: percentage change from `period` bars ago. `nil` wherever the comparison
    /// value is zero, since a percentage change from zero is undefined rather than infinite-in-practice.
    public static func rateOfChange(_ values: [Double], period: Int) -> [Double?] {
        let count = values.count
        var result = [Double?](repeating: nil, count: count)
        guard period > 0, count > period else { return result }
        for index in period..<count {
            let previous = values[index - period]
            guard previous != 0 else { continue }
            result[index] = 100 * (values[index] - previous) / previous
        }
        return result
    }

    /// Momentum: the same comparison as `rateOfChange`, as a raw difference instead of a percentage
    /// — useful on instruments (or panes) where a percentage isn't the natural unit.
    public static func momentum(_ values: [Double], period: Int) -> [Double?] {
        let count = values.count
        var result = [Double?](repeating: nil, count: count)
        guard period > 0, count > period else { return result }
        for index in period..<count {
            result[index] = values[index] - values[index - period]
        }
        return result
    }

    /// Chaikin Money Flow: a rolling average of the "money flow multiplier"
    /// `((close − low) − (high − close)) / (high − low)` weighted by volume — where in its range a
    /// candle closed, scaled by how much traded.
    public static func chaikinMoneyFlow(
        highs: [Double],
        lows: [Double],
        closes: [Double],
        volumes: [Double],
        period: Int
    ) -> [Double?] {
        let count = closes.count
        var result = [Double?](repeating: nil, count: count)
        guard period > 0, count >= period, highs.count == count, lows.count == count, volumes.count == count else {
            return result
        }

        var moneyFlowVolume = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let range = highs[index] - lows[index]
            let multiplier = range == 0 ? 0 : ((closes[index] - lows[index]) - (highs[index] - closes[index])) / range
            moneyFlowVolume[index] = multiplier * volumes[index]
        }

        for index in (period - 1)..<count {
            let window = (index - period + 1)...index
            let volumeSum = window.reduce(0.0) { $0 + volumes[$1] }
            guard volumeSum > 0 else { continue }
            result[index] = window.reduce(0.0) { $0 + moneyFlowVolume[$1] } / volumeSum
        }
        return result
    }
}
