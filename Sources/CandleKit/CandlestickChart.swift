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
    private var drawingsBinding: Binding<[Drawing]>?
    private var drawingToolBinding: Binding<DrawingTool?>?
    private var selectedDrawingBinding: Binding<UUID?>?
    /// What a newly created drawing looks like — see `defaultDrawingStyle(_:)`.
    private var drawingDefaultStyle = DrawingStyle()
    @State private var drawingController = DrawingController()

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
        // Only mutates @ObservationIgnored properties (see `DrawingController.attach`), so — like
        // `setHandlers` above — this is safe to call directly from inside body every pass.
        let _ = drawingController.attach(
            drawings: drawingsBinding,
            tool: drawingToolBinding,
            selection: selectedDrawingBinding,
            frame: { state.currentFrame },
            defaultStyle: { drawingDefaultStyle }
        )
        let drawingsValue = drawingsBinding?.wrappedValue ?? []

        VStack(alignment: .leading, spacing: 8) {
            if showsHeader && !candles.isEmpty {
                ChartHeader(state: state, candles: candles, fractionDigits: headerDigits, style: style)
            }

            GeometryReader { proxy in
                let metrics = ChartMetrics(
                    priceAxisWidth: priceAxisWidth,
                    timeAxisHeight: timeAxisHeight,
                    // The requested overlap while browsing history — see `buildFrame`, which forces
                    // this back to 0 whenever the viewport is showing the latest candle, so "now" is
                    // never obscured by the axis. Deliberately larger than `priceAxisWidth` itself
                    // (~64pt at base Dynamic Type size): a smaller value left candles stopping
                    // partway through the axis while scrolled back, leaving a visible gap of nothing
                    // between where they ended and the actual screen edge. 70 closes that gap by
                    // extending candles all the way to (and slightly past, harmlessly clipped by the
                    // canvas's own bounds) the true edge, for the state where overlap is active at all.
                    priceAxisOverlap: style.priceAxisMaterial != nil ? 70 : 0
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
                    if drawingsBinding != nil {
                        DrawingsLayer(state: state, controller: drawingController, drawings: drawingsValue)
                    }
                    ChartGestureView(
                        state: state,
                        drawingController: drawingsBinding != nil ? drawingController : nil
                    )
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
        // Also reads `crosshairIndex` (not `crosshairY`, which changes on every pixel of finger
        // movement within the same candle and doesn't affect which candle should look dulled).
        // `crosshairIndex` only changes when the crosshair engages, disengages, or crosses to a
        // different candle — far less often than a scroll's `revision` bumps — so this doesn't add
        // a new source of high-frequency redraws, just a narrow one this view already updates for.
        let focusedCandleIndex = state.crosshairIndex
        let frame = state.makeFrame(
            candles: candles,
            indicators: indicators,
            style: style,
            size: size,
            metrics: metrics,
            showsVolume: showsVolume,
            fractionDigits: fractionDigits
        )
        ChartBaseLayer(frame: frame, style: style, appearPhase: state.appearPhase, focusedCandleIndex: focusedCandleIndex)
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
                    // Plain rectangle, not a rounded/stroked shape: real device screenshots showed
                    // `glassEffect` producing visible colour-tinted glow artefacts along the top and
                    // bottom of this tall, edge-spanning strip, and a stroked rounded-corner outline
                    // added its own hard edge that fought the feathering below. Both are dropped —
                    // this is exactly the situation where a sophisticated new API misbehaves in a
                    // way that can't be safely diagnosed or tuned without a device in hand, so this
                    // falls back to the simpler, well-understood primitive rather than continuing to
                    // guess at `glassEffect` parameters. Revisit true Liquid Glass once there's a way
                    // to iterate on it directly against a device.
                    Rectangle()
                        .fill(material)
                        // `Material` alone carries its own neutral grey-ish tint regardless of
                        // what's behind it, which is what made the panel read as a distinctly
                        // coloured box rather than a frosted version of its surroundings. Blending
                        // toward the system background pulls its hue back toward whatever's already
                        // around it — `.systemBackground` resolves to the correct value in both
                        // light and dark automatically, no explicit colour-scheme branch needed —
                        // and the reduced opacity on the whole layer afterward makes the panel
                        // noticeably more translucent than `Material` alone allows (there's no
                        // "thinner than ultraThin" material to reach for instead).
                        .overlay(Color(uiColor: .systemBackground).opacity(0.4))
                        .opacity(0.7)
                        .frame(width: axis.width, height: axis.height)
                        // Feathers three edges — leading, top, bottom — so the panel dissolves into
                        // the chart instead of presenting a hard-edged box. The trailing edge stays
                        // fully opaque; it's flush with the screen edge, with nothing to blend into.
                        // Two masks stack multiplicatively (each restricts the alpha the previous
                        // one already restricted), which is how one shape ends up faded on more than
                        // one side without hand-building a 2D gradient. Fractions widened slightly
                        // from the previous round for an even softer, smoother dissolve.
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.2),
                                    .init(color: .black, location: 1),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.12),
                                    .init(color: .black, location: 0.88),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .position(x: axis.midX, y: axis.midY)
                }

                ForEach(frame.priceTicks.values.indices, id: \.self) { index in
                    let y = frame.y(forPrice: frame.priceTicks.values[index])
                    if y > axis.minY + 6, y < axis.maxY - 6 {
                        Text(frame.priceTickLabels[index])
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(style.axisLabelColor)
                            .frame(width: axis.width, alignment: .center)
                            .position(x: axis.midX, y: y)
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

    /// Trend lines, rectangles, Fibonacci retracements and other annotations the person draws on
    /// the chart. App-owned, the same shape `.indicators([...])` already uses, and for the same
    /// reason — see `docs/design/drawing-tools.md` for the full design. Omit this modifier and
    /// drawing tools cost nothing: no extra Canvas layer, no gesture-mode branching in the pan/pinch/
    /// long-press recognizers.
    ///
    /// ```swift
    /// CandlestickChart(candles)
    ///     .drawings($drawings)
    ///     .drawingTool($activeTool)
    /// ```
    public func drawings(_ drawings: Binding<[Drawing]>) -> CandlestickChart {
        var copy = self
        copy.drawingsBinding = drawings
        return copy
    }

    /// The color, line width, dash and fill opacity a newly created drawing starts with. Defaults to
    /// `DrawingStyle()`'s neutral blue. Per-drawing color is the point of `Drawing.style` (design
    /// note — two trend lines on the same chart can already carry different colors); this only sets
    /// what the *next* one starts as. To recolor a drawing that already exists — including the
    /// currently selected one — mutate its `style` directly in your own `.drawings(...)` array, the
    /// same "app owns the array" pattern `.selectedDrawing(...)` already documents for deletion.
    public func defaultDrawingStyle(_ style: DrawingStyle) -> CandlestickChart {
        var copy = self
        copy.drawingDefaultStyle = style
        return copy
    }

    /// Which drawing tool is active, or `nil` for the chart's ordinary pan/zoom/crosshair behavior
    /// (the default). While a tool is set, a one-finger drag creates a drawing of that kind instead
    /// of panning the chart, and pinch/long-press are suppressed; releasing commits the drawing and
    /// the tool stays selected for the next one. Requires `.drawings(...)` to also be attached —
    /// there is nothing to place a created drawing into otherwise. See the design note's §2 for the
    /// full interaction model this implements.
    public func drawingTool(_ tool: Binding<DrawingTool?>) -> CandlestickChart {
        var copy = self
        copy.drawingToolBinding = tool
        return copy
    }

    /// Mirrors which drawing's id is currently selected (by tapping it, in cursor mode), or `nil`
    /// when nothing is. One-way, chart → app: use it to show your own inspector or "Delete" button —
    /// deletion itself is just `drawings.removeAll { $0.id == id }` on your own `.drawings(...)`
    /// binding, per the design note's §4/§5. Optional; omit it if you don't need to react to selection.
    public func selectedDrawing(_ selection: Binding<UUID?>) -> CandlestickChart {
        var copy = self
        copy.selectedDrawingBinding = selection
        return copy
    }
}
#endif
