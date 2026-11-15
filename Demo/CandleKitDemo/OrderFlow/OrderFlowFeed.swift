import CandleKit
import Foundation
import Observation

/// What an order-flow source sends: a full book, changes to it, or a trade.
enum OrderFlowEvent: Sendable {
    case snapshot(bids: [OrderBookLevel], asks: [OrderBookLevel])
    case updates([OrderBookUpdate])
    case trade(MarketTrade)
}

/// Feeds the Order flow tab. Ordinary app code: it turns a stream of events into the two values
/// CandleKit's views take, an `OrderBook` (through `OrderBookStore`) and a list of trades.
@MainActor
@Observable
final class OrderFlowFeed {
    enum Status: String {
        case simulated = "Simulated"
        case connecting = "Connecting…"
        case live = "Live"
        case disconnected = "Disconnected"
    }

    /// Deep enough that grouping a live book by whole dollars still leaves several rows.
    let store = OrderBookStore(depth: 1_500)
    private(set) var tape = TradeTape(capacity: 200)
    private(set) var status = Status.simulated

    // Trades can arrive in bursts. They collect here and reach the observed `tape` at most five
    // times a second, so a burst is one redraw.
    @ObservationIgnored private var buffer = TradeTape(capacity: 200)
    @ObservationIgnored private var throttle = PublishThrottle(interval: 0.2)
    @ObservationIgnored private var pendingFlush: Task<Void, Never>?

    /// Runs until the calling task is cancelled or a live connection drops.
    func run(live: Bool, productID: String) async {
        pendingFlush?.cancel()
        pendingFlush = nil
        store.clear()
        buffer.removeAll()
        tape = buffer
        status = live ? .connecting : .simulated

        let events = live
            ? CoinbaseOrderFlow.events(productID: productID)
            : SimulatedOrderFlow.events(seed: 42)

        for await event in events {
            if Task.isCancelled { break }
            switch event {
            case .snapshot(let bids, let asks):
                store.reset(bids: bids, asks: asks)
                if live { status = .live }
            case .updates(let updates):
                store.apply(updates)
            case .trade(let trade):
                record(trade)
            }
        }
        if live, !Task.isCancelled {
            status = .disconnected
        }
    }

    private func record(_ trade: MarketTrade) {
        buffer.append(trade)
        let wait = throttle.delay(at: ProcessInfo.processInfo.systemUptime)
        if wait <= 0 {
            flush()
        } else if pendingFlush == nil {
            pendingFlush = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                self?.flush()
            }
        }
    }

    private func flush() {
        pendingFlush?.cancel()
        pendingFlush = nil
        tape = buffer
        throttle.markPublished(at: ProcessInfo.processInfo.systemUptime)
    }
}
