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

private func close(_ a: [Double], _ b: [Double]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 }
}

@Suite("Order book maths")
struct OrderBookMathTests {
    @Test func cumulativeBids() {
        #expect(close(OrderBookMath.cumulative(sampleBook.bids).map(\.cumulativeSize), [1.5, 3.5, 7.5, 8.0, 11.0]))
    }

    @Test func cumulativeAsks() {
        #expect(close(OrderBookMath.cumulative(sampleBook.asks).map(\.cumulativeSize), [1.0, 3.5, 5.0, 11.0, 11.5]))
    }

    @Test func imbalance() {
        #expect(close(OrderBookMath.imbalance(of: sampleBook, depth: 1), 0.2))
        #expect(close(OrderBookMath.imbalance(of: sampleBook, depth: 3), 0.2))
        #expect(close(OrderBookMath.imbalance(of: sampleBook, depth: 5), -0.022222222222222223))
        #expect(close(OrderBookMath.imbalance(of: sampleBook, depth: 10), -0.022222222222222223))
        #expect(OrderBookMath.imbalance(of: sampleBook, depth: 0) == nil)
        #expect(OrderBookMath.imbalance(of: OrderBook(), depth: 5) == nil)
    }

    @Test func groupBidsRoundDown() {
        let grouped = OrderBookMath.grouped(sampleBook.bids, side: .bid, tick: 1.0)
        #expect(close(grouped.map(\.price), [100, 99, 98]))
        #expect(close(grouped.map(\.size), [1.5, 6.0, 3.5]))
    }

    @Test func groupAsksRoundUp() {
        let grouped = OrderBookMath.grouped(sampleBook.asks, side: .ask, tick: 1.0)
        #expect(close(grouped.map(\.price), [101, 102, 103]))
        #expect(close(grouped.map(\.size), [3.5, 7.5, 0.5]))
    }

    @Test func groupSmallTicks() {
        let bids = OrderBookMath.grouped(
            [level(0.3, 1), level(0.29, 2), level(0.21, 3), level(0.2, 4)], side: .bid, tick: 0.1
        )
        #expect(close(bids.map(\.price), [0.3, 0.2]))
        #expect(close(bids.map(\.size), [1, 9]))

        let asks = OrderBookMath.grouped(
            [level(0.3, 1), level(0.31, 2), level(0.4, 3), level(0.41, 4)], side: .ask, tick: 0.1
        )
        #expect(close(asks.map(\.price), [0.3, 0.4, 0.5]))
        #expect(close(asks.map(\.size), [1, 5, 4]))
    }

    @Test func groupBadTickIsIdentity() {
        for tick in [0.0, -1.0, Double.nan] {
            #expect(OrderBookMath.grouped(sampleBook.bids, side: .bid, tick: tick) == sampleBook.bids)
        }
    }

    @Test func buckets() {
        let result = OrderBookMath.buckets(of: sampleBook, priceRange: 98...103, bucketCount: 5)
        #expect(close(result.bids, [3.5, 6.0, 1.5, 0, 0]))
        #expect(close(result.asks, [0, 0, 1.0, 4.0, 6.5]))

        let none = OrderBookMath.buckets(of: sampleBook, priceRange: 98...103, bucketCount: 0)
        #expect(none.bids.isEmpty && none.asks.isEmpty)
        let flat = OrderBookMath.buckets(of: sampleBook, priceRange: 100...100, bucketCount: 5)
        #expect(flat.bids.isEmpty && flat.asks.isEmpty)
    }

    @Test func ladderRaw() {
        let ladder = OrderBookLadder(book: sampleBook, rowsPerSide: 3)
        #expect(ladder.bids.map(\.price) == [100, 99.5, 99])
        #expect(ladder.asks.map(\.price) == [100.5, 101, 101.5])
        #expect(close(ladder.maxCumulativeSize, 7.5))
        #expect(close(ladder.bids.map(\.depthFraction), [0.2, 0.4666666666666667, 1.0]))
        #expect(close(ladder.asks.map(\.depthFraction), [0.13333333333333333, 0.4666666666666667, 0.6666666666666666]))
        #expect(ladder.bids.allSatisfy { $0.side == .bid })
        #expect(ladder.asks.allSatisfy { $0.side == .ask })
    }

    @Test func ladderGrouped() {
        let ladder = OrderBookLadder(book: sampleBook, rowsPerSide: 2, tick: 1.0)
        #expect(close(ladder.bids.map(\.price), [100, 99]))
        #expect(close(ladder.bids.map(\.size), [1.5, 6.0]))
        #expect(close(ladder.bids.map(\.cumulativeSize), [1.5, 7.5]))
        #expect(close(ladder.asks.map(\.price), [101, 102]))
        #expect(close(ladder.asks.map(\.size), [3.5, 7.5]))
        #expect(close(ladder.asks.map(\.cumulativeSize), [3.5, 11.0]))
        #expect(close(ladder.maxCumulativeSize, 11.0))
    }

    @Test func ladderEmpty() {
        let empty = OrderBookLadder(book: OrderBook(), rowsPerSide: 5)
        #expect(empty.bids.isEmpty && empty.asks.isEmpty && empty.maxCumulativeSize == 0)
        let noRows = OrderBookLadder(book: sampleBook, rowsPerSide: 0)
        #expect(noRows.bids.isEmpty && noRows.asks.isEmpty && noRows.maxCumulativeSize == 0)
    }

    @Test func depthCurve() throws {
        let curve = try #require(DepthCurve(book: sampleBook, window: 0.01))
        #expect(close(curve.midPrice, 100.25))
        #expect(curve.bids.map(\.price) == [100, 99.5])
        #expect(close(curve.bids.map(\.cumulativeSize), [1.5, 3.5]))
        #expect(curve.asks.map(\.price) == [100.5, 101])
        #expect(close(curve.asks.map(\.cumulativeSize), [1.0, 3.5]))
        #expect(close(curve.maxCumulativeSize, 3.5))
        #expect(curve.priceRange == 99.5...101)
    }

    @Test func depthCurveWholeBook() throws {
        let curve = try #require(DepthCurve(book: sampleBook, window: 0))
        #expect(curve.bids.count == 5)
        #expect(curve.asks.count == 5)
        #expect(close(curve.maxCumulativeSize, 11.5))
    }

    @Test func depthCurveNeedsBothSides() {
        #expect(DepthCurve(book: OrderBook(bids: [level(100, 1)])) == nil)
    }
}
