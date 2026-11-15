import Foundation
import Testing
@testable import CandleKitCore

private func trade(_ id: String, _ t: Double, _ price: Double, _ size: Double, _ side: MarketTrade.Side) -> MarketTrade {
    MarketTrade(id: id, time: Date(timeIntervalSince1970: t), price: price, size: size, side: side)
}

private var sampleTrades: [MarketTrade] {
    [
        trade("1", 0, 100.0, 0.5, .buy), trade("2", 10, 100.5, 1.5, .sell), trade("3", 59, 101.0, 2.0, .buy),
        trade("4", 60, 100.0, 1.0, .unknown), trade("5", 125, 99.0, 4.0, .sell), trade("6", 130, 99.5, 0.25, .buy),
        trade("7", 200, 98.0, 1.0, .sell),
    ]
}

private func close(_ a: Double?, _ b: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) < 1e-9
}

@Suite("Market trades")
struct MarketTradeTests {
    @Test func flowTotals() {
        let flow = TradeMath.flow(of: sampleTrades)
        #expect(close(flow.buyVolume, 2.75))
        #expect(close(flow.sellVolume, 6.5))
        #expect(close(flow.unknownVolume, 1.0))
        #expect(flow.tradeCount == 7)
        #expect(close(flow.notional, 1021.625))
        #expect(close(flow.totalVolume, 10.25))
        #expect(close(flow.delta, -3.75))
        #expect(close(flow.vwap, 99.67073170731707))
        #expect(close(flow.buyShare, 0.2972972972972973))
    }

    @Test func flowEmpty() {
        let flow = TradeMath.flow(of: [])
        #expect(flow == TradeFlow())
        #expect(flow.totalVolume == 0)
        #expect(flow.delta == 0)
        #expect(flow.vwap == nil)
        #expect(flow.buyShare == nil)
    }

    @Test func flowSkipsBadTrades() {
        var flow = TradeFlow()
        flow.add(trade("a", 0, 100, 0, .buy))
        flow.add(trade("b", 0, 100, -1, .sell))
        flow.add(trade("c", 0, .nan, 1, .buy))
        flow.add(trade("d", 0, 100, .infinity, .buy))
        #expect(flow == TradeFlow())
    }

    @Test func tapeKeepsNewest() {
        var tape = TradeTape(capacity: 3)
        for trade in sampleTrades {
            tape.append(trade)
        }
        #expect(tape.trades.map(\.id) == ["5", "6", "7"])
    }

    @Test func tapeIgnoresRepeatOfNewest() {
        var tape = TradeTape(capacity: 10)
        tape.append(sampleTrades[0])
        tape.append(sampleTrades[0])
        #expect(tape.trades.count == 1)
        tape.append(sampleTrades[1])
        tape.append(sampleTrades[0])
        #expect(tape.trades.count == 3)
    }

    @Test func tapeCapacityFloor() {
        #expect(TradeTape(capacity: 0).capacity == 1)
        #expect(TradeTape(capacity: -8).capacity == 1)
    }

    @Test func tapeAppendContentsOf() {
        var tape = TradeTape(capacity: 5)
        tape.append(contentsOf: sampleTrades)
        #expect(tape.trades.map(\.id) == ["3", "4", "5", "6", "7"])
        tape.removeAll()
        #expect(tape.trades.isEmpty)
    }

    @Test func tickRule() {
        let prices = [100, 100.5, 100.5, 100.2, 100.2, 100.2, 100.3]
        var previousPrice: Double?
        var side = MarketTrade.Side.unknown
        var sides: [MarketTrade.Side] = []
        for price in prices {
            side = TradeMath.tickRuleSide(price: price, previousPrice: previousPrice, previousSide: side)
            sides.append(side)
            previousPrice = price
        }
        #expect(sides == [.unknown, .buy, .buy, .sell, .sell, .sell, .buy])
    }
}
