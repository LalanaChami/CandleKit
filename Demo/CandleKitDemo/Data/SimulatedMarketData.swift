import CandleKit
import Foundation

/// Fake market data that works offline, with timing close enough to a real feed to exercise every chart path.
struct SimulatedMarketData: MarketDataSource {
    private static let batchSize = 300

    func history(for request: HistoryRequest) async throws -> [Candle] {
        // A short delay keeps loading states visible, as they would be over a network.
        try await Task.sleep(for: .milliseconds(request.end == nil ? 300 : 600))

        let interval = request.timeframe.seconds
        let newest: Date
        if let end = request.end {
            newest = end.addingTimeInterval(-interval)
        } else {
            newest = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 / interval).rounded(.down) * interval)
        }
        let start = newest.addingTimeInterval(-interval * Double(Self.batchSize - 1))

        let walk = CandleSampleData.randomWalk(
            count: Self.batchSize,
            start: start,
            interval: interval,
            startPrice: request.product.simulatedPrice,
            volatility: min(0.03, 0.0015 * (interval / 60).squareRoot()),
            seed: UInt64(max(0, start.timeIntervalSince1970)) &+ UInt64(request.timeframe.rawValue)
        )

        // Scale older batches so they end where the loaded candles begin.
        guard let anchor = request.anchorPrice, let lastClose = walk.last?.close, lastClose > 0 else { return walk }
        let factor = anchor / lastClose
        return walk.map { candle in
            Candle(
                time: candle.time,
                open: candle.open * factor,
                high: candle.high * factor,
                low: candle.low * factor,
                close: candle.close * factor,
                volume: candle.volume
            )
        }
    }

    func liveTrades(for product: Product, startingAt price: Double) -> AsyncThrowingStream<Trade, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var lastPrice = price
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(Int.random(in: 120...600)))
                    guard !Task.isCancelled else { break }
                    lastPrice = max(0.01, lastPrice * (1 + Double.random(in: -0.0006...0.0006)))
                    continuation.yield(Trade(price: lastPrice, size: Double.random(in: 0.001...0.5), time: .now))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
