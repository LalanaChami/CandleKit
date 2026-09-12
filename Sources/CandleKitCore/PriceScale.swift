import Foundation

/// Maps a numeric domain onto a pixel range. The range may be inverted (for example, bottom-to-top).
public struct LinearScale: Hashable, Sendable {
    public var domain: ClosedRange<Double>
    public var rangeStart: Double
    public var rangeEnd: Double

    public init(domain: ClosedRange<Double>, rangeStart: Double, rangeEnd: Double) {
        self.domain = domain
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }

    public func map(_ value: Double) -> Double {
        let span = domain.upperBound - domain.lowerBound
        guard span != 0 else { return (rangeStart + rangeEnd) / 2 }
        return rangeStart + (value - domain.lowerBound) / span * (rangeEnd - rangeStart)
    }

    public func invert(_ position: Double) -> Double {
        let span = rangeEnd - rangeStart
        guard span != 0 else { return domain.lowerBound }
        return domain.lowerBound + (position - rangeStart) / span * (domain.upperBound - domain.lowerBound)
    }
}

/// Evenly spaced, human-friendly price levels.
public struct PriceTicks: Hashable, Sendable {
    public let values: [Double]
    public let step: Double

    /// Decimal places needed to tell adjacent ticks apart.
    public var fractionDigits: Int { PriceScale.fractionDigits(forStep: step) }
}

public enum PriceScale {
    /// The price range covering every visible candle and indicator value, with padding above and below.
    public static func autoRange(
        for candles: [Candle],
        in visible: Range<Int>,
        including series: [[Double?]] = [],
        paddingFraction: Double = 0.08
    ) -> ClosedRange<Double>? {
        let range = visible.clamped(to: 0..<candles.count)
        guard !range.isEmpty else { return nil }

        var low = Double.infinity
        var high = -Double.infinity
        for index in range {
            low = min(low, candles[index].low)
            high = max(high, candles[index].high)
        }
        for values in series {
            for index in range where index < values.count {
                if let value = values[index], value.isFinite {
                    low = min(low, value)
                    high = max(high, value)
                }
            }
        }
        guard low.isFinite, high.isFinite else { return nil }
        if low > high { swap(&low, &high) }

        if high == low {
            let padding = abs(high) * 0.01
            let safePadding = padding > 0 ? padding : 1
            return (low - safePadding)...(high + safePadding)
        }
        let padding = (high - low) * paddingFraction
        return (low - padding)...(high + padding)
    }

    /// The value range covering every visible point of a set of indicator series.
    ///
    /// Used for indicator panes, which scale to their own values rather than to price. `required`
    /// is folded in unpadded so a pinned range — RSI's 0...100 — stays exactly that rather than
    /// drifting outward by the padding fraction each render.
    ///
    /// Returns `nil` when nothing is visible, which the caller should treat as "draw no pane
    /// content" rather than substituting an arbitrary range.
    public static func autoRange(
        forSeries series: [[Double?]],
        in visible: Range<Int>,
        required: ClosedRange<Double>? = nil,
        paddingFraction: Double = 0.1
    ) -> ClosedRange<Double>? {
        var low = Double.infinity
        var high = -Double.infinity

        for values in series {
            let range = visible.clamped(to: 0..<values.count)
            for index in range {
                guard let value = values[index], value.isFinite else { continue }
                low = min(low, value)
                high = max(high, value)
            }
        }

        if low.isFinite, high.isFinite, low <= high {
            if high == low {
                let padding = abs(high) * 0.01
                let safePadding = padding > 0 ? padding : 1
                low -= safePadding
                high += safePadding
            } else {
                let padding = (high - low) * paddingFraction
                low -= padding
                high += padding
            }
        } else if required == nil {
            return nil
        } else {
            low = .infinity
            high = -.infinity
        }

        if let required {
            low = min(low, required.lowerBound)
            high = max(high, required.upperBound)
        }
        guard low.isFinite, high.isFinite, low < high else { return nil }
        return low...high
    }

    /// Tick values at multiples of 1, 2 or 5 × 10ⁿ, targeting roughly `approximateCount` ticks.
    public static func niceTicks(in range: ClosedRange<Double>, approximateCount: Int) -> PriceTicks {
        let span = range.upperBound - range.lowerBound
        guard span > 0, span.isFinite, approximateCount > 0 else {
            return PriceTicks(values: [], step: 0)
        }
        let step = niceStep(span / Double(approximateCount))
        let first = (range.lowerBound / step).rounded(.up)
        let last = (range.upperBound / step).rounded(.down)
        guard first <= last, abs(first) < 1e12, abs(last) < 1e12 else {
            return PriceTicks(values: [], step: step)
        }
        let values = stride(from: first, through: last, by: 1).map { $0 * step }
        return PriceTicks(values: values, step: step)
    }

    static func niceStep(_ rough: Double) -> Double {
        let magnitude = pow(10, log10(rough).rounded(.down))
        let residual = rough / magnitude
        let nice: Double
        if residual <= 1 {
            nice = 1
        } else if residual <= 2 {
            nice = 2
        } else if residual <= 5 {
            nice = 5
        } else {
            nice = 10
        }
        return nice * magnitude
    }

    public static func fractionDigits(forStep step: Double) -> Int {
        guard step > 0, step.isFinite else { return 0 }
        // The epsilon absorbs log10 results like -0.9999999999999999 for 0.1.
        return max(0, Int(-(log10(step) + 1e-9).rounded(.down)))
    }

    /// A reasonable display precision when the caller doesn't specify one:
    /// two decimals at or above 1, and four significant decimals below that.
    public static func suggestedFractionDigits(forPrice price: Double) -> Int {
        let magnitude = abs(price)
        guard magnitude.isFinite, magnitude > 0 else { return 2 }
        if magnitude >= 1 { return 2 }
        let leadingZeros = Int(-log10(magnitude).rounded(.down)) - 1
        return min(10, leadingZeros + 4)
    }
}
