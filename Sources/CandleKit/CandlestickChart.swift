#if os(iOS)
import SwiftUI

/// An interactive candlestick chart.
///
/// ```swift
/// CandlestickChart(candles)
///     .indicators([.sma(20), .ema(50)])
///     .onReachOldestCandle { Task { await loadHistory() } }
/// ```
///
/// Drag to scroll (with momentum), pinch to zoom around your fingers, long-press to inspect a candle,
/// and double-tap to reset. Candles must be sorted by time, oldest first. Update the array freely:
/// appended candles scroll into view when the newest candle is on screen, and prepended history keeps
/// the visible candles in place.
public struct CandlestickChart: View {
    private let candles: [Candle]
    private let externalState: CandleChartState?
    @State private var internalState = CandleChartState()
    @ScaledMetric(relativeTo: .caption2) private var priceAxisWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .caption2) private var timeAxisHeight: CGFloat = 24
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var style = CandleChartStyle.standard
    private var indicators: [ChartIndicator] = []
    private var showsVolume = true
    private var showsHeader = true
    private var fractionDigits: Int?
    private var crosshairHandler: ((Candle?) -> Void)?
    private var oldestCandleHandler: (() -> Void)?

    /// - Parameters:
    ///   - candles: The series to draw, oldest first.
    ///   - state: Pass your own state to control scrolling from outside the chart.
    public init(_ candles: [Candle], state: CandleChartState? = nil) {
        self.candles = candles
        self.externalState = state
    }

    // Deliberately does NOT read `state.revision`.
    //
    // It used to, which meant a single `revision` bump — one per animation frame during a pan,
    // a fling or a pinch, up to 120 times a second — invalidated this entire body: the header
    // (which reformats a row of prices), the accessibility summary (which formats two dates and
    // two numbers), the gesture representable, and the ZStack layout. Almost none of that
    // actually changes when the viewport moves.
    //
    // `revision` is now read only by `ChartContentLayer`, the one view that genuinely has to
    // redraw per frame. Everything here re-evaluates only when its own inputs change.
    public var body: some View {
        let state = externalState ?? internalState
        let _ = state.setHandlers(crosshair: crosshairHandler, oldestCandle: oldestCandleHandler)
        let headerDigits = fractionDigits ?? PriceScale.suggestedFractionDigits(forPrice: candles.last?.close ?? 0)

        VStack(alignment: .leading, spacing: 8) {
            if showsHeader && !candles.isEmpty {
                ChartHeader(state: state, candles: candles, fractionDigits: headerDigits, style: style)
            }

            GeometryReader { proxy in
                let metrics = ChartMetrics(
                    priceAxisWidth: priceAxisWidth,
                    timeAxisHeight: timeAxisHeight,
                    // Only overlap when there's a material to keep the labels legible against
                    // candles moving underneath — see the doc comment on the property itself.
                    priceAxisOverlap: style.priceAxisMaterial != nil ? 28 : 0
                )
                // Covers every pane, so a drag starting on an indicator pane still pans the chart.
                // Depends only on the size and metrics — never on which indicators are present — so
                // the gesture view is positioned without waiting on a rendered ChartFrame.
                let content = ChartLayout.contentRect(size: proxy.size, metrics: metrics)

                ZStack(alignment: .topLeading) {
                    ChartContentLayer(
                        state: state,
                        candles: candles,
                        indicators: indicators,
                        size: proxy.size,
                        metrics: metrics,
                        showsVolume: showsVolume,
                        fractionDigits: fractionDigits,
                        style: style
                    )
                    PriceAxisGlassPanel(state: state, style: style)
                    CrosshairLayer(state: state, style: style)
                    LastPriceBadge(state: state, candles: candles, style: style)
                    ChartGestureView(state: state)
                        .frame(width: content.width, height: content.height)
                        .position(x: content.midX, y: content.midY)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Candlestick chart"))
                .modifier(ChartAccessibilityDetails(state: state, isActive: voiceOverEnabled))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        // Stops any in-flight appear or spring animation the moment this chart leaves the view
        // hierarchy — a `List` row scrolling away mid-animation, a sheet being dismissed, a
        // NavigationStack pop — so its CADisplayLink isn't left running in the background.
        .onDisappear { state.stopAnimations() }
    }
}

/// The only view that re-renders on every animation frame.
///
/// Isolating it means a `revision` bump repaints the candle Canvas and nothing else. Its own stored
/// inputs (the candle array, the indicator list, the size) don't change between frames of a scroll,
/// so SwiftUI won't re-run this body for any reason other than the `revision` read below.
private struct ChartContentLayer: View {
    let state: CandleChartState
    let candles: [Candle]
    let indicators: [ChartIndicator]
    let size: CGSize
    let metrics: ChartMetrics
    let showsVolume: Bool
    let fractionDigits: Int?
    let style: CandleChartStyle

    var body: some View {
        let _ = state.revision
        let frame = state.makeFrame(
            candles: candles,
            indicators: indicators,
            style: style,
            size: size,
            metrics: metrics,
            showsVolume: showsVolume,
            fractionDigits: fractionDigits
        )
        ChartBaseLayer(frame: frame, style: style, appearPhase: state.appearPhase)
    }
}

/// Attaches the expensive accessibility descriptions only when VoiceOver is actually running.
///
/// `ChartAccessibility.summary` formats two dates and two numbers. Date formatting is one of the
/// most expensive things Foundation does, and this string was previously rebuilt on every frame of
/// every scroll for the benefit of a screen reader that usually isn't running. When VoiceOver *is*
/// running there's no 120 Hz flinging to protect, so the cost stops mattering, and the frame lookup
/// below reads `revision` to keep the summary current as the chart moves.
private struct ChartAccessibilityDetails: ViewModifier {
    let state: CandleChartState
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive, let frame = currentFrame() {
            content
                .accessibilityValue(Text(ChartAccessibility.summary(
                    of: frame.candles[frame.visible],
                    digits: frame.priceFractionDigits,
                    interval: frame.interval
                )))
                .accessibilityChartDescriptor(ChartAccessibility(frame: frame))
                .accessibilityAdjustableAction { direction in
                    let page = max(1, frame.visible.count / 2)
                    switch direction {
                    case .increment:
                        state.scroll(byCandles: page)
                    case .decrement:
                        state.scroll(byCandles: -page)
                    @unknown default:
                        break
                    }
                }
        } else {
            content
        }
    }

    private func currentFrame() -> ChartFrame? {
        _ = state.revision
        return state.currentFrame
    }
}

/// The last-price tag on the price axis, as a real SwiftUI view instead of Canvas-drawn text.
///
/// `.contentTransition(.numericText())` — a smooth digit roll instead of a hard cut, the standard
/// "stock ticker" look — has no Canvas equivalent; `.contentTransition` is a view modifier. This is
/// the one piece of the chart's text that's worth paying for as a real view over it: it's the single
/// number a user actually watches tick while a market is open.
///
/// Reads `state.revision`, unlike most of this file, so its vertical position tracks the price scale
/// during a pan or pinch. That's a narrow, cheap subscription — repositioning one small view — not
/// the whole-subtree cost `ChartContentLayer` exists to avoid.
private struct LastPriceBadge: View {
    let state: CandleChartState
    let candles: [Candle]
    let style: CandleChartStyle

    /// Approximates `caption2` + the padding below closely enough for the vertical clamp; being a
    /// few points off only matters right at the top or bottom edge of the plot.
    private static let height: CGFloat = 20

    var body: some View {
        let _ = state.revision
        if let last = candles.last, let frame = state.currentFrame, let label = frame.lastPriceLabel {
            let axis = frame.layout.priceAxis
            let plot = frame.layout.plot
            let half = Self.height / 2
            let y = min(max(frame.y(forPrice: last.close), plot.minY + half), plot.maxY - half)

            HStack(spacing: 0) {
                Text(label)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        last.isBullish ? style.upColor : style.downColor,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    // Scoped to just this Text, so only the digits animate — the position above is
                    // computed outside this modifier chain and snaps to the new scale instantly,
                    // exactly as it did when this was drawn in the Canvas.
                    .contentTransition(.numericText(value: last.close))
                    .animation(.snappy(duration: 0.3), value: last.close)
                Spacer(minLength: 0)
            }
            .padding(.leading, 2)
            .frame(width: axis.width, height: Self.height, alignment: .leading)
            .position(x: axis.minX + axis.width / 2, y: y)
            .allowsHitTesting(false)
        }
    }
}

/// A frosted backdrop behind the price axis's tick labels, letting candles show through it
/// (softly blurred) as they scroll underneath — see `CandleChartStyle.priceAxisMaterial`.
///
/// Tick labels are real `Text` views here, not drawn in the Canvas: a `Material` only blurs
/// content *behind* the view it's attached to, so text drawn inside the same `Canvas` as the
/// candles would be blurred right along with them. Rendering them as their own layer, on top of
/// the material, is what keeps the numbers crisp while the candles behind them aren't — the same
/// reason `LastPriceBadge` had to become a real view rather than Canvas-drawn text.
///
/// Reads `state.revision`, like `LastPriceBadge` — a narrow, cheap subscription (repositioning a
/// handful of small `Text` views) so tick positions and values track the price scale during a pan
/// or pinch, not the whole-subtree cost `ChartContentLayer` exists to avoid.
private struct PriceAxisGlassPanel: View {
    let state: CandleChartState
    let style: CandleChartStyle

    var body: some View {
        let _ = state.revision
        if let frame = state.currentFrame {
            let axis = frame.layout.priceAxis
            ZStack(alignment: .topLeading) {
                // Only the background is conditional on the style. The labels themselves are
                // drawn either way — this view is what draws them now, full stop, whether or not
                // there's a material behind them.
                if let material = style.priceAxisMaterial {
                    Rectangle()
                        .fill(material)
                        .frame(width: axis.width, height: axis.height)
                        .position(x: axis.midX, y: axis.midY)
                }

                ForEach(frame.priceTicks.values.indices, id: \.self) { index in
                    let y = frame.y(forPrice: frame.priceTicks.values[index])
                    if y > axis.minY + 6, y < axis.maxY - 6 {
                        Text(frame.priceTickLabels[index])
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(style.axisLabelColor)
                            .frame(width: max(0, axis.width - 8), alignment: .leading)
                            .position(x: axis.minX + max(0, axis.width - 8) / 2 + 6, y: y)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Modifiers

extension CandlestickChart {
    /// Colors and candle appearance. See ``CandleChartStyle`` for presets.
    public func candleChartStyle(_ style: CandleChartStyle) -> CandlestickChart {
        var copy = self
        copy.style = style
        return copy
    }

    /// Line overlays such as moving averages. Values are cached and only recomputed when the data changes.
    public func indicators(_ indicators: [ChartIndicator]) -> CandlestickChart {
        var copy = self
        copy.indicators = indicators
        return copy
    }

    /// Shows volume bars beneath the candles. On by default.
    public func volumeVisible(_ visible: Bool = true) -> CandlestickChart {
        var copy = self
        copy.showsVolume = visible
        return copy
    }

    /// Shows the price readout above the chart. On by default.
    public func headerVisible(_ visible: Bool = true) -> CandlestickChart {
        var copy = self
        copy.showsHeader = visible
        return copy
    }

    /// Decimal places for prices. By default this is inferred from the latest close.
    public func priceFractionDigits(_ digits: Int?) -> CandlestickChart {
        var copy = self
        copy.fractionDigits = digits
        return copy
    }

    /// Called when the long-pressed candle changes, and with `nil` when the finger lifts.
    public func onCrosshairChange(_ action: @escaping (Candle?) -> Void) -> CandlestickChart {
        var copy = self
        copy.crosshairHandler = action
        return copy
    }

    /// Called when the user scrolls near the oldest loaded candle. Prepend older candles to your array in response.
    ///
    /// The handler runs once per data size, so it won't fire repeatedly while a request is in flight.
    public func onReachOldestCandle(_ action: @escaping () -> Void) -> CandlestickChart {
        var copy = self
        copy.oldestCandleHandler = action
        return copy
    }
}
#endif
