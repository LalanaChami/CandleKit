import CandleKit
import Foundation
import Observation

/// The symbols picked in Chart Options to compare against the main one (roadmap 7.6), and their
/// loaded candles.
///
/// Loaded once per symbol, timeframe and data source: the comparison lines do not tick with live
/// trades, so on a live crypto chart they fall behind after a few minutes (the chart shows a break
/// where a line has no recent data). Only symbols of the same kind are offered, because crypto trades
/// around the clock and equities do not.
@MainActor @Observable
final class ComparisonModel {
    var selected: Set<String> = []
    var normalization: ComparisonNormalization = .percentChange
    private(set) var series: [ComparisonSeries] = []
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Symbols that can be compared with `product`.
    static func candidates(for product: Product) -> [Product] {
        Product.all.filter { $0.id != product.id && $0.isEquity == product.isEquity }
    }

    func toggle(_ product: Product) {
        if selected.contains(product.id) {
            selected.remove(product.id)
        } else if selected.count < 3 {
            selected.insert(product.id)
        }
    }

    /// Reloads the lines for the current selection. Call whenever the main configuration or selection changes.
    func reload(for configuration: FeedConfiguration) {
        task?.cancel()
        let products = Self.candidates(for: configuration.product).filter { selected.contains($0.id) }
        guard !products.isEmpty else {
            series = []
            return
        }
        let source = configuration.effectiveSource.dataSource
        let timeframe = configuration.timeframe
        task = Task { [weak self] in
            var loaded: [ComparisonSeries] = []
            for product in products {
                if Task.isCancelled { return }
                let request = HistoryRequest(product: product, timeframe: timeframe, end: nil, anchorPrice: nil)
                if let candles = try? await source.history(for: request) {
                    loaded.append(ComparisonSeries(name: product.id, candles: candles))
                }
            }
            guard !Task.isCancelled else { return }
            self?.series = loaded
        }
    }
}
