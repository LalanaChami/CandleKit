import Foundation

/// A level together with the running total of size from the best price out to it.
public struct DepthLevel: Sendable, Hashable {
    public var price: Double
    public var size: Double
    public var cumulativeSize: Double

    public init(price: Double, size: Double, cumulativeSize: Double) {
        self.price = price
        self.size = size
        self.cumulativeSize = cumulativeSize
    }
}

/// Pure calculations on an order book.
public enum OrderBookMath {
    /// Merges levels into price buckets `tick` wide. Bids round **down** to a bucket and asks round
    /// **up**, so a grouped price is never better than any real level inside it. Input and output
    /// are best-first. A `tick` that is not finite or is `<= 0` returns `levels` unchanged.
    public static func grouped(_ levels: [OrderBookLevel], side: OrderBookSide, tick: Double) -> [OrderBookLevel] {
        guard tick.isFinite, tick > 0 else { return levels }
        var result: [OrderBookLevel] = []
        var lastBucket: Double?
        for level in levels {
            // The small nudge keeps a price that sits exactly on a bucket edge in that bucket when
            // the division lands a hair off (0.3 / 0.1 is 2.9999999999999996).
            let ratio = level.price / tick
            let bucket = side == .bid ? (ratio + 1e-9).rounded(.down) : (ratio - 1e-9).rounded(.up)
            if bucket == lastBucket, !result.isEmpty {
                result[result.count - 1].size += level.size
            } else {
                result.append(OrderBookLevel(price: bucket * tick, size: level.size))
                lastBucket = bucket
            }
        }
        return result
    }

    /// Running totals, best price first.
    public static func cumulative(_ levels: [OrderBookLevel]) -> [DepthLevel] {
        var total = 0.0
        return levels.map { level in
            total += level.size
            return DepthLevel(price: level.price, size: level.size, cumulativeSize: total)
        }
    }

    /// Bid size minus ask size over their sum, across the best `depth` levels of each side:
    /// +1 is all bids, −1 all asks. `nil` when there is no size at all or `depth <= 0`.
    public static func imbalance(of book: OrderBook, depth: Int) -> Double? {
        guard depth > 0 else { return nil }
        let bidSize = book.bids.prefix(depth).reduce(0) { $0 + $1.size }
        let askSize = book.asks.prefix(depth).reduce(0) { $0 + $1.size }
        let total = bidSize + askSize
        guard total > 0 else { return nil }
        return (bidSize - askSize) / total
    }

    /// Bid and ask size per price bucket across `priceRange`, for drawing the book against a price
    /// axis. Bucket 0 starts at `priceRange.lowerBound`. Levels outside the range are skipped.
    /// Returns empty arrays when `bucketCount < 1` or the range has no height.
    public static func buckets(
        of book: OrderBook, priceRange: ClosedRange<Double>, bucketCount: Int
    ) -> (bids: [Double], asks: [Double]) {
        let low = priceRange.lowerBound
        let high = priceRange.upperBound
        guard bucketCount >= 1, low.isFinite, high.isFinite, high > low else { return ([], []) }
        let height = (high - low) / Double(bucketCount)
        guard height > 0 else { return ([], []) }

        func fill(_ levels: [OrderBookLevel]) -> [Double] {
            var sizes = [Double](repeating: 0, count: bucketCount)
            for level in levels where level.price >= low && level.price <= high {
                let index = min(bucketCount - 1, max(0, Int(((level.price - low) / height).rounded(.down))))
                sizes[index] += level.size
            }
            return sizes
        }
        return (fill(book.bids), fill(book.asks))
    }
}

/// The rows an order-book ladder shows: the best levels of each side with their running totals.
public struct OrderBookLadder: Sendable, Equatable {
    /// One row of the ladder.
    public struct Row: Sendable, Hashable, Identifiable {
        public var side: OrderBookSide
        public var price: Double
        public var size: Double
        /// Size from the best price on this side out to this row.
        public var cumulativeSize: Double
        /// `cumulativeSize` as a share (0...1) of the largest running total on either side.
        public var depthFraction: Double
        public var id: Double { price }

        public init(side: OrderBookSide, price: Double, size: Double, cumulativeSize: Double, depthFraction: Double) {
            self.side = side
            self.price = price
            self.size = size
            self.cumulativeSize = cumulativeSize
            self.depthFraction = depthFraction
        }
    }

    /// Best ask first.
    public var asks: [Row]
    /// Best bid first.
    public var bids: [Row]
    /// The largest running total among the rows shown; `0` for an empty ladder.
    public var maxCumulativeSize: Double

    /// - Parameters:
    ///   - rowsPerSide: how many rows to keep on each side (values below 1 give an empty ladder).
    ///   - tick: group prices into buckets this wide first; `nil` shows the raw levels.
    public init(book: OrderBook, rowsPerSide: Int, tick: Double? = nil) {
        let count = max(0, rowsPerSide)

        func depth(_ side: OrderBookSide) -> [DepthLevel] {
            var levels = book.levels(side)
            if let tick {
                // Grouping can only merge neighbours, so `count` buckets never need more than the
                // whole side; group first, then cut.
                levels = OrderBookMath.grouped(levels, side: side, tick: tick)
            }
            return OrderBookMath.cumulative(Array(levels.prefix(count)))
        }

        let bidDepth = depth(.bid)
        let askDepth = depth(.ask)
        let largest = max(bidDepth.last?.cumulativeSize ?? 0, askDepth.last?.cumulativeSize ?? 0)

        func rows(_ levels: [DepthLevel], _ side: OrderBookSide) -> [Row] {
            levels.map {
                Row(
                    side: side, price: $0.price, size: $0.size, cumulativeSize: $0.cumulativeSize,
                    depthFraction: largest > 0 ? $0.cumulativeSize / largest : 0
                )
            }
        }

        bids = rows(bidDepth, .bid)
        asks = rows(askDepth, .ask)
        maxCumulativeSize = largest
    }
}

/// Points for a depth chart: cumulative size on each side within a window around the mid price.
public struct DepthCurve: Sendable, Equatable {
    /// Best bid first (prices descending), cumulative size rising.
    public var bids: [DepthLevel]
    /// Best ask first (prices ascending), cumulative size rising.
    public var asks: [DepthLevel]
    public var midPrice: Double
    /// From the lowest bid shown to the highest ask shown.
    public var priceRange: ClosedRange<Double>
    /// The larger of the two sides' totals.
    public var maxCumulativeSize: Double

    /// `nil` unless both sides have at least one level inside the window.
    /// - Parameter window: how far from the mid price to include, as a share of it (0.02 = ±2%).
    ///   Values that are not finite or are `<= 0` include every level.
    public init?(book: OrderBook, window: Double = 0.02) {
        guard let mid = book.midPrice else { return nil }
        var bidLevels = book.bids
        var askLevels = book.asks
        if window.isFinite, window > 0 {
            let lowest = mid * (1 - window)
            let highest = mid * (1 + window)
            bidLevels = bidLevels.filter { $0.price >= lowest }
            askLevels = askLevels.filter { $0.price <= highest }
        }
        let bidDepth = OrderBookMath.cumulative(bidLevels)
        let askDepth = OrderBookMath.cumulative(askLevels)
        guard let lastBid = bidDepth.last, let lastAsk = askDepth.last, lastBid.price <= lastAsk.price else {
            return nil
        }
        bids = bidDepth
        asks = askDepth
        midPrice = mid
        priceRange = lastBid.price...lastAsk.price
        maxCumulativeSize = max(lastBid.cumulativeSize, lastAsk.cumulativeSize)
    }
}
