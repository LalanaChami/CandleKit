#if os(iOS)
import Observation
import QuartzCore
import SwiftUI
import UIKit

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
    // Cached so makeFrame never calls estimatedInterval during a pan frame (it only changes with data).
    // Not `private`: `ChartHeader` reads it too, so it doesn't redundantly recompute the same value
    // on every render (it used to — see CHANGELOG).
    @ObservationIgnored private(set) var cachedInterval: TimeInterval = 60
    // Frozen while the user is scrolling so horizontal panning doesn't shift all candle Y-positions.
    @ObservationIgnored private var cachedPriceRange: ClosedRange<Double>? = nil
    /// True while the user is panning or momentum/spring-back is running. `makeFrame` skips
    /// recomputing the price scale in this state to keep candle heights visually stable.
    @ObservationIgnored var isScrolling = false

    // MARK: Rubber-band and spring-animation state (not observed)

    /// True while the viewport is intentionally held outside the clamped data range (rubber-band
    /// drag or spring-back). `makeFrame` skips its clamp step while this is set so the overscroll
    /// is rendered rather than immediately corrected.
    @ObservationIgnored var isRubberBanding = false

    // MARK: Appear animation (not observed)

    /// Progress of the candle appear animation when new data first loads. 0 = all candles hidden,
    /// 1 = all visible. Driven by `appearDisplayLink`; read in the Canvas to stagger per-candle opacity.
    @ObservationIgnored var appearPhase: Double = 1.0
    @ObservationIgnored private var appearDisplayLink: CADisplayLink?
    /// Cached from the first full `makeFrame` call when an animation starts. While `appearPhase < 1`
    /// and data is unchanged, `makeFrame` returns this immediately so the 120 Hz display link does
    /// not repeatedly run O(visible) price/tick/volume work on every animation frame.
    @ObservationIgnored private var cachedAnimationFrame: ChartFrame?
    @ObservationIgnored private var cachedAnimationSize: CGSize = .zero

    /// The most recently rendered frame. Read by `CrosshairLayer` and the accessibility modifier so
    /// they don't each have to depend on `revision` (and therefore re-render on every scroll frame)
    /// just to know where things are. Not observed: whoever reads it is already being re-rendered
    /// for its own reasons.
    @ObservationIgnored private(set) var currentFrame: ChartFrame?

    // Axis label strings are cached against the ticks that produced them. Number and date
    // formatting is expensive enough to matter when it runs for every label on every frame, and
    // while panning the tick values usually don't change at all from one frame to the next.
    @ObservationIgnored private var cachedPriceTicks: PriceTicks?
    @ObservationIgnored private var cachedPriceTickLabels: [String] = []
    @ObservationIgnored private var cachedTimeTicks: [TimeTick] = []
    @ObservationIgnored private var cachedTimeTickLabels: [String] = []
    @ObservationIgnored private var cachedLastPrice: Double?
    @ObservationIgnored private var cachedLastPriceDigits: Int = -1
    @ObservationIgnored private var cachedLastPriceLabel: String?

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

    /// Like ``resetZoom()``, but eases to the destination with a spring instead of snapping — the
    /// same animation double-tap-to-reset uses. Prefer this over `resetZoom()` for anything a
    /// person taps deliberately (a toolbar button, a menu item); reserve the instant version for
    /// places an animation would be wrong, like restoring state on launch.
    ///
    /// Respects Reduce Motion: jumps straight to the destination when it's on, exactly like
    /// `resetZoom()`.
    public func animatedResetZoom() {
        let target = Viewport.latest(count: candles.count, spacing: defaultSpacing, rightPadding: rightPadding)
        startSpringAnimation(to: target)
    }

    /// Like ``scrollToLatest()``, but eases to the destination with a spring instead of snapping.
    /// Keeps the current zoom level, unlike ``animatedResetZoom()``, which also resets it. Prefer
    /// this over `scrollToLatest()` for a "jump to latest" control a person taps.
    ///
    /// Respects Reduce Motion: jumps straight to the destination when it's on, exactly like
    /// `scrollToLatest()`.
    public func animatedScrollToLatest() {
        let target = Viewport.latest(count: candles.count, spacing: viewport.spacing, rightPadding: rightPadding)
        startSpringAnimation(to: target)
    }

    /// Stops any in-progress spring or appear animation. Snaps the appear animation to
    /// fully visible so a gesture that interrupts mid-animation never leaves candles half-drawn.
    func cancelAnimation() {
        stopSpringAnimation()
        if appearPhase < 1.0 {
            appearPhase = 1.0
            cachedAnimationFrame = nil
        }
        stopAppearAnimation()
    }

    /// Immediately stops any running appear or spring-to-target animation, without changing the
    /// current viewport or `appearPhase`. `CandlestickChart` calls this automatically when the chart
    /// leaves the view hierarchy, so a still-running animation doesn't keep this object — and
    /// everything it holds — alive in the background. Call it yourself if you manage a
    /// `CandleChartState` outside a `CandlestickChart`'s own lifecycle, for example one chart state
    /// per row in a list of charts that scroll on and off screen.
    public func stopAnimations() {
        stopAppearAnimation()
        stopSpringAnimation()
    }

    private func startSpringAnimation(to target: Viewport) {
        stopSpringAnimation()

        // Reduce Motion: this is an autonomous transition (not tied to a finger on screen), so it's
        // squarely what the setting asks apps to cut. Jump straight to the destination instead.
        if UIAccessibility.isReduceMotionEnabled {
            viewport = clampedToData(target)
            revision &+= 1
            requestOlderCandlesIfNeeded()
            return
        }

        springTargetViewport = target
        springRightEdgeVelocity = 0
        springSpacingVelocity = 0
        springLastTimestamp = CACurrentMediaTime()
        springDisplayLink = DisplayLinkProxy.scheduled(target: self) { state, link in
            state.stepSpringAnimation(link)
        }
    }

    private func stepSpringAnimation(_ link: CADisplayLink) {
        guard let target = springTargetViewport else { stopSpringAnimation(); return }
        // targetTimestamp is when this frame will appear on screen — computing physics to that moment
        // removes the systematic one-frame lag that timestamp-based calculations have.
        let now = link.targetTimestamp
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

    // MARK: Appear animation

    private func startAppearAnimation() {
        stopAppearAnimation()
        appearDisplayLink = DisplayLinkProxy.scheduled(target: self) { state, link in
            state.stepAppearAnimation(link)
        }
    }

    private func stepAppearAnimation(_ link: CADisplayLink) {
        let elapsed = link.targetTimestamp - link.timestamp
        appearPhase = min(1.0, appearPhase + elapsed / 0.5)
        revision &+= 1
        if appearPhase >= 1.0 {
            stopAppearAnimation()
        }
    }

    private func stopAppearAnimation() {
        appearDisplayLink?.invalidate()
        appearDisplayLink = nil
        cachedAnimationFrame = nil
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
        ChartPerformance.measure(.makeFrame) {
            buildFrame(
                candles: newCandles,
                indicators: indicators,
                size: size,
                metrics: metrics,
                showsVolume: showsVolume,
                fractionDigits: fractionDigits
            )
        }
    }

    private func buildFrame(
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
        // Trigger the candle appear animation on initial load or a full series replacement.
        // `startAppearAnimation` only mutates @ObservationIgnored properties (the CADisplayLink),
        // so it is safe to call directly here without deferring via Task.
        // Reduce Motion: this sweep is decorative, not information-bearing, so skip it and show
        // the candles immediately rather than just playing it faster.
        if (change == .initial || change == .replaced) && !newCandles.isEmpty {
            cachedAnimationFrame = nil   // stale cache from a previous run must not be reused
            if UIAccessibility.isReduceMotionEnabled {
                appearPhase = 1.0
            } else {
                appearPhase = 0.0
                startAppearAnimation()
            }
        }

        // While the appear animation is running and data hasn't changed, skip the O(visible)
        // price/tick/volume work — the Canvas reads state.appearPhase directly, so skipping
        // makeFrame's heavy computation does not affect what the animation draws.
        if appearPhase < 1.0, change == .unchanged,
           let cached = cachedAnimationFrame, cachedAnimationSize == size {
            currentFrame = cached
            return cached
        }

        if change != .unchanged {
            cachedInterval = TimeScale.estimatedInterval(of: newCandles)
        }
        // Skip the clamp while the user is in rubber-band overscroll or a spring-back is running,
        // so the intentional out-of-bounds position is rendered rather than immediately corrected.
        if !isRubberBanding {
            viewport = clampedToData(viewport)
        }

        let series = indicatorCache.series(for: indicators.map(\.kind), candles: newCandles)
        let visible = viewport.visibleRange(width: plotWidth, count: newCandles.count)
        // While scrolling, reuse the cached price range so horizontal panning doesn't shift candle heights.
        // Update on data change, zoom (change == .unchanged but !isScrolling covers non-pan interactions),
        // or when no cache exists yet. A ±15-candle window means occasional boundary candles don't jitter
        // the scale even when the cache refreshes.
        if !isScrolling || cachedPriceRange == nil || change != .unchanged {
            ChartPerformance.measure(.priceRange) {
                let priceWindow = max(0, visible.lowerBound - 15)..<min(newCandles.count, visible.upperBound + 15)
                cachedPriceRange = PriceScale.autoRange(for: newCandles, in: priceWindow, including: series) ?? 0...1
            }
        }
        let priceRange = cachedPriceRange!
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

        let timeTicks = ChartPerformance.measure(.timeTicks) {
            TimeScale.ticks(
                for: newCandles,
                in: visible,
                spacing: viewport.spacing,
                minimumLabelSpacing: metrics.timeLabelSpacing,
                interval: cachedInterval
            )
        }

        // --- Axis label strings -------------------------------------------------------------
        // Formatted here, on the main actor, once per change — not inside the Canvas closure on
        // every frame. While panning, the tick values are usually identical frame to frame, so
        // these cache hits skip the formatting entirely.
        let labels = ChartPerformance.measure(.labels) {
            buildLabels(
                priceTicks: priceTicks,
                timeTicks: timeTicks,
                candles: newCandles,
                fractionDigits: fractionDigits
            )
        }

        let frame = ChartFrame(
            candles: newCandles,
            layout: layout,
            viewport: viewport,
            visible: visible,
            priceScale: priceScale,
            priceTicks: priceTicks,
            priceFractionDigits: labels.digits,
            timeTicks: timeTicks,
            baseTimeUnit: labels.baseUnit,
            interval: cachedInterval,
            volumeMax: volumeMax,
            indicators: indicators,
            indicatorSeries: series,
            priceTickLabels: labels.priceLabels,
            timeTickLabels: labels.timeLabels,
            lastPriceLabel: labels.lastPrice
        )

        // Store this frame so subsequent animation ticks can return immediately without recomputing.
        if appearPhase < 1.0 {
            cachedAnimationFrame = frame
            cachedAnimationSize  = size
        }

        currentFrame = frame
        return frame
    }

    /// Formats the axis label strings, reusing cached ones whenever the ticks that produced them
    /// are unchanged. Split out of `buildFrame` so it can be timed as its own phase.
    private func buildLabels(
        priceTicks: PriceTicks,
        timeTicks: [TimeTick],
        candles newCandles: [Candle],
        fractionDigits: Int?
    ) -> (priceLabels: [String], baseUnit: TimeLabelUnit, timeLabels: [String], digits: Int, lastPrice: String?) {
        let priceTickLabels: [String]
        if let cachedPriceTicks, cachedPriceTicks == priceTicks {
            priceTickLabels = cachedPriceTickLabels
        } else {
            let digits = priceTicks.fractionDigits
            priceTickLabels = priceTicks.values.map { ChartFormat.price($0, digits: digits) }
            cachedPriceTicks = priceTicks
            cachedPriceTickLabels = priceTickLabels
        }

        let baseUnit = TimeScale.baseUnit(forInterval: cachedInterval)
        let timeTickLabels: [String]
        if cachedTimeTicks == timeTicks {
            timeTickLabels = cachedTimeTickLabels
        } else {
            timeTickLabels = timeTicks.map { ChartFormat.axisTime($0.date, unit: $0.unit) }
            cachedTimeTicks = timeTicks
            cachedTimeTickLabels = timeTickLabels
        }

        let resolvedDigits = fractionDigits ?? PriceScale.suggestedFractionDigits(forPrice: newCandles.last?.close ?? 0)
        let lastClose = newCandles.last?.close
        let lastPriceLabel: String?
        if lastClose == cachedLastPrice, resolvedDigits == cachedLastPriceDigits {
            lastPriceLabel = cachedLastPriceLabel
        } else {
            lastPriceLabel = lastClose.map { ChartFormat.price($0, digits: resolvedDigits) }
            cachedLastPrice = lastClose
            cachedLastPriceDigits = resolvedDigits
            cachedLastPriceLabel = lastPriceLabel
        }

        return (priceTickLabels, baseUnit, timeTickLabels, resolvedDigits, lastPriceLabel)
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
