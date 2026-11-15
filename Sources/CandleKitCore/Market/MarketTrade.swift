import Foundation

/// One executed trade (a "print" on the tape).
public struct MarketTrade: Sendable, Hashable, Identifiable {
    /// Who crossed the spread to make the trade happen (the aggressor, or taker).
    ///
    /// Some feeds report the maker's side instead. Flip it when building the trade: a trade whose
    /// maker was selling is a `.buy` here.
    public enum Side: String, Sendable, Hashable, Codable, CaseIterable {
        /// A buyer took the offer. Usually drawn green.
        case buy
        /// A seller hit the bid. Usually drawn red.
        case sell
        /// The feed didn't say. See `TradeMath.tickRuleSide`.
        case unknown
    }

    /// Unique within the feed, for example the exchange's trade id.
    public var id: String
    public var time: Date
    public var price: Double
    public var size: Double
    public var side: Side

    public init(id: String, time: Date, price: Double, size: Double, side: Side = .unknown) {
        self.id = id
        self.time = time
        self.price = price
        self.size = size
        self.side = side
    }
}

/// The most recent trades, oldest first, never more than `capacity`.
public struct TradeTape: Sendable, Equatable {
    /// The most trades kept. Older ones are dropped.
    public let capacity: Int
    /// Oldest first; the newest trade is last.
    public private(set) var trades: [MarketTrade]

    /// - Parameter capacity: values below 1 are treated as 1.
    public init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
        trades = []
    }

    /// Adds a trade as the newest. A trade with the same `id` as the current newest is ignored
    /// (feeds resend the last trade on reconnect).
    public mutating func append(_ trade: MarketTrade) {
        if let newest = trades.last, newest.id == trade.id { return }
        trades.append(trade)
        if trades.count > capacity {
            trades.removeFirst(trades.count - capacity)
        }
    }

    /// Adds several trades, oldest first.
    public mutating func append(contentsOf newTrades: [MarketTrade]) {
        for trade in newTrades {
            append(trade)
        }
    }

    /// Empties the tape, for example when the symbol changes.
    public mutating func removeAll() {
        trades.removeAll()
    }
}

/// Totals over a group of trades.
public struct TradeFlow: Sendable, Equatable {
    public var buyVolume: Double
    public var sellVolume: Double
    /// Volume of trades whose aggressor isn't known.
    public var unknownVolume: Double
    public var tradeCount: Int
    /// Sum of price × size.
    public var notional: Double

    public init(
        buyVolume: Double = 0, sellVolume: Double = 0, unknownVolume: Double = 0, tradeCount: Int = 0,
        notional: Double = 0
    ) {
        self.buyVolume = buyVolume
        self.sellVolume = sellVolume
        self.unknownVolume = unknownVolume
        self.tradeCount = tradeCount
        self.notional = notional
    }

    /// Buy, sell and unknown volume together.
    public var totalVolume: Double { buyVolume + sellVolume + unknownVolume }

    /// Buy volume minus sell volume. Positive means buyers were the aggressors.
    public var delta: Double { buyVolume - sellVolume }

    /// Volume-weighted average price of these trades; `nil` with no volume.
    public var vwap: Double? {
        let total = totalVolume
        return total > 0 ? notional / total : nil
    }

    /// Buy volume as a share (0...1) of buy plus sell volume; `nil` when both are zero.
    public var buyShare: Double? {
        let known = buyVolume + sellVolume
        return known > 0 ? buyVolume / known : nil
    }

    /// Adds one trade. A trade whose price or size is not finite, or whose size is `<= 0`, is skipped.
    public mutating func add(_ trade: MarketTrade) {
        guard trade.price.isFinite, trade.size.isFinite, trade.size > 0 else { return }
        switch trade.side {
        case .buy: buyVolume += trade.size
        case .sell: sellVolume += trade.size
        case .unknown: unknownVolume += trade.size
        }
        tradeCount += 1
        notional += trade.price * trade.size
    }
}

/// Pure calculations on trades.
public enum TradeMath {
    /// Totals for `trades`.
    public static func flow(of trades: [MarketTrade]) -> TradeFlow {
        var flow = TradeFlow()
        for trade in trades {
            flow.add(trade)
        }
        return flow
    }

    /// Guesses the aggressor for a feed that doesn't report it (the "tick rule"): a higher price
    /// than the previous trade is a buy, a lower one a sell, an equal one keeps `previousSide`.
    public static func tickRuleSide(
        price: Double, previousPrice: Double?, previousSide: MarketTrade.Side
    ) -> MarketTrade.Side {
        guard let previousPrice else { return previousSide }
        if price > previousPrice { return .buy }
        if price < previousPrice { return .sell }
        return previousSide
    }
}
