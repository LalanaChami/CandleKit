import CandleKit
import Foundation

/// Coinbase Exchange's public WebSocket feed: the `level2_batch` channel for the book and
/// `matches` for trades. No API key. (Plain `level2` needs authentication; the batch channel sends
/// the same data every 50 ms.)
enum CoinbaseOrderFlow {
    private static let feedURL = URL(string: "wss://ws-feed.exchange.coinbase.com")!

    /// Ends when the connection drops or the consumer stops listening. No automatic reconnect.
    static func events(productID: String) -> AsyncStream<OrderFlowEvent> {
        let socket = URLSession.shared.webSocketTask(with: feedURL)
        // The opening snapshot of a busy book is several megabytes; the default limit is 1 MB.
        socket.maximumMessageSize = 32 * 1024 * 1024
        return AsyncStream { continuation in
            let task = Task {
                socket.resume()
                do {
                    let subscribe: [String: Any] = [
                        "type": "subscribe",
                        "product_ids": [productID],
                        "channels": ["level2_batch", "matches"],
                    ]
                    let text = String(decoding: try JSONSerialization.data(withJSONObject: subscribe), as: UTF8.self)
                    try await socket.send(.string(text))

                    let timestamps = ISO8601DateFormatter()
                    timestamps.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        if let event = Self.event(from: message, timestamps: timestamps) {
                            continuation.yield(event)
                        }
                    }
                } catch {
                    // A dropped connection ends the stream; the feed shows "Disconnected".
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                // `receive()` doesn't observe task cancellation, so close the socket to unblock it.
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    // MARK: Parsing

    /// Every number on this feed arrives as text. Anything that doesn't parse is skipped.
    private static func event(
        from message: URLSessionWebSocketTask.Message, timestamps: ISO8601DateFormatter
    ) -> OrderFlowEvent? {
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let raw): data = raw
        @unknown default: return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return nil }

        switch type {
        case "snapshot":
            return .snapshot(bids: Self.levels(json["bids"]), asks: Self.levels(json["asks"]))

        case "l2update":
            guard let changes = json["changes"] as? [[String]] else { return nil }
            let updates = changes.compactMap { change -> OrderBookUpdate? in
                guard change.count >= 3, let price = Double(change[1]), let size = Double(change[2]) else {
                    return nil
                }
                // Here "buy" and "sell" name the side of the book. A size of "0" removes the level,
                // which `OrderBook` does by itself.
                return OrderBookUpdate(side: change[0] == "buy" ? .bid : .ask, price: price, size: size)
            }
            return updates.isEmpty ? nil : .updates(updates)

        case "match", "last_match":
            guard let priceText = json["price"] as? String, let price = Double(priceText),
                  let sizeText = json["size"] as? String, let size = Double(sizeText),
                  let makerSide = json["side"] as? String
            else { return nil }
            let id = (json["trade_id"] as? NSNumber)?.stringValue ?? UUID().uuidString
            let time = (json["time"] as? String).flatMap { timestamps.date(from: $0) } ?? Date()
            // Coinbase reports the MAKER's side. CandleKit's `side` is the aggressor, the opposite:
            // a resting sell order that got filled means a buyer lifted it.
            let aggressor: MarketTrade.Side = makerSide == "sell" ? .buy : .sell
            return .trade(MarketTrade(id: id, time: time, price: price, size: size, side: aggressor))

        default:
            return nil
        }
    }

    private static func levels(_ value: Any?) -> [OrderBookLevel] {
        guard let rows = value as? [[String]] else { return [] }
        return rows.compactMap { row in
            guard row.count >= 2, let price = Double(row[0]), let size = Double(row[1]) else { return nil }
            return OrderBookLevel(price: price, size: size)
        }
    }
}
