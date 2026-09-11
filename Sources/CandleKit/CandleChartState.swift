#if os(iOS)
import Observation
import QuartzCore
import SwiftUI

/// Scroll position, zoom level and crosshair for a ``CandlestickChart``.
///
/// You only need to create one when you want to drive the chart from outside, for example
/// with a "Jump to latest" button. Otherwise the chart manages its own state.
///
/// ```swift
/// @State private var chartState = CandleChartState()
///
/// CandlestickChart(candles, state: chartState)
/// Button("Latest") { chartState.scrollToLatest() }
/// ```
@MainActor
@Observable
public final class CandleChartState {
    // MARK: Observed

    /// Bumped whenever the viewport moves. The chart body reads this to re-render.
    private(set) var revision = 0

    /// Index of the candle under the crosshair while the user is long-pressing, otherwise `nil`.
    public private(set) var crosshairIndex: Int? = nil

    private(set) var crosshairY: CGFloat? = nil

    // MARK: Not observed
    //
    // These are updated while SwiftUI evaluates the chart body (for example, shifting the viewport when
    // history is prepended). Mutating observed properties there would trigger "modifying state during
    // view update" and an extra render, so they are excluded from observation. Changes made outside
    // rendering, such as gestures, bump `revision` explicitly.

    @ObservationIgnored var viewport: Viewport
    @ObservationIgnored private var summary: SeriesSummary?
    @ObservationIgnored private var indicatorCache = IndicatorCache()
    @ObservationIgnored private var candles: [Candle] = []
    @ObservationIgnored private var plotWidth: Double = 0
    @ObservationIgnored private var oldestRequestCount: Int?
    @ObservationIgnored private var crosshairHandler: ((Candle?) -> Void)?
    @ObservationIgnored private var oldestCandleHandler: (() -> Void)?

    // MARK: Rubber-band and spring-animation state (not observed)

    /// True while the viewport is intentionally held outside the clamped data range (rubber-band
    /// drag or spring-back). `makeFrame` skips its clamp step while this is set so the overscroll
    /// is rendered rather than immediately corrected.
    @ObservationIgnored var isRubberBanding = false

    @ObservationIgnored private var springDisplayLink: CADisplayLink?
    @ObservationIgnored private var springTargetViewport: Viewport?
    @ObservationIgnored private var springRightEdgeVelocity: Double = 0
    @ObservationIgnored private var springSpacingVelocity: Double = 0
    @ObservationIgnored private var springLastTimestamp: CFTimeInterval = 0

    let zoomLimits: ZoomLimits
    let defaultSpacing: Double
    let rightPadding: Double

    /// - Parameters:
    ///   - candleSpacing: Initial width of one candle slot, in points.
    ///   - zoomLimits: How far the user can pinch in and out.
    ///   - rightPadding: Empty candle slots shown after the newest candle.
    public init(candleSpacing: Double = 8, zoomLimits: ZoomLimits = ZoomLimits(), rightPadding: Double = 3) {
        let spacing = zoomLimits.clamp(candleSpacing)
        self.viewport = Viewport(rightEdge: 0, spacing: spacing)
        self.zoomLimits = zoomLimits
        self.defaultSpacing = spacing
        self.rightPadding = max(0, rightPadding)
    }

    // MARK: Public controls

    /// `true` when the newest candle is on screen. New candles then scroll into view automatically.
    public var isFollowingLatest: Bool {
        _ = revision
        return viewport.isShowingLatest(count: candles.count)
    }

    public func scrollToLatest() {
        viewport = .latest(count: candles.count, spacing: viewport.spacing, rightPadding: rightPadding)
        commitViewport()
    }

    /// Restores the initial zoom level and scrolls to the newest candle.
    public func resetZoom() {
        viewport = .latest(count: candles.count, spacing: defaultSpacing, rightPadding: rightPadding)
        commitViewport()
    }

    /// Scrolls by whole candles. Positive values move toward newer data.
    public func scroll(byCandles count: Int) {
        pan(byPoints: -Double(count) * viewport.spacing)
    }

    // MARK: Gesture entry points

    /// Returns `true` if the pan was stopped by the edge of the data, so momentum can end.
    @discardableResult
    func pan(byPoints dx: Double) -> Bool {
        var moved = viewport
        moved.pan(byPoints: dx)
        let clamped = clampedToData(moved)
        let hitEdge = abs(clamped.rightEdge - moved.rightEdge) > 1e-9
        viewport = clamped
        revision &+= 1
        requestOlderCandlesIfNeeded()
        return hitEdge
    }

    /// Pans with rubber-band resistance at the data edges.
    ///
    /// Resistance grows as the overscroll distance increases, matching UIScrollView's feel.
    /// Returns `true` while the viewport is in (or just entered) overscroll territory. Call
    /// `startSpringBack()` on the coordinator when the drag ends in overscroll.
    @discardableResult
    func panForDrag(byPoints dx: Double, plotWidth: Double) -> Bool {
        // Compute resistance from the current overscroll before this delta is applied.
        let currentClamped = clampedToData(viewport)
        let currentOverscrollPts = (viewport.rightEdge - currentClamped.rightEdge) * viewport.spacing
        let factor: Double
        if abs(currentOverscrollPts) > 0 {
            factor = max(0.05, 1.0 - min(abs(currentOverscrollPts) / plotWidth, 0.8) * 0.55)
        } else {
            factor = 1.0
        }

        var moved = viewport
        moved.pan(byPoints: dx * factor)
        let clamped = clampedToData(moved)
        let hitEdge = abs(clamped.rightEdge - moved.rightEdge) > 1e-9

        if hitEdge || isRubberBanding {
            isRubberBanding = true
            viewport = moved

            // If the user has panned back within bounds, snap and exit.
            let newOverscrollPts = (viewport.rightEdge - clampedToData(viewport).rightEdge) * viewport.spacing
            if abs(newOverscrollPts) < 0.5 {
                viewport = clampedToData(viewport)
                isRubberBanding = false
                requestOlderCandlesIfNeeded()
            }
        } else {
            viewport = clamped
            requestOlderCandlesIfNeeded()
        }

        revision &+= 1
        return isRubberBanding
    }

    func zoom(by scale: Double, anchorX: Double) {
        viewport.zoom(by: scale, anchorX: anchorX, width: plotWidth, limits: zoomLimits)
        commitViewport()
    }

    func updateCrosshair(x: CGFloat, y: CGFloat) {
        guard let index = viewport.candleIndex(atX: Double(x), width: plotWidth, count: candles.count) else { return }
        crosshairY = y
        if crosshairIndex != index {
            crosshairIndex = index
            crosshairHandler?(candles[index])
        }
    }

    func clearCrosshair() {
        guard crosshairIndex != nil || crosshairY != nil else { return }
        crosshairIndex = nil
        crosshairY = nil
        crosshairHandler?(nil)
    }

    // MARK: Rubber-band support (used by ChartGestureCoordinator)

    /// How far past the clamped data edge the viewport currently sits, in points.
    /// Positive means past the right (newest) edge; negative means past the left (oldest) edge.
    func overscrollPoints() -> Double {
        let clamped = clampedToData(viewport)
        return (viewport.rightEdge - clamped.rightEdge) * viewport.spacing
    }

    /// The right-edge value the viewport would have after clamping.
    func clampedRightEdge() -> Double {
        clampedToData(viewport).rightEdge
    }

    /// Moves the right edge directly without clamping, for use during spring-back animation.
    /// Callers must ensure `isRubberBanding` is true so `makeFrame` doesn't re-clamp immediately.
    func setRightEdgeDirect(_ edge: Double) {
        viewport.rightEdge = edge
        revision &+= 1
    }

    /// Snaps the viewport to its clamped position and exits rubber-band mode.
    func snapToClamped() {
        viewport = clampedToData(viewport)
        isRubberBanding = false
        revision &+= 1
        requestOlderCandlesIfNeeded()
    }

    // MARK: Spring animations (animated reset / scroll-to-latest)

    /// Animates to the reset-zoom viewport (default spacing, latest candle visible).
    func animatedResetZoom() {
        let target = Viewport.latest(count: candles.count, spacing: defaultSpacing, rightPadding: rightPadding)
        startSpringAnimation(to: target)
    }

    /// Animates to show the latest candle while keeping the current zoom level.
    func animatedScrollToLatest() {
        let target = Viewport.latest(count: candles.count, spacing: viewport.spacing, rightPadding: rightPadding)
        startSpringAnimation(to: target)
    }

    /// Stops any in-progress spring animation without snapping to the target.
    func cancelAnimation() {
        stopSpringAnimation()
    }

    private func startSpringAnimation(to target: Viewport) {
        stopSpringAnimation()
        springTargetViewport = target
        springRightEdgeVelocity = 0
        springSpacingVelocity = 0
        springLastTimestamp = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(stepSpringAnimation(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        springDisplayLink = link
    }

    @objc private func stepSpringAnimation(_ link: CADisplayLink) {
        guard let target = springTargetViewport else { stopSpringAnimation(); return }
        let now = link.timestamp
        let elapsed = min(max(now - springLastTimestamp, 0), 1.0 / 30)
        springLastTimestamp = now

        // Critically-damped spring: stiffness=180, damping=2√180≈26.8 → use 27.
        let stiffness = 180.0
        let damping = 27.0

        let edgeDelta = viewport.rightEdge - target.rightEdge
        springRightEdgeVelocity += (-stiffness * edgeDelta - damping * springRightEdgeVelocity) * elapsed
        viewport.rightEdge += springRightEdgeVelocity * elapsed

        let spacingDelta = viewport.spacing - target.spacing
        springSpacingVelocity += (-stiffness * spacingDelta - damping * springSpacingVelocity) * elapsed
        viewport.spacing += springSpacingVelocity * elapsed

        revision &+= 1

        // Settle: both dimensions within half a point and moving slowly.
        let edgeSettled = abs(edgeDelta * viewport.spacing) < 0.5 && abs(springRightEdgeVelocity * viewport.spacing) < 5
        let spacingSettled = abs(spacingDelta) < 0.05 && abs(springSpacingVelocity) < 0.1
        if edgeSettled && spacingSettled {
            viewport = clampedToData(target)
            revision &+= 1
            stopSpringAnimation()
        }
    }

    private func stopSpringAnimation() {
        springDisplayLink?.invalidate()
        springDisplayLink = nil
        springTargetViewport = nil
    }

    // MARK: Rendering

    func setHandlers(crosshair: ((Candle?) -> Void)?, oldestCandle: (() -> Void)?) {
        crosshairHandler = crosshair
        oldestCandleHandler = oldestCandle
    }

    /// Reconciles the viewport with the latest data and size, then computes everything the renderers draw.
    func makeFrame(
        candles newCandles: [Candle],
        indicators: [ChartIndicator],
        size: CGSize,
        metrics: ChartMetrics,
        showsVolume: Bool,
        fractionDigits: Int?
    ) -> ChartFrame {
        let layout = ChartLayout(size: size, metrics: metrics, showsVolume: showsVolume)
        plotWidth = Double(layout.plot.width)

        let change = SeriesChange.between(summary, newCandles)
        viewport.apply(change, previousCount: summary?.count ?? 0, newCount: newCandles.count, rightPadding: rightPadding)
        summary = SeriesSummary(newCandles)
        candles = newCandles
        // Skip the clamp while the user is in rubber-band overscroll or a spring-back is running,
        // so the intentional out-of-bounds position is rendered rather than immediately corrected.
        if !isRubberBanding {
            viewport = clampedToData(viewport)
        }

        let series = indicatorCache.series(for: indicators.map(\.kind), candles: newCandles)
        let visible = viewport.visibleRange(width: plotWidth, count: newCandles.count)
        let priceRange = PriceScale.autoRange(for: newCandles, in: visible, including: series) ?? 0...1
        let priceScale = LinearScale(
            domain: priceRange,
            rangeStart: Double(layout.priceBand.upperBound),
            rangeEnd: Double(layout.priceBand.lowerBound)
        )
        let bandHeight = Double(layout.priceBand.upperBound - layout.priceBand.lowerBound)
        let priceTicks = PriceScale.niceTicks(
            in: priceRange,
            approximateCount: max(2, Int(bandHeight / metrics.priceTickSpacing))
        )

        var volumeMax = 0.0
        for index in visible {
            volumeMax = max(volumeMax, newCandles[index].volume)
        }

        let interval = TimeScale.estimatedInterval(of: newCandles)
        let timeTicks = TimeScale.ticks(
            for: newCandles,
            in: visible,
            spacing: viewport.spacing,
            minimumLabelSpacing: metrics.timeLabelSpacing
        )

        return ChartFrame(
            candles: newCandles,
            layout: layout,
            viewport: viewport,
            visible: visible,
            priceScale: priceScale,
            priceTicks: priceTicks,
            priceFractionDigits: fractionDigits ?? PriceScale.suggestedFractionDigits(forPrice: newCandles.last?.close ?? 0),
            timeTicks: timeTicks,
            baseTimeUnit: TimeScale.baseUnit(forInterval: interval),
            interval: interval,
            volumeMax: volumeMax,
            indicators: indicators,
            indicatorSeries: series
        )
    }

    // MARK: Private

    private func commitViewport() {
        viewport = clampedToData(viewport)
        revision &+= 1
        requestOlderCandlesIfNeeded()
    }

    private func clampedToData(_ proposed: Viewport) -> Viewport {
        proposed.clamped(count: candles.count, width: plotWidth, limits: zoomLimits)
    }

    /// Calls the history handler once per data size when the user nears the oldest candle.
    private func requestOlderCandlesIfNeeded() {
        guard let oldestCandleHandler, !candles.isEmpty, plotWidth > 0, oldestRequestCount != candles.count else { return }
        let threshold = max(10, viewport.visibleCandleCount(width: plotWidth) * 0.25)
        guard viewport.leftEdge(width: plotWidth) < threshold else { return }
        oldestRequestCount = candles.count
        oldestCandleHandler()
    }
}
#endif
