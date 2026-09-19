#if os(iOS)
import SwiftUI

/// The crosshair lives in its own view that reads only crosshair state, so moving a finger
/// redraws a few lines and two tags instead of every candle.
///
/// When no crosshair is showing, this view produces no `Canvas` at all. That matters more than it
/// looks: an always-present Canvas is re-rasterised on every frame of every scroll even when its
/// draw closure immediately returns, and it reads `revision` only inside the active branch, so
/// while the chart is just being scrolled this view doesn't re-render at all.
struct CrosshairLayer: View {
    let state: CandleChartState
    let style: CandleChartStyle
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let index = state.crosshairIndex, let pointerY = state.crosshairY {
            // Only subscribes to viewport changes while the crosshair is up, so the vertical line
            // tracks its candle if the chart moves underneath it.
            let _ = state.revision
            let frame = state.currentFrame
            let scale = displayScale

            Canvas { context, _ in
                guard let frame, frame.candles.indices.contains(index) else { return }
                ChartPerformance.measure(.drawCrosshair) {
                let pixels = PixelGrid(scale: scale)

                // Drawn first so the crosshair lines and tags stay crisp on top of it. Always at
                // the candle's own (price-scale) position, regardless of which pane the finger is
                // vertically over — the glow marks *which candle*, not which pane is being read.
                drawFocusGlow(candleIndex: index, frame: frame, style: style, pixels: pixels, context: &context)

                let plot = frame.layout.plot
                let x = pixels.hairlineCenter(frame.centerX(ofCandle: index))

                // The vertical line runs through every pane, so the candle under the finger lines
                // up with its RSI or MACD value below. The horizontal line belongs to whichever
                // pane the finger is actually in.
                let bottom = frame.panes.last?.layout.plot.maxY ?? plot.maxY
                var lines = Path()
                lines.move(to: CGPoint(x: x, y: plot.minY))
                lines.addLine(to: CGPoint(x: x, y: bottom))

                let tagBackground = Color.primary
                let tagForeground = Color(uiColor: .systemBackground)

                if let pane = frame.panes.first(where: {
                    pointerY >= $0.layout.plot.minY && pointerY <= $0.layout.plot.maxY
                }) {
                    let y = pixels.hairlineCenter(
                        min(max(pointerY, pane.layout.plot.minY), pane.layout.plot.maxY)
                    )
                    lines.move(to: CGPoint(x: pane.layout.plot.minX, y: y))
                    lines.addLine(to: CGPoint(x: pane.layout.plot.maxX, y: y))
                    context.stroke(lines, with: .color(style.crosshairColor),
                                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    ChartText.drawPriceTag(
                        ChartFormat.price(pane.value(atY: y), digits: pane.ticks.fractionDigits),
                        y: y,
                        in: pane.layout.valueAxis,
                        background: tagBackground,
                        foreground: tagForeground,
                        context: &context
                    )
                } else {
                    let y = pixels.hairlineCenter(min(max(pointerY, plot.minY), plot.maxY))
                    lines.move(to: CGPoint(x: plot.minX, y: y))
                    lines.addLine(to: CGPoint(x: plot.maxX, y: y))
                    context.stroke(lines, with: .color(style.crosshairColor),
                                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    // These format on every crosshair move, which is fine — bounded by how fast a
                    // finger moves, not by the animation frame rate.
                    ChartText.drawPriceTag(
                        ChartFormat.price(frame.price(atY: y), digits: frame.priceFractionDigits),
                        y: y,
                        in: frame.layout.priceAxis,
                        background: tagBackground,
                        foreground: tagForeground,
                        context: &context
                    )
                }
                ChartText.drawTimeTag(
                    ChartFormat.detailedTime(frame.candles[index].time, interval: frame.interval),
                    x: x,
                    in: frame.layout.timeAxis,
                    background: tagBackground,
                    foreground: tagForeground,
                    context: &context
                )
                }
            }
            .allowsHitTesting(false)
            .sensoryFeedback(.selection, trigger: index)
        }
    }

    /// Traces a soft, additive rim glow around the focused candle's outline, so it draws the eye
    /// without covering it up.
    ///
    /// **Dulling the other candles is no longer this function's job.** An earlier version filled
    /// every *other* visible candle's silhouette with a flat dark tint from here, recomputed
    /// independently of the real candle geometry `BaseLayerRenderer` actually draws. At most zoom
    /// levels the two calculations landed close enough to look right, but they weren't the same
    /// numbers, and the mismatch showed up as the dim shapes visibly drifting out of alignment with
    /// the real candles underneath them. Dulling now happens inside `BaseLayerRenderer.drawCandles`
    /// itself — the non-focused candles are filled at reduced opacity as part of the very same draw
    /// call that draws them at full opacity, so there's no second, independently-computed shape
    /// that could ever disagree with the first.
    ///
    /// **Stroked, not filled.** The first version of the glow itself filled the candle's own
    /// silhouette with a blurred, high-opacity color — which, blended additively on top of the real
    /// candle drawn underneath, washed the whole shape out into a bright blob instead of a
    /// highlighted candle. Stroking only the outline puts the bright "ink" in a thin band that
    /// traces the edge; the interior — where the real candle's colour and detail live — is
    /// untouched by the glow at all.
    ///
    /// The glow's outline comes from `CandleGeometry.compute`, the same pixel-snapped calculation
    /// `BaseLayerRenderer` draws the real candle from, so the ring traces the candle's *actual*
    /// edges rather than a separately-derived approximation of them.
    ///
    /// The glow uses `GraphicsContext.Filter.blur(radius:)` only, deliberately avoiding
    /// `.shadow(...)`'s multi-parameter signature, which hasn't been run to confirm; `.blur` is a
    /// much smaller surface to get right.
    private func drawFocusGlow(
        candleIndex: Int,
        frame: ChartFrame,
        style: CandleChartStyle,
        pixels: PixelGrid,
        context: inout GraphicsContext
    ) {
        let candle = frame.candles[candleIndex]
        let glowColor = candle.isBullish ? style.upColor : style.downColor
        let outerBlurRadius: CGFloat = 10

        // Expanded a couple of points past the real edges, so the traced line sits just outside
        // the candle rather than directly on top of it.
        let expand: CGFloat = 2
        let geometry = CandleGeometry.compute(index: candleIndex, frame: frame, style: style, pixels: pixels)
        var shape = Path()
        shape.addRoundedRect(
            in: geometry.wick.insetBy(dx: -expand, dy: -expand),
            cornerSize: CGSize(width: 1.5, height: 1.5)
        )
        shape.addRoundedRect(
            in: geometry.body.insetBy(dx: -expand, dy: -expand),
            cornerSize: CGSize(width: 3, height: 3)
        )

        // Two stroked passes — a soft, wide, faint one and a tighter, brighter one — rather than
        // one, since a single pass reads as either too weak to notice or too strong to look soft.
        // Both stay well short of the opacity that visibly tints the candle's own interior.
        var outer = context
        outer.addFilter(.blur(radius: outerBlurRadius))
        outer.blendMode = .plusLighter
        outer.opacity = 0.22
        outer.stroke(shape, with: .color(glowColor), lineWidth: 2.5)

        var inner = context
        inner.addFilter(.blur(radius: 3))
        inner.blendMode = .plusLighter
        inner.opacity = 0.5
        inner.stroke(shape, with: .color(glowColor), lineWidth: 1.25)
    }
}
#endif
