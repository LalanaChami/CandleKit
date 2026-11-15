import Foundation

// Market data tools (roadmap phase 12, `docs/plans/market-tools.md`). Pure Foundation like the rest
// of Core: the app owns the connection and feeds values in; nothing here talks to an exchange.

/// Which side of the book a level is on.
public enum OrderBookSide: String, Sendable, Hashable, Codable, CaseIterable {
    /// Buyers waiting below the market.
    case bid
    /// Sellers waiting above the market.
    case ask
}

/// The total size resting at one price.
public struct OrderBookLevel: Sendable, Hashable, Codable {
    public var price: Double
    public var size: Double

    public init(price: Double, size: Double) {
        self.price = price
        self.size = size
    }
}

/// A change to one price level. `size` is the new total at that price, not a difference;
/// zero (or a negative or non-finite size) removes the level.
public struct OrderBookUpdate: Sendable, Hashable, Codable {
    public var side: OrderBookSide
    public var price: Double
    public var size: Double

    public init(side: OrderBookSide, price: Double, size: Double) {
        self.side = side
        self.price = price
        self.size = size
    }
}

/// A level 2 order book: the size resting at each price on both sides.
///
/// Both sides stay sorted best-first, so index 0 is always the best price. Two levels are the same
/// level when their prices are equal as `Double`; a feed that sends the same price text always
/// parses to the same value.
public struct OrderBook: Sendable, Equatable {
    /// Buy levels, highest price first, so `bids[0]` is the best bid.
    public private(set) var bids: [OrderBookLevel]
    /// Sell levels, lowest price first, so `asks[0]` is the best ask.
    public private(set) var asks: [OrderBookLevel]

    /// Levels may be passed in any order. A level with a non-finite or non-positive price or size
    /// is dropped, and when a price appears twice the later one wins.
    public init(bids: [OrderBookLevel] = [], asks: [OrderBookLevel] = []) {
        self.bids = Self.cleaned(bids, side: .bid)
        self.asks = Self.cleaned(asks, side: .ask)
    }

    /// `true` when neither side has a level.
    public var isEmpty: Bool { bids.isEmpty && asks.isEmpty }

    /// The highest price a buyer is waiting at.
    public var bestBid: OrderBookLevel? { bids.first }

    /// The lowest price a seller is waiting at.
    public var bestAsk: OrderBookLevel? { asks.first }

    /// Halfway between the best bid and best ask; `nil` unless both exist.
    public var midPrice: Double? {
        guard let bid = bids.first, let ask = asks.first else { return nil }
        return (bid.price + ask.price) / 2
    }

    /// Best ask minus best bid; `nil` unless both exist. Negative when the book is crossed.
    public var spread: Double? {
        guard let bid = bids.first, let ask = asks.first else { return nil }
        return ask.price - bid.price
    }

    /// The spread as a share of the mid price, in basis points (1 bp = 0.01%).
    public var spreadBasisPoints: Double? {
        guard let spread = spread, let mid = midPrice, mid != 0 else { return nil }
        return spread / mid * 10_000
    }

    /// `true` when the best bid is at or above the best ask, which means the data is inconsistent
    /// (usually a missed update).
    public var isCrossed: Bool {
        guard let bid = bids.first, let ask = asks.first else { return false }
        return bid.price >= ask.price
    }

    /// The levels of one side, best price first.
    public func levels(_ side: OrderBookSide) -> [OrderBookLevel] {
        side == .bid ? bids : asks
    }

    /// Sets, replaces or removes one level, keeping the side sorted. An update whose price is not
    /// finite or not positive is ignored.
    public mutating func apply(_ update: OrderBookUpdate) {
        guard update.price.isFinite, update.price > 0 else { return }
        switch update.side {
        case .bid: Self.apply(update, to: &bids, side: .bid)
        case .ask: Self.apply(update, to: &asks, side: .ask)
        }
    }

    /// Applies several updates in order.
    public mutating func apply(_ updates: [OrderBookUpdate]) {
        for update in updates {
            apply(update)
        }
    }

    /// Replaces the whole book, for a fresh snapshot. Input is cleaned the same way `init` does.
    public mutating func reset(bids: [OrderBookLevel], asks: [OrderBookLevel]) {
        self.bids = Self.cleaned(bids, side: .bid)
        self.asks = Self.cleaned(asks, side: .ask)
    }

    /// A copy holding only the best `depth` levels on each side.
    public func trimmed(depth: Int) -> OrderBook {
        var copy = self
        let keep = max(0, depth)
        if copy.bids.count > keep { copy.bids.removeSubrange(keep...) }
        if copy.asks.count > keep { copy.asks.removeSubrange(keep...) }
        return copy
    }

    // MARK: Internals

    private static func isUsable(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }

    /// `true` when `a` sorts before `b` on this side (a better price).
    private static func isBetter(_ a: Double, than b: Double, side: OrderBookSide) -> Bool {
        side == .bid ? a > b : a < b
    }

    private static func cleaned(_ levels: [OrderBookLevel], side: OrderBookSide) -> [OrderBookLevel] {
        var sizeByPrice: [Double: Double] = [:]
        for level in levels where isUsable(level.price) && isUsable(level.size) {
            sizeByPrice[level.price] = level.size
        }
        return sizeByPrice
            .map { OrderBookLevel(price: $0.key, size: $0.value) }
            .sorted { isBetter($0.price, than: $1.price, side: side) }
    }

    /// Binary search: the index of `price` if present, otherwise where it would be inserted.
    private static func position(
        of price: Double, in levels: [OrderBookLevel], side: OrderBookSide
    ) -> (index: Int, found: Bool) {
        var low = 0
        var high = levels.count
        while low < high {
            let mid = (low + high) / 2
            if isBetter(levels[mid].price, than: price, side: side) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return (low, low < levels.count && levels[low].price == price)
    }

    private static func apply(_ update: OrderBookUpdate, to levels: inout [OrderBookLevel], side: OrderBookSide) {
        let (index, found) = position(of: update.price, in: levels, side: side)
        if isUsable(update.size) {
            if found {
                levels[index].size = update.size
            } else {
                levels.insert(OrderBookLevel(price: update.price, size: update.size), at: index)
            }
        } else if found {
            levels.remove(at: index)
        }
    }
}
