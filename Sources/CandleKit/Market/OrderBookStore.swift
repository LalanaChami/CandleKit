#if os(iOS)
import Observation
import SwiftUI

/// Holds a live order book and republishes it to SwiftUI at a steady, readable rate.
///
/// A level 2 feed can change twenty times a second. Redrawing that often costs battery and is too
/// fast to read, so the store keeps the full book current and publishes a trimmed copy a few times
/// a second.
///
/// ```swift
/// @State private var store = OrderBookStore()
/// store.reset(bids: snapshot.bids, asks: snapshot.asks)   // on connect
/// store.apply(updates)                                    // on every feed message
/// OrderBookView(store.book)
/// ```
@MainActor
@Observable
public final class OrderBookStore {
    /// The book as last published: at most `depth` levels per side, refreshed at most once per
    /// `publishInterval`. Views read this.
    public private(set) var book = OrderBook()

    @ObservationIgnored private var full = OrderBook()
    @ObservationIgnored private var throttle: PublishThrottle
    @ObservationIgnored private var pending: Task<Void, Never>?
    private let depth: Int

    /// - Parameters:
    ///   - publishInterval: minimum seconds between two published books. 0.2 (five a second) by default.
    ///   - depth: levels kept per side in the published book. The full book is still tracked.
    public init(publishInterval: TimeInterval = 0.2, depth: Int = 200) {
        throttle = PublishThrottle(interval: publishInterval)
        self.depth = max(1, depth)
    }

    /// Replaces the book with a fresh snapshot and publishes it straight away.
    public func reset(bids: [OrderBookLevel], asks: [OrderBookLevel]) {
        full.reset(bids: bids, asks: asks)
        publishNow()
    }

    /// Applies feed updates. Publishing is delayed if the last publish was too recent.
    public func apply(_ updates: [OrderBookUpdate]) {
        full.apply(updates)
        let wait = throttle.delay(at: Self.now)
        if wait <= 0 {
            publishNow()
        } else if pending == nil {
            pending = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                self?.publishNow()
            }
        }
    }

    /// Empties the book, for example when the symbol changes.
    public func clear() {
        full = OrderBook()
        publishNow()
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func publishNow() {
        pending?.cancel()
        pending = nil
        book = full.trimmed(depth: depth)
        throttle.markPublished(at: Self.now)
    }
}
#endif
