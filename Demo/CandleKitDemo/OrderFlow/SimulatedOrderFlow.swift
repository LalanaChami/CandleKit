import CandleKit
import Foundation

/// A made-up book and tape around a price of 100, so the Order flow tab works offline.
enum SimulatedOrderFlow {
    static let midPrice = 100.0
    static let tick = 0.05
    private static let levels = 40

    static func events(seed: UInt64) -> AsyncStream<OrderFlowEvent> {
        AsyncStream { continuation in
            let task = Task {
                var book = MarketSampleData.orderBook(midPrice: midPrice, levels: levels, tick: tick, seed: seed)
                continuation.yield(.snapshot(bids: book.bids, asks: book.asks))
                var counter = 0

                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    if Task.isCancelled { break }

                    var updates: [OrderBookUpdate] = []
                    for _ in 0..<4 {
                        let index = Int.random(in: 0..<levels)
                        let isBid = Bool.random()
                        // The same arithmetic `MarketSampleData.orderBook` uses, so the price
                        // matches an existing level exactly.
                        let offset = tick * (Double(index) + 0.5)
                        let price = isBid ? midPrice - offset : midPrice + offset
                        // Now and then a level away from the top empties out.
                        let removes = index > 0 && Int.random(in: 0..<12) == 0
                        let size = removes ? 0 : (Double.random(in: 0.2...3.0) * 100).rounded() / 100
                        updates.append(OrderBookUpdate(side: isBid ? .bid : .ask, price: price, size: size))
                    }
                    book.apply(updates)
                    continuation.yield(.updates(updates))

                    if let bid = book.bestBid, let ask = book.bestAsk {
                        let buyerLifts = Bool.random()
                        counter += 1
                        // One print in ten is large, to show the tape's highlight.
                        let large = Int.random(in: 0..<10) == 0
                        let size = (Double.random(in: large ? 2.5...6.0 : 0.05...1.5) * 100).rounded() / 100
                        continuation.yield(.trade(MarketTrade(
                            id: "sim-\(counter)",
                            time: Date(),
                            price: buyerLifts ? ask.price : bid.price,
                            size: size,
                            side: buyerLifts ? .buy : .sell
                        )))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
