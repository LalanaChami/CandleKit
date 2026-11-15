import Foundation
import Testing
@testable import CandleKitCore

private func trade(_ id: String, _ t: Double, _ price: Double, _ size: Double, _ side: MarketTrade.Side) -> MarketTrade {
    MarketTrade(id: id, time: Date(timeIntervalSince1970: t), price: price, size: size, side: side)
}

/// The trades from `MarketTradeTests`, plus one before the first candle.
private var sampleTrades: [MarketTrade] {
    [
        trade("1", 0, 100.0, 0.5, .buy), trade("2", 10, 100.5, 1.5, .sell), trade("3", 59, 101.0, 2.0, .buy),
        trade("4", 60, 100.0, 1.0, .unknown), trade("5", 125, 99.0, 4.0, .sell), trade("6", 130, 99.5, 0.25, .buy),
        trade("7", 200, 98.0, 1.0, .sell), trade("8", -5, 100.0, 9.0, .buy),
    ]
}

private func close(_ a: Double?, _ b: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) < 1e-9
}

@Suite("Trade aggregation")
struct TradeAggregationTests {
    // Candles opening at 0, 60 and 120 seconds.
    private let candles: [Candle] = (0..<3).map { i in
        Candle(time: Date(timeIntervalSince1970: Double(i) * 60), open: 100, high: 101, low: 99, close: 100)
    }

    @Test func flowsPerCandle() {
        let flows = TradeAggregation.flows(trades: sampleTrades, candles: candles, interval: 60)
        #expect(flows.count == 3)

        #expect(close(flows[0].buyVolume, 2.5))
        #expect(close(flows[0].sellVolume, 1.5))
        #expect(flows[0].unknownVolume == 0)
        #expect(flows[0].tradeCount == 3)
        #expect(close(flows[0].notional, 402.75))
        #expect(close(flows[0].delta, 1.0))
        #expect(close(flows[0].vwap, 100.6875))

        #expect(close(flows[1].unknownVolume, 1.0))
        #expect(flows[1].tradeCount == 1)
        #expect(close(flows[1].notional, 100.0))
        #expect(flows[1].delta == 0)
        #expect(flows[1].buyShare == nil)

        #expect(close(flows[2].buyVolume, 0.25))
        #expect(close(flows[2].sellVolume, 4.0))
        #expect(flows[2].tradeCount == 2)
        #expect(close(flows[2].notional, 420.875))
        #expect(close(flows[2].delta, -3.75))
        #expect(close(flows[2].vwap, 99.02941176470588))
    }

    @Test func tradesOutsideAreDropped() {
        let flows = TradeAggregation.flows(trades: sampleTrades, candles: candles, interval: 60)
        #expect(flows.reduce(0) { $0 + $1.tradeCount } == 6)
    }

    @Test func cumulativeDelta() {
        let flows = TradeAggregation.flows(trades: sampleTrades, candles: candles, interval: 60)
        let running = TradeAggregation.cumulativeDelta(flows)
        #expect(running.count == 3)
        #expect(close(running[0], 1.0))
        #expect(close(running[1], 1.0))
        #expect(close(running[2], -2.75))
    }

    @Test func noCandles() {
        #expect(TradeAggregation.flows(trades: sampleTrades, candles: [], interval: 60).isEmpty)
        #expect(TradeAggregation.cumulativeDelta([]).isEmpty)
    }
}
