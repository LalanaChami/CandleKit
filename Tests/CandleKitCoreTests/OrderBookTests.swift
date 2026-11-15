import Foundation
import Testing
@testable import CandleKitCore

private func level(_ price: Double, _ size: Double) -> OrderBookLevel { OrderBookLevel(price: price, size: size) }

/// Bids 100.0…98.0, asks 100.5…102.5. Passed deliberately unsorted to prove `init` sorts.
private var sampleBook: OrderBook {
    OrderBook(
        bids: [level(99.0, 4.0), level(100.0, 1.5), level(98.0, 3.0), level(99.5, 2.0), level(98.5, 0.5)],
        asks: [level(101.5, 1.5), level(100.5, 1.0), level(102.5, 0.5), level(101.0, 2.5), level(102.0, 6.0)]
    )
}

private func close(_ a: Double?, _ b: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) < 1e-9
}

@Suite("Order book")
struct OrderBookTests {
    @Test func initSorts() {
        #expect(sampleBook.bids.map(\.price) == [100, 99.5, 99, 98.5, 98])
        #expect(sampleBook.asks.map(\.price) == [100.5, 101, 101.5, 102, 102.5])
    }

    @Test func bestAndSpread() {
        let book = sampleBook
        #expect(book.bestBid == level(100, 1.5))
        #expect(book.bestAsk == level(100.5, 1.0))
        #expect(close(book.midPrice, 100.25))
        #expect(close(book.spread, 0.5))
        #expect(close(book.spreadBasisPoints, 49.87531172069826))
        #expect(book.isCrossed == false)
        #expect(book.levels(.bid) == book.bids)
        #expect(book.levels(.ask) == book.asks)
    }

    @Test func emptyBook() {
        let book = OrderBook()
        #expect(book.isEmpty)
        #expect(book.bestBid == nil)
        #expect(book.bestAsk == nil)
        #expect(book.midPrice == nil)
        #expect(book.spread == nil)
        #expect(book.spreadBasisPoints == nil)
        #expect(book.isCrossed == false)
    }

    @Test func oneSided() {
        let book = OrderBook(bids: [level(100, 1)])
        #expect(book.midPrice == nil)
        #expect(book.spread == nil)
        #expect(book.spreadBasisPoints == nil)
        #expect(book.bestBid == level(100, 1))
        #expect(book.isEmpty == false)
    }

    @Test func initDropsBadLevels() {
        let book = OrderBook(bids: [
            level(100, 1), level(.nan, 1), level(99, 0), level(98, -1), level(-5, 1), level(97, .infinity),
        ])
        #expect(book.bids.map(\.price) == [100])
    }

    @Test func initLaterDuplicateWins() {
        let book = OrderBook(bids: [level(100, 1), level(100, 7)])
        #expect(book.bids == [level(100, 7)])
    }

    @Test func applyUpdates() {
        var book = sampleBook
        book.apply([
            OrderBookUpdate(side: .bid, price: 99.5, size: 0),
            OrderBookUpdate(side: .bid, price: 100.25, size: 0.75),
            OrderBookUpdate(side: .ask, price: 100.5, size: 3.0),
            OrderBookUpdate(side: .ask, price: 103.0, size: 1.0),
            OrderBookUpdate(side: .bid, price: 97.0, size: 0),
            OrderBookUpdate(side: .ask, price: 101.0, size: .nan),
        ])
        #expect(book.bids == [level(100.25, 0.75), level(100, 1.5), level(99, 4), level(98.5, 0.5), level(98, 3)])
        #expect(book.asks == [level(100.5, 3), level(101.5, 1.5), level(102, 6), level(102.5, 0.5), level(103, 1)])
    }

    @Test func applyIgnoresBadPrice() {
        var book = sampleBook
        book.apply(OrderBookUpdate(side: .bid, price: .nan, size: 1))
        book.apply(OrderBookUpdate(side: .bid, price: 0, size: 1))
        #expect(book == sampleBook)
    }

    @Test func crossedBook() {
        let book = OrderBook(bids: [level(101, 1)], asks: [level(100, 1)])
        #expect(book.isCrossed)
        #expect(close(book.spread, -1))
    }

    @Test func trimmed() {
        let two = sampleBook.trimmed(depth: 2)
        #expect(two.bids.map(\.price) == [100, 99.5])
        #expect(two.asks.map(\.price) == [100.5, 101])
        #expect(sampleBook.trimmed(depth: 0).isEmpty)
        #expect(sampleBook.trimmed(depth: -4).isEmpty)
        #expect(sampleBook.trimmed(depth: 99) == sampleBook)
    }

    @Test func resetReplaces() {
        var book = sampleBook
        book.reset(bids: [level(50, 1)], asks: [level(51, 2)])
        #expect(book == OrderBook(bids: [level(50, 1)], asks: [level(51, 2)]))
    }
}
