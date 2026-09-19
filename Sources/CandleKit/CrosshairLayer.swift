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
                drawFocusGlow(candleIndex: index, frame: frame, style: style, context: &context)

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

    /// Darkens the *other* candles and traces a soft, additive rim glow around the focused
    /// candle's outline, so it draws the eye without covering it up.
    ///
    /// **Only candle silhouettes are darkened — nothing else.** The first version dimmed the
    /// whole plot with a full-coverage scrim and cut a candle-shaped hole out of it, which read as
    /// the entire chart (grid, background, volume bars, indicator lines) going gray whenever the
    /// crosshair was up. What should visually recede is the *other candles*, not the chart around
    /// them, so this fills each non-focused visible candle's own body-and-wick shape with a flat
    /// dark tint and leaves everything else — background, grid, axes, volume, indicators — alone.
    /// The tint is filled with no blur and confined to each candle's exact geometry, so it can't
    /// bleed onto neighboring pixels the way a blurred scrim would.
    ///
    /// **The focused candle's own glow is stroked, not filled.** The first version of *that*
    /// filled the candle's own silhouette with a blurred, high-opacity color — which, blended
    /// additively on top of the real candle drawn underneath, washed the whole shape out into a
    /// bright blob instead of a highlighted candle. Stroking only the outline puts the bright
    /// "ink" in a thin band that traces the edge; the interior — where the real candle's colour and
    /// detail live — is untouched by the glow at all.
    ///
    /// Drawing order is: darken the other candles, then glow the focused one, so the glow is never
    /// itself dimmed by the layer underneath it, and the crosshair's lines and tags (drawn by the
    /// caller afterward, on the original `context`, not a copy) are unaffected by either.
    ///
    /// The glow uses `GraphicsContext.Filter.blur(radius:)` only, deliberately avoiding
    /// `.shadow(...)`'s multi-parameter signature, which hasn't been run to confirm; `.blur` is a
    /// much smaller surface to get right.
    private func drawFocusGlow(
        candleIndex: Int,
        frame: ChartFrame,
        style: CandleChartStyle,
        context: inout GraphicsContext
    ) {
        let candle = frame.candles[candleIndex]
        let glowColor = candle.isBullish ? style.upColor : style.downColor
        let outerBlurRadius: CGFloat = 10
        let shape = candleSilhouette(candleIndex, frame: frame, style: style, expand: 2)

        if style.crosshairDimOpacity > 0 {
            // Every OTHER visible candle is flattened into one path and filled in a single call,
            // rather than one fill per candle, so this stays cheap even with a wide viewport.
            var others = Path()
            for index in frame.visible where index != candleIndex && frame.candles.indices.contains(index) {
                others.addPath(candleSilhouette(index, frame: frame, style: style, expand: 0))
            }
            context.fill(others, with: .color(.black.opacity(style.crosshairDimOpacity)))
        }

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

    /// The body-and-wick outline of one candle, in plot coordinates — shared by the focused
    /// candle's glow (which strokes it, expanded slightly past the real edges so the traced line
    /// sits just outside them) and the dimming fill over every other candle (which fills it
    /// exactly, `expand: 0`, so the tint never spills past the candle it belongs to).
    private func candleSilhouette(
        _ index: Int,
        frame: ChartFrame,
        style: CandleChartStyle,
        expand: CGFloat
    ) -> Path {
        let candle = frame.candles[index]
        let centerX = frame.centerX(ofCandle: index)
        let bodyWidth = max(2, CGFloat(frame.viewport.spacing) * style.bodyWidthRatio)
        let highY = frame.y(forPrice: candle.high)
        let lowY = frame.y(forPrice: candle.low)
        let openY = frame.y(forPrice: candle.open)
        let closeY = frame.y(forPrice: candle.close)
        let bodyTop = min(openY, closeY)
        let bodyHeight = max(abs(openY - closeY), 2)

        var shape = Path()
        shape.addRoundedRect(
            in: CGRect(
                x: centerX - 1.5 - expand,
                y: highY - expand,
                width: 1 + expand * 2,
                height: max(lowY - highY, 2) + expand * 2
            ),
            cornerSize: CGSize(width: 1.5, height: 1.5)
        )
        shape.addRoundedRect(
            in: CGRect(
                x: centerX - bodyWidth / 2 - expand,
                y: bodyTop - expand,
                width: bodyWidth + expand * 2,
                height: bodyHeight + expand * 2
            ),
            cornerSize: CGSize(width: 3, height: 3)
        )
        return shape
    }
}
#endif
