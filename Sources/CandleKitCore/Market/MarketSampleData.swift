import Foundation

/// Deterministic fake order books and trades for previews, demos and tests.
public enum MarketSampleData {
    /// A book with `levels` levels per side around `midPrice`, one `tick` apart, sizes growing
    /// loosely with distance from the mid. The same arguments always give the same book.
    public static func orderBook(
        midPrice: Double = 100, levels: Int = 25, tick: Double = 0.05, seed: UInt64 = 42
    ) -> OrderBook {
        let step = tick.isFinite && tick > 0 ? tick : 0.01
        var generator = SplitMix64(seed: seed)
        var bids: [OrderBookLevel] = []
        var asks: [OrderBookLevel] = []

        func size(_ index: Int) -> Double {
            ((0.5 + generator.nextDouble() * 2) * (1 + Double(index) * 0.15) * 100).rounded() / 100
        }

        for index in 0..<max(0, levels) {
            let offset = step * (Double(index) + 0.5)
            let bidSize = size(index)
            let askSize = size(index)
            if midPrice - offset > 0 {
                bids.append(OrderBookLevel(price: midPrice - offset, size: bidSize))
            }
            asks.append(OrderBookLevel(price: midPrice + offset, size: askSize))
        }
        return OrderBook(bids: bids, asks: asks)
    }

    /// `count` trades, `spacing` seconds apart starting at `start`, prices walking from `startPrice`
    /// in steps of `tick`. The same arguments always give the same trades.
    public static func trades(
        count: Int,
        start: Date = Date(timeIntervalSince1970: 1_767_225_600), // 2026-01-01 00:00 UTC
        spacing: TimeInterval = 1,
        startPrice: Double = 100,
        tick: Double = 0.05,
        seed: UInt64 = 42
    ) -> [MarketTrade] {
        let step = tick.isFinite && tick > 0 ? tick : 0.01
        var generator = SplitMix64(seed: seed)
        var trades: [MarketTrade] = []
        trades.reserveCapacity(max(0, count))
        var price = max(step, startPrice)
        var side = MarketTrade.Side.buy

        for index in 0..<max(0, count) {
            let move = Int((generator.nextDouble() * 5).rounded(.down)) - 2
            price = max(step, price + Double(move) * step)
            if move > 0 { side = .buy } else if move < 0 { side = .sell }
            let size = ((0.01 + generator.nextDouble() * 2) * 100).rounded() / 100
            trades.append(MarketTrade(
                id: "s\(seed)-\(index)",
                time: start.addingTimeInterval(Double(index) * spacing),
                price: price,
                size: size,
                side: side
            ))
        }
        return trades
    }
}
