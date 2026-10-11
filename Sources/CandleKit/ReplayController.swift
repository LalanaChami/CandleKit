#if os(iOS)
import SwiftUI

/// Plays a loaded series back candle by candle, for backtesting and for teaching technical
/// analysis. See ``CandlestickChart/replay(_:)``.
///
/// ```swift
/// @State private var replay = ReplayController()
///
/// CandlestickChart(candles)
///     .replay(replay)
///
/// Button("Replay") { replay.begin(at: 60); replay.play() }
/// ```
///
/// While a replay is active the chart shows only the first ``position`` candles, as if the rest of
/// the series hadn't happened yet. ``end()`` returns to the whole series.
@MainActor
@Observable
public final class ReplayController {
    /// The fewest candles a replay ever shows, so the chart always has something to draw.
    public static let minimumVisible = 2

    /// `true` between ``begin(at:)`` and ``end()``. When `false` the chart shows everything.
    public private(set) var isActive = false
    /// `true` while candles are being revealed on a timer.
    public private(set) var isPlaying = false
    /// How many candles are revealed. The chart limits it to what the series actually has.
    public private(set) var position = 0
    /// Speed while playing. Can be changed mid-replay; non-positive values pause progress.
    public var candlesPerSecond: Double = 2

    /// The series length the chart last reported, so stepping can stop at the end.
    @ObservationIgnored private(set) var totalCount = 0
    @ObservationIgnored private var clock = ReplayClock()
    @ObservationIgnored private var loop: Task<Void, Never>?

    public init() {}

    /// Starts (or restarts) a replay with the first `position` candles showing. Does not start playing.
    ///
    /// Going back to an earlier position redraws the chart as a new series, so it plays its
    /// appear animation again — fine for a restart, which is what this is for.
    public func begin(at position: Int = 50) {
        stopLoop()
        isActive = true
        self.position = max(position, Self.minimumVisible)
    }

    /// Reveals candles at ``candlesPerSecond`` until the end of the series or ``pause()``.
    /// Does nothing when no replay is active or the last candle is already showing.
    public func play() {
        guard isActive, !isAtEnd, !isPlaying else { return }
        isPlaying = true
        clock.reset()
        let task = Task { @MainActor [weak self] in
            let timer = ContinuousClock()
            var last = timer.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self, !Task.isCancelled else { return }
                let now = timer.now
                let elapsed = last.duration(to: now)
                last = now
                self.tick(seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18)
            }
        }
        loop = task
    }

    /// Stops revealing candles and keeps the current position.
    public func pause() {
        stopLoop()
    }

    /// Reveals `count` more candles (one by default) and pauses. Use ``begin(at:)`` to go back.
    public func step(_ count: Int = 1) {
        guard isActive, count > 0 else { return }
        stopLoop()
        advance(by: count)
    }

    /// Leaves replay: the chart shows the whole series again.
    public func end() {
        stopLoop()
        isActive = false
    }

    /// `true` once every candle of the series is showing.
    public var isAtEnd: Bool {
        totalCount > 0 && position >= totalCount
    }

    // MARK: Chart interface

    /// Called by the chart on every update so replay knows where the series ends. Only writes an
    /// unobserved property, so it is safe to call while a view body is being evaluated.
    func attach(totalCount: Int) {
        self.totalCount = totalCount
    }

    /// How many of the chart's `count` candles to show right now.
    func visibleCount(of count: Int) -> Int {
        ReplayMath.visibleCount(position: position, count: count, minimum: Self.minimumVisible)
    }

    // MARK: Private

    private func tick(seconds: Double) {
        let whole = clock.advance(by: seconds, candlesPerSecond: candlesPerSecond)
        if whole > 0 { advance(by: whole) }
    }

    private func advance(by count: Int) {
        let limit = totalCount > 0 ? totalCount : Int.max
        position = min(position + count, limit)
        if isAtEnd { stopLoop() }
    }

    private func stopLoop() {
        loop?.cancel()
        loop = nil
        isPlaying = false
    }
}
#endif
