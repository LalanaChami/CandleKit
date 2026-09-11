import CandleKit
import Foundation
import Observation

struct FeedConfiguration: Hashable, Sendable {
    var source: DataSourceKind
    var product: Product
    var timeframe: Timeframe
    /// Bumped to retry after a failure.
    var attempt = 0
}

/// Loads candles, keeps the newest one updated from live trades, and pages in history on request.
///
/// The chart only ever sees a plain `[Candle]`. Everything here is ordinary app code, which is the point:
/// CandleKit works out appends, in-place updates and prepends by itself.
@MainActor
@Observable
final class MarketFeed {
    enum Status: Equatable {
        case loading
        case streaming
        case reconnecting
        case failed(String)
    }

    private(set) var candles: [Candle] = []
    private(set) var status: Status = .loading
    private(set) var isLoadingHistory = false

    @ObservationIgnored private var configuration: FeedConfiguration?
    @ObservationIgnored private var historyTask: Task<Void, Never>?
    @ObservationIgnored private var reachedOldestAvailable = false
    /// Guards against a cancelled run writing into a newer one while its awaits unwind.
    @ObservationIgnored private var generation = 0

    /// Runs until the calling task is cancelled. Use with `.task(id:)`.
    func run(_ configuration: FeedConfiguration) async {
        generation += 1
        let runGeneration = generation
        historyTask?.cancel()
        historyTask = nil
        self.configuration = configuration
        candles = []
        status = .loading
        isLoadingHistory = false
        reachedOldestAvailable = false

        let source = configuration.source.dataSource
        let request = HistoryRequest(product: configuration.product, timeframe: configuration.timeframe, end: nil, anchorPrice: nil)
        do {
            let initial = try await source.history(for: request)
            guard isCurrent(runGeneration) else { return }
            candles = initial
        } catch {
            guard isCurrent(runGeneration) else { return }
            status = .failed(error.localizedDescription)
            return
        }

        var failures = 0
        while isCurrent(runGeneration) {
            status = .streaming
            do {
                let startPrice = candles.last?.close ?? configuration.product.simulatedPrice
                for try await trade in source.liveTrades(for: configuration.product, startingAt: startPrice) {
                    guard isCurrent(runGeneration) else { break }
                    apply(trade, interval: configuration.timeframe.seconds)
                    failures = 0
                }
            } catch {
                failures += 1
            }
            guard isCurrent(runGeneration) else { break }

            // The feed dropped. Back off, then reconnect. Candles missed while offline are not backfilled.
            status = .reconnecting
            let delay = min(30, pow(2, Double(failures)))
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    /// Fetches older candles once; further calls are ignored until the request finishes.
    func loadOlder() {
        guard let configuration, historyTask == nil, !reachedOldestAvailable, let oldest = candles.first else { return }
        let runGeneration = generation
        isLoadingHistory = true

        historyTask = Task { [weak self] in
            let request = HistoryRequest(
                product: configuration.product,
                timeframe: configuration.timeframe,
                end: oldest.time,
                anchorPrice: oldest.open
            )
            let result: Result<[Candle], Error>
            do {
                result = .success(try await configuration.source.dataSource.history(for: request))
            } catch {
                result = .failure(error)
            }

            guard let self, self.isCurrent(runGeneration) else { return }
            self.isLoadingHistory = false
            self.historyTask = nil

            switch result {
            case let .success(fetched):
                let currentOldest = self.candles.first?.time ?? oldest.time
                let older = fetched.filter { $0.time < currentOldest }
                if older.isEmpty {
                    self.reachedOldestAvailable = true
                } else {
                    self.candles.insert(contentsOf: older, at: 0)
                }
            case .failure:
                // Leave `reachedOldestAvailable` false so scrolling back again retries.
                break
            }
        }
    }

    private func isCurrent(_ runGeneration: Int) -> Bool {
        runGeneration == generation && !Task.isCancelled
    }

    /// Folds a trade into the candle for its time bucket.
    private func apply(_ trade: Trade, interval: TimeInterval) {
        let bucket = Date(timeIntervalSince1970: (trade.time.timeIntervalSince1970 / interval).rounded(.down) * interval)
        guard let last = candles.last else {
            candles.append(Candle(time: bucket, open: trade.price, high: trade.price, low: trade.price, close: trade.price, volume: trade.size))
            return
        }

        if bucket == last.time {
            var updated = last
            updated.close = trade.price
            updated.high = max(updated.high, trade.price)
            updated.low = min(updated.low, trade.price)
            updated.volume += trade.size
            candles[candles.count - 1] = updated
        } else if bucket > last.time {
            candles.append(Candle(
                time: bucket,
                open: last.close,
                high: max(last.close, trade.price),
                low: min(last.close, trade.price),
                close: trade.price,
                volume: trade.size
            ))
        }
        // Trades older than the newest candle are stale snapshots and are ignored.
    }
}
