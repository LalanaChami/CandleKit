#if os(iOS)
import Foundation
import os

/// Opt-in performance instrumentation for the chart's per-frame work.
///
/// This exists because CandleKit's performance work kept being done blind: costs were ranked by
/// reading the code rather than by measuring, which fixed several real-but-minor things while the
/// dominant cost went untouched. Instruments alone gives you a call tree of Swift and SwiftUI
/// symbols that's hard to map back to chart phases, so the chart names its own phases here.
///
/// Two outputs, from the same measurements:
///
/// - **Signposts**, so Instruments shows named intervals (`makeFrame`, `draw.candles`, …) on the
///   Points of Interest track, lined up against the Animation Hitches track.
/// - **A markdown table** via ``report(scenario:)``, ready to paste into `docs/PERFORMANCE.md`.
///
/// Everything is off by default and costs a single `Bool` check per phase when off, so shipping
/// code pays effectively nothing. Turn it on by setting the `CANDLEKIT_PERF` environment variable
/// in the scheme, or by calling ``setEnabled(_:)``.
///
/// ```swift
/// ChartPerformance.setEnabled(true)
/// ChartPerformance.reset()
/// // …scroll, fling, pinch for ten seconds…
/// print(ChartPerformance.report(scenario: "Continuous pan, 5m, iPhone 15 Pro"))
/// ```
public enum ChartPerformance {
    /// A named slice of the per-frame work.
    public enum Phase: String, CaseIterable, Sendable {
        /// Everything `CandleChartState.makeFrame` does: reconciling data, scales, ticks, labels.
        case makeFrame = "makeFrame"
        /// Just the price autorange inside `makeFrame`.
        case priceRange = "makeFrame.priceRange"
        /// Time-tick placement inside `makeFrame`.
        case timeTicks = "makeFrame.timeTicks"
        /// Formatting axis label strings inside `makeFrame` (skipped on a cache hit).
        case labels = "makeFrame.labels"
        /// The whole base-layer Canvas closure.
        case drawTotal = "draw.total"
        case drawGrid = "draw.grid"
        case drawVolume = "draw.volume"
        /// Batched steady-state candles.
        case drawCandles = "draw.candles"
        /// Bucketed appear-animation candles.
        case drawAppear = "draw.appear"
        case drawIndicators = "draw.indicators"
        /// Axis labels and the last-price tag — the text-drawing path.
        case drawAxes = "draw.axes"
        /// The crosshair overlay Canvas.
        case drawCrosshair = "draw.crosshair"
    }

    // MARK: Enabling

    /// `true` when measurements are being taken. Defaults to whether `CANDLEKIT_PERF` is set in the
    /// environment, so you can profile a Release build without recompiling.
    public static var isEnabled: Bool {
        store.isEnabled
    }

    public static func setEnabled(_ enabled: Bool) {
        store.isEnabled = enabled
    }

    /// Discards all samples. Call this immediately before the interaction you want to measure, so
    /// the numbers aren't diluted by startup work.
    public static func reset() {
        store.reset()
    }

    // MARK: Measuring

    /// Times `body` and records it under `phase`. Returns whatever `body` returns.
    ///
    /// When instrumentation is off this is a `Bool` check and a direct call — no clock reads, no
    /// locking, no signposts.
    @inline(__always)
    static func measure<T>(_ phase: Phase, _ body: () throws -> T) rethrows -> T {
        guard store.isEnabled else { return try body() }
        let signposter = store.signposter
        let state = signposter.beginInterval(phase.signpostName)
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            store.record(phase, nanoseconds: DispatchTime.now().uptimeNanoseconds &- start)
            signposter.endInterval(phase.signpostName, state)
        }
        return try body()
    }

    // MARK: Reporting

    /// A markdown table of everything recorded since the last ``reset()``, ready to paste into
    /// `docs/PERFORMANCE.md`.
    ///
    /// - Parameter scenario: what you were doing, the device, and the candle count — for example
    ///   `"Continuous pan · 5m · 10K candles · iPhone 15 Pro"`. This ends up as the table heading,
    ///   so be specific: a row without its device and dataset can't be compared against anything.
    public static func report(scenario: String) -> String {
        store.report(scenario: scenario)
    }

    // MARK: Storage

    private static let store = Store()

    /// Sample storage. Deliberately a lock rather than an actor: `measure` is called from the
    /// `Canvas` draw closure, which is not main-actor-isolated and cannot await.
    private final class Store: @unchecked Sendable {
        /// Ring buffer length per phase. At ~120 frames a second this holds about 16 seconds of
        /// samples, which comfortably covers a single measured interaction.
        private static let capacity = 2_048

        let signposter = OSSignposter(subsystem: "com.candlekit.CandleKit", category: .pointsOfInterest)

        private let lock = OSAllocatedUnfairLock(initialState: Samples())
        private let enabledLock: OSAllocatedUnfairLock<Bool>

        init() {
            let fromEnvironment = ProcessInfo.processInfo.environment["CANDLEKIT_PERF"] != nil
            enabledLock = OSAllocatedUnfairLock(initialState: fromEnvironment)
        }

        var isEnabled: Bool {
            get { enabledLock.withLock { $0 } }
            set { enabledLock.withLock { $0 = newValue } }
        }

        private struct Samples {
            var buffers: [Phase: [Double]] = [:]
            var counts: [Phase: Int] = [:]
        }

        func reset() {
            lock.withLock { $0 = Samples() }
        }

        func record(_ phase: Phase, nanoseconds: UInt64) {
            let milliseconds = Double(nanoseconds) / 1_000_000
            lock.withLock { samples in
                var buffer = samples.buffers[phase] ?? []
                if buffer.count < Self.capacity {
                    buffer.append(milliseconds)
                } else {
                    // Wrap: overwrite oldest, so a long session reports its most recent window
                    // rather than silently ignoring everything after the buffer fills.
                    let index = (samples.counts[phase] ?? 0) % Self.capacity
                    buffer[index] = milliseconds
                }
                samples.buffers[phase] = buffer
                samples.counts[phase] = (samples.counts[phase] ?? 0) + 1
            }
        }

        func report(scenario: String) -> String {
            let samples = lock.withLock { $0 }
            var lines: [String] = []
            lines.append("### \(scenario)")
            lines.append("")
            lines.append("_Captured \(Date.now.formatted(date: .abbreviated, time: .shortened))_")
            lines.append("")

            let recorded = Phase.allCases.filter { (samples.buffers[$0]?.isEmpty == false) }
            guard !recorded.isEmpty else {
                lines.append("No samples recorded. Is `ChartPerformance.isEnabled` true?")
                return lines.joined(separator: "\n")
            }

            lines.append("| Phase | Calls | Mean ms | p50 ms | p95 ms | Max ms |")
            lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
            for phase in recorded {
                guard let buffer = samples.buffers[phase], !buffer.isEmpty else { continue }
                let sorted = buffer.sorted()
                let total = buffer.reduce(0, +)
                let mean = total / Double(buffer.count)
                let calls = samples.counts[phase] ?? buffer.count
                lines.append(
                    "| `\(phase.rawValue)` | \(calls) | \(Self.format(mean)) "
                    + "| \(Self.format(Self.percentile(sorted, 0.50))) "
                    + "| \(Self.format(Self.percentile(sorted, 0.95))) "
                    + "| \(Self.format(sorted[sorted.count - 1])) |"
                )
            }
            lines.append("")
            lines.append(
                "A 120 Hz frame budget is 8.3 ms and a 60 Hz budget is 16.7 ms — that's for "
                + "*everything*, including the SwiftUI and Core Animation work this table doesn't "
                + "measure, so treat anything over ~3 ms here as worth attention."
            )
            return lines.joined(separator: "\n")
        }

        private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            let index = Int((Double(sorted.count - 1) * fraction).rounded())
            return sorted[min(max(index, 0), sorted.count - 1)]
        }

        private static func format(_ milliseconds: Double) -> String {
            String(format: "%.3f", milliseconds)
        }
    }
}

private extension ChartPerformance.Phase {
    /// `OSSignposter` needs a `StaticString`, so the names are spelled out rather than derived
    /// from `rawValue`.
    var signpostName: StaticString {
        switch self {
        case .makeFrame: return "makeFrame"
        case .priceRange: return "makeFrame.priceRange"
        case .timeTicks: return "makeFrame.timeTicks"
        case .labels: return "makeFrame.labels"
        case .drawTotal: return "draw.total"
        case .drawGrid: return "draw.grid"
        case .drawVolume: return "draw.volume"
        case .drawCandles: return "draw.candles"
        case .drawAppear: return "draw.appear"
        case .drawIndicators: return "draw.indicators"
        case .drawAxes: return "draw.axes"
        case .drawCrosshair: return "draw.crosshair"
        }
    }
}
#endif
