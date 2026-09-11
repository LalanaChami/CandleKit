import CandleKit
import Foundation

struct Product: Hashable, Identifiable, Sendable {
    /// Coinbase product ID, for example "BTC-USD".
    let id: String
    let name: String
    /// Where simulated prices start.
    let simulatedPrice: Double

    static let bitcoin = Product(id: "BTC-USD", name: "Bitcoin", simulatedPrice: 64_000)
    static let ether = Product(id: "ETH-USD", name: "Ether", simulatedPrice: 3_200)
    static let solana = Product(id: "SOL-USD", name: "Solana", simulatedPrice: 150)

    static let all: [Product] = [.bitcoin, .ether, .solana]
}

/// Raw values are seconds, matching the granularities the Coinbase candles endpoint accepts.
enum Timeframe: Int, CaseIterable, Identifiable, Sendable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case oneHour = 3_600
    case sixHours = 21_600
    case oneDay = 86_400

    var id: Int { rawValue }

    var seconds: TimeInterval { TimeInterval(rawValue) }

    var label: String {
        switch self {
        case .oneMinute: return "1m"
        case .fiveMinutes: return "5m"
        case .fifteenMinutes: return "15m"
        case .oneHour: return "1h"
        case .sixHours: return "6h"
        case .oneDay: return "1D"
        }
    }
}

struct Trade: Sendable {
    let price: Double
    let size: Double
    let time: Date
}

struct HistoryRequest: Sendable {
    let product: Product
    let timeframe: Timeframe
    /// Only candles older than this are wanted. `nil` means the most recent candles.
    let end: Date?
    /// Price the returned candles should lead into. Simulated data uses it to join up with loaded candles.
    let anchorPrice: Double?
}

protocol MarketDataSource: Sendable {
    /// A batch of candles, oldest first, with unique times.
    func history(for request: HistoryRequest) async throws -> [Candle]

    /// Trades as they happen. The stream ends when the connection drops.
    func liveTrades(for product: Product, startingAt price: Double) -> AsyncThrowingStream<Trade, Error>
}

enum DataSourceKind: String, CaseIterable, Identifiable, Sendable {
    case coinbase = "Live"
    case simulated = "Simulated"

    var id: String { rawValue }

    var dataSource: any MarketDataSource {
        switch self {
        case .coinbase: return CoinbaseMarketData()
        case .simulated: return SimulatedMarketData()
        }
    }
}

enum MarketDataError: LocalizedError {
    case invalidResponse
    case server(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server sent a response the app couldn't read."
        case let .server(status, message):
            if let message, !message.isEmpty {
                return "The server returned an error (\(status)): \(message)"
            }
            return "The server returned an error (\(status))."
        }
    }
}
