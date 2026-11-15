import Foundation
import Testing
@testable import CandleKitCore

@Suite("Market sample data")
struct MarketSampleDataTests {
    @Test func bookIsDeterministic() {
        #expect(MarketSampleData.orderBook() == MarketSampleData.orderBook())
        #expect(MarketSampleData.orderBook(seed: 1) != MarketSampleData.orderBook(seed: 2))
    }

    @Test func bookShape() throws {
        let book = MarketSampleData.orderBook()
        #expect(book.bids.count == 25)
        #expect(book.asks.count == 25)
        #expect(book.isCrossed == false)
        let mid = try #require(book.midPrice)
        #expect(abs(mid - 100) < 1e-9)
        #expect(zip(book.bids, book.bids.dropFirst()).allSatisfy { $0.price > $1.price })
        #expect(zip(book.asks, book.asks.dropFirst()).allSatisfy { $0.price < $1.price })
        #expect((book.bids + book.asks).allSatisfy { $0.size > 0 })
    }

    @Test func bookZeroLevels() {
        #expect(MarketSampleData.orderBook(levels: 0).isEmpty)
        #expect(MarketSampleData.orderBook(levels: -3).isEmpty)
    }

    @Test func tradesAreDeterministic() {
        let trades = MarketSampleData.trades(count: 100)
        #expect(trades == MarketSampleData.trades(count: 100))
        #expect(Set(trades.map(\.id)).count == 100)
        #expect(zip(trades, trades.dropFirst()).allSatisfy { $0.time < $1.time })
        #expect(MarketSampleData.trades(count: 0).isEmpty)
    }

    @Test func tradesStayPositive() {
        let trades = MarketSampleData.trades(count: 500, startPrice: 0.1, tick: 0.05)
        #expect(trades.count == 500)
        #expect(trades.allSatisfy { $0.price > 0 && $0.size > 0 })
    }
}
