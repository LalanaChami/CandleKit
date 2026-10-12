import Foundation

/// Volume-weighted average price from a chosen candle onward (anchored VWAP), with optional
/// volume-weighted standard-deviation bands.
public enum AnchoredVWAP {
    public struct Output: Sendable, Equatable {
        public var vwap: [Double?]
        public var upper: [Double?]
        public var lower: [Double?]
    }

    /// - Parameters:
    ///   - anchorIndex: first candle included; candles before it get `nil`.
    ///   - bandMultiplier: standard deviations for the bands; `0` leaves the band arrays `nil`.
    ///
    /// Typical price is `(high + low + close) / 3`. A candle with no volume contributes nothing, and
    /// the value stays `nil` until some volume has accumulated.
    public static func compute(candles: [Candle], anchorIndex: Int, bandMultiplier: Double = 0) -> Output {
        let count = candles.count
        var vwap = [Double?](repeating: nil, count: count)
        var upper = [Double?](repeating: nil, count: count)
        var lower = [Double?](repeating: nil, count: count)
        guard count > 0, anchorIndex < count else { return Output(vwap: vwap, upper: upper, lower: lower) }
        var sumPV = 0.0
        var sumPPV = 0.0
        var sumV = 0.0
        for index in max(0, anchorIndex)..<count {
            let candle = candles[index]
            let price = (candle.high + candle.low + candle.close) / 3
            sumPV += price * candle.volume
            sumPPV += price * price * candle.volume
            sumV += candle.volume
            guard sumV > 0 else { continue }
            let mean = sumPV / sumV
            vwap[index] = mean
            if bandMultiplier > 0 {
                // Volume-weighted variance, floored at zero against rounding error.
                let deviation = max(0, sumPPV / sumV - mean * mean).squareRoot()
                upper[index] = mean + bandMultiplier * deviation
                lower[index] = mean - bandMultiplier * deviation
            }
        }
        return Output(vwap: vwap, upper: upper, lower: lower)
    }
}

/// An indicator form of anchored VWAP, anchored to a *time* so it stays put when history is
/// prepended. Add it with `ChartIndicator(AnchoredVWAPIndicator(anchor: date))` or
/// `.anchoredVWAP(from:)`. Not in the picker catalog, because choosing a date needs your own UI.
public struct AnchoredVWAPIndicator: Indicator {
    public static let identifier = "anchored-vwap"
    public static let displayName = "Anchored VWAP"
    public static let category = IndicatorCategory.volume

    public var parameters: [IndicatorParameter]

    /// - Parameters:
    ///   - anchor: the time to start from. The first candle at or after it is the anchor candle.
    ///   - bandMultiplier: standard-deviation bands; `0` (default) draws only the VWAP line.
    public init(anchor: Date, bandMultiplier: Double = 0) {
        parameters = [
            IndicatorParameter(key: "anchor", name: "Anchor (Unix time)",
                               kind: .number(range: 0...4_102_444_800, step: 60),
                               value: .number(anchor.timeIntervalSince1970)),
            IndicatorParameter(key: "bands", name: "Std. deviation bands",
                               kind: .number(range: 0...5, step: 0.5), value: .number(bandMultiplier)),
        ]
    }

    public var anchor: Date { Date(timeIntervalSince1970: parameters.number("anchor", default: 0)) }
    public var bandMultiplier: Double { parameters.number("bands", default: 0) }
    public var pane: IndicatorPane { .price }
    public var shortLabel: String { "AVWAP" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        // First candle not before the anchor time; a later anchor than the data gives all `nil`.
        let anchorTime = anchor
        var low = 0
        var high = candles.count
        while low < high {
            let mid = (low + high) / 2
            if candles[mid].time < anchorTime { low = mid + 1 } else { high = mid }
        }
        let output = AnchoredVWAP.compute(candles: candles, anchorIndex: low, bandMultiplier: bandMultiplier)
        var plots = [IndicatorPlot(key: "vwap", name: "AVWAP", values: output.vwap, colorRole: .series(2))]
        var fills: [IndicatorFill] = []
        if bandMultiplier > 0 {
            plots.append(IndicatorPlot(key: "upper", name: "Upper", values: output.upper,
                                       style: .line(width: 1, dash: [4, 3]), colorRole: .series(2)))
            plots.append(IndicatorPlot(key: "lower", name: "Lower", values: output.lower,
                                       style: .line(width: 1, dash: [4, 3]), colorRole: .series(2)))
            fills.append(IndicatorFill(lowerPlotKey: "lower", upperPlotKey: "upper", colorRole: .series(2), opacity: 0.08))
        }
        return IndicatorResult(plots: plots, fills: fills)
    }
}

/// Volume by price: how much traded at each price level over a stretch of candles.
public struct VolumeProfile: Sendable, Equatable {
    /// Lowest price covered (the bottom of the first bucket).
    public var lowPrice: Double
    /// Height of each bucket in price units.
    public var bucketHeight: Double
    /// Volume per bucket, lowest price first.
    public var volumes: [Double]
    /// Index of the bucket with the most volume (the first one on a tie, so the lowest price).
    public var pointOfControl: Int
    /// Buckets that together hold at least `valueAreaShare` of the volume, grown outward from the
    /// point of control; an inclusive range of bucket indices.
    public var valueArea: ClosedRange<Int>

    public var highPrice: Double { lowPrice + bucketHeight * Double(volumes.count) }
    public var totalVolume: Double { volumes.reduce(0, +) }

    /// Centre price of bucket `index`.
    public func price(ofBucket index: Int) -> Double { lowPrice + bucketHeight * (Double(index) + 0.5) }

    /// Builds a profile from `candles[range]`.
    ///
    /// Each candle's volume is spread evenly over its high-low range (a candle with no range puts
    /// it all in one bucket), the usual approximation when only OHLCV is known. Returns `nil` with
    /// no volume or an empty range. Cost is O(range × buckets touched per candle).
    ///
    /// - Parameters:
    ///   - bucketCount: number of price buckets (at least 2).
    ///   - valueAreaShare: share of volume the value area should hold, 0...1 (0.7 is customary).
    public static func compute(
        candles: [Candle],
        range: Range<Int>,
        bucketCount: Int = 24,
        valueAreaShare: Double = 0.7
    ) -> VolumeProfile? {
        let clamped = max(0, range.lowerBound)..<min(candles.count, range.upperBound)
        guard !clamped.isEmpty, bucketCount >= 2 else { return nil }
        var low = Double.infinity
        var high = -Double.infinity
        for index in clamped {
            low = min(low, candles[index].low)
            high = max(high, candles[index].high)
        }
        guard low.isFinite, high.isFinite else { return nil }
        let span = max(high - low, .leastNormalMagnitude)
        let height = span / Double(bucketCount)
        var volumes = [Double](repeating: 0, count: bucketCount)

        func bucket(of price: Double) -> Int {
            min(bucketCount - 1, max(0, Int(((price - low) / height).rounded(.down))))
        }

        for index in clamped {
            let candle = candles[index]
            guard candle.volume > 0, candle.volume.isFinite else { continue }
            let candleRange = candle.high - candle.low
            if candleRange <= height * 1e-9 {
                volumes[bucket(of: candle.low)] += candle.volume
                continue
            }
            let first = bucket(of: candle.low)
            let last = bucket(of: candle.high)
            for b in first...last {
                let bottom = low + Double(b) * height
                let overlap = min(candle.high, bottom + height) - max(candle.low, bottom)
                if overlap > 0 { volumes[b] += candle.volume * overlap / candleRange }
            }
        }

        let total = volumes.reduce(0, +)
        guard total > 0 else { return nil }
        var poc = 0
        for (b, volume) in volumes.enumerated() where volume > volumes[poc] { poc = b }

        // Grow the value area one bucket at a time toward whichever neighbour holds more.
        var lower = poc
        var upper = poc
        var covered = volumes[poc]
        let target = total * min(max(valueAreaShare, 0), 1)
        while covered < target {
            let below = lower > 0 ? volumes[lower - 1] : -1
            let above = upper < bucketCount - 1 ? volumes[upper + 1] : -1
            if below < 0 && above < 0 { break }
            if above >= below {
                upper += 1
                covered += volumes[upper]
            } else {
                lower -= 1
                covered += volumes[lower]
            }
        }
        return VolumeProfile(lowPrice: low, bucketHeight: height, volumes: volumes, pointOfControl: poc, valueArea: lower...upper)
    }
}
