import Foundation

/// Groups trades by the candle they happened in.
public enum TradeAggregation {
    /// One `TradeFlow` per candle (same count and order as `candles`). A trade belongs to the last
    /// candle that opened at or before it; trades before the first candle, or more than `interval`
    /// after the last candle opened, are left out.
    ///
    /// Costs O(trades × log candles).
    public static func flows(trades: [MarketTrade], candles: [Candle], interval: TimeInterval) -> [TradeFlow] {
        var flows = [TradeFlow](repeating: TradeFlow(), count: candles.count)
        for trade in trades {
            guard let index = EventMarkerLayout.candleIndex(for: trade.time, in: candles, interval: interval) else {
                continue
            }
            flows[index].add(trade)
        }
        return flows
    }

    /// Running sum of `delta`, one value per flow (cumulative volume delta).
    public static func cumulativeDelta(_ flows: [TradeFlow]) -> [Double] {
        var total = 0.0
        return flows.map { flow in
            total += flow.delta
            return total
        }
    }
}
