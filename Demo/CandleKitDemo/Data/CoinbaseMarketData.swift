import CandleKit
import Foundation

/// Public market data from Coinbase Exchange. No account or API key is needed.
///
/// Candles: `GET /products/{id}/candles`, at most 300 per request, rows of `[time, low, high, open, close, volume]`.
/// Trades: the `ticker` channel of the public WebSocket feed.
struct CoinbaseMarketData: MarketDataSource {
    private static let restBase = URL(string: "https://api.exchange.coinbase.com")!
    private static let feedURL = URL(string: "wss://ws-feed.exchange.coinbase.com")!
    /// Requests spanning more than 300 buckets are rejected, and both ends of the range are inclusive,
    /// so stay a little under the limit.
    private static let bucketsPerRequest = 290

    func history(for request: HistoryRequest) async throws -> [Candle] {
        let interval = request.timeframe.seconds
        let end = request.end ?? .now
        let start = end.addingTimeInterval(-interval * Double(Self.bucketsPerRequest - 1))

        var components = URLComponents(
            url: Self.restBase.appending(path: "products/\(request.product.id)/candles"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "granularity", value: String(request.timeframe.rawValue)),
            URLQueryItem(name: "start", value: start.formatted(.iso8601)),
            URLQueryItem(name: "end", value: end.formatted(.iso8601)),
        ]
        guard let url = components.url else { throw MarketDataError.invalidResponse }
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw MarketDataError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.message
            throw MarketDataError.server(status: http.statusCode, message: message)
        }

        let rows = try JSONDecoder().decode([[Double]].self, from: data)
        var candles = rows.compactMap { row -> Candle? in
            guard row.count >= 6 else { return nil }
            return Candle(
                time: Date(timeIntervalSince1970: row[0]),
                open: row[3],
                high: row[2],
                low: row[1],
                close: row[4],
                volume: row[5]
            )
        }
        // The end bound is inclusive, so the candle we already have can come back again.
        if let requestedEnd = request.end {
            candles.removeAll { $0.time >= requestedEnd }
        }
        // Coinbase returns newest first; the chart needs oldest first with unique times.
        candles.sort { $0.time < $1.time }
        var unique: [Candle] = []
        unique.reserveCapacity(candles.count)
        for candle in candles where unique.last?.time != candle.time {
            unique.append(candle)
        }
        return unique
    }

    func liveTrades(for product: Product, startingAt price: Double) -> AsyncThrowingStream<Trade, Error> {
        let socket = URLSession.shared.webSocketTask(with: Self.feedURL)
        return AsyncThrowingStream { continuation in
            let task = Task {
                socket.resume()
                do {
                    let subscribe = SubscribeMessage(productIDs: [product.id], channels: ["ticker"])
                    let text = String(decoding: try JSONEncoder().encode(subscribe), as: UTF8.self)
                    try await socket.send(.string(text))
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        if let trade = Self.trade(from: message) {
                            continuation.yield(trade)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                // `receive()` doesn't observe task cancellation, so close the socket to unblock it.
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    // MARK: Messages

    private struct ErrorBody: Decodable {
        let message: String
    }

    private struct SubscribeMessage: Encodable {
        let type = "subscribe"
        let productIDs: [String]
        let channels: [String]

        enum CodingKeys: String, CodingKey {
            case type
            case productIDs = "product_ids"
            case channels
        }
    }

    private struct TickerMessage: Decodable {
        let type: String
        let price: String?
        let lastSize: String?
        let time: String?

        enum CodingKeys: String, CodingKey {
            case type
            case price
            case lastSize = "last_size"
            case time
        }
    }

    private static func trade(from message: URLSessionWebSocketTask.Message) -> Trade? {
        let data: Data
        switch message {
        case let .string(text):
            data = Data(text.utf8)
        case let .data(bytes):
            data = bytes
        @unknown default:
            return nil
        }
        guard
            let ticker = try? JSONDecoder().decode(TickerMessage.self, from: data),
            ticker.type == "ticker",
            let price = ticker.price.flatMap({ Double($0) }),
            let time = ticker.time.flatMap({ parseTime($0) })
        else { return nil }
        return Trade(price: price, size: ticker.lastSize.flatMap { Double($0) } ?? 0, time: time)
    }

    /// Coinbase sends microseconds ("2026-09-11T14:02:07.061769Z"). Whole seconds are enough to bucket trades.
    private static func parseTime(_ string: String) -> Date? {
        var trimmed = string
        if let dot = string.firstIndex(of: ".") {
            trimmed = String(string[..<dot]) + "Z"
        }
        return try? Date(trimmed, strategy: .iso8601)
    }
}
