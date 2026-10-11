import Foundation

/// Reduces a series to a bounded number of candles.
///
/// Used by surfaces with a fixed draw budget, such as a home-screen widget, so drawing cost does not
/// depend on how long the series is.
public enum CandleAggregator {
    /// Merges consecutive candles into at most `maxCount` candles.
    ///
    /// Bucket `i` of `m` covers source indices `i * n / m ..< (i + 1) * n / m` (integer division), so
    /// bucket sizes differ by at most one. Each merged candle takes the time and open of its first
    /// source candle, the close of its last, the highest high, the lowest low and the summed volume.
    /// A series already within `maxCount` is returned unchanged. `maxCount < 1` returns an empty array.
    public static func downsample(_ candles: [Candle], maxCount: Int) -> [Candle] {
        guard maxCount >= 1 else { return [] }
        let n = candles.count
        guard n > maxCount else { return candles }

        var result: [Candle] = []
        result.reserveCapacity(maxCount)
        for bucket in 0..<maxCount {
            let start = bucket * n / maxCount
            let end = (bucket + 1) * n / maxCount
            guard start < end else { continue }
            var merged = candles[start]
            for index in (start + 1)..<end {
                let c = candles[index]
                merged.high = Swift.max(merged.high, c.high)
                merged.low = Swift.min(merged.low, c.low)
                merged.volume += c.volume
            }
            merged.close = candles[end - 1].close
            result.append(merged)
        }
        return result
    }
}
