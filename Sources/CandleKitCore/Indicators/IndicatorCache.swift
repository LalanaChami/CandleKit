import Foundation

/// Keeps computed indicator results between renders, so panning and zooming never recompute them.
///
/// Results are recomputed only when the candle array changes. Comparing an unchanged array is O(1)
/// because Swift's `Array` equality short-circuits when both sides share the same storage buffer —
/// which is the normal case frame to frame.
///
/// Not `Sendable`-shared: hold one per chart, mutate it from the main actor.
public struct IndicatorCache {
    private var source: [Candle] = []
    private var storage: [String: IndicatorResult] = [:]
    /// Number of full computations performed. Exposed so tests can prove caching actually works —
    /// an indicator engine that silently recomputes every frame looks identical from the outside.
    public private(set) var computations = 0

    public init() {}

    /// Results for `indicators`, computing only the ones not already cached for this candle array.
    ///
    /// Indicators are identified by their ``IndicatorDescriptor/id``, which folds in the parameter
    /// values — so an RSI(14) and an RSI(21) are separate cache entries, and changing a period
    /// recomputes only that indicator rather than invalidating everything.
    public mutating func results(for indicators: [any Indicator], candles: [Candle]) -> [IndicatorResult] {
        if candles != source {
            storage.removeAll(keepingCapacity: true)
            source = candles
        }

        let wantedKeys = Set(indicators.map { $0.descriptor.id })
        if storage.count > wantedKeys.count {
            storage = storage.filter { wantedKeys.contains($0.key) }
        }

        return indicators.map { indicator in
            let key = indicator.descriptor.id
            if let cached = storage[key] { return cached }
            let computed = indicator.compute(candles)
            storage[key] = computed
            computations += 1
            return computed
        }
    }

    /// Drops everything. Use when the indicator set changes wholesale and the old entries are
    /// certainly dead, rather than waiting for the next call to evict them.
    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        source = []
    }
}
