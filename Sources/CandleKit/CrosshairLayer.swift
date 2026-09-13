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

    /// Dims the rest of the chart and traces a soft, additive rim glow around the focused candle's
    /// outline, so it draws the eye without covering it up.
    ///
    /// **Stroked, not filled.** The first version filled the candle's own silhouette with a
    /// blurred, high-opacity color — which, blended additively on top of the real candle drawn
    /// underneath, washed the whole shape out into a bright blob instead of a highlighted candle.
    /// Stroking only the outline puts the bright "ink" in a thin band that traces the edge; the
    /// interior — where the real candle's colour and detail live — is untouched by the glow at all.
    ///
    /// The dim layer and the glow deliberately share one shape (`shape` below): the "hole" left in
    /// the dimming is the same geometry the glow is stroked from, blurred by the same amount, so
    /// the dimmed boundary and the glow's own soft edge coincide instead of reading as two
    /// mismatched rings. Drawing order matters — dim first, glow after — so the glow is never
    /// itself dimmed by the layer underneath it, and the crosshair's lines and tags (drawn by the
    /// caller afterward, on the original `context`, not a copy) are unaffected by either.
    ///
    /// Both the dim and the glow use `GraphicsContext.Filter.blur(radius:)` only, deliberately
    /// avoiding `.shadow(...)`'s multi-parameter signature, which hasn't been run to confirm;
    /// `.blur` is a much smaller surface to get right.
    private func drawFocusGlow(
        candleIndex: Int,
        frame: ChartFrame,
        style: CandleChartStyle,
        context: inout GraphicsContext
    ) {
        let candle = frame.candles[candleIndex]
        let centerX = frame.centerX(ofCandle: candleIndex)
        let bodyWidth = max(2, CGFloat(frame.viewport.spacing) * style.bodyWidthRatio)
        let highY = frame.y(forPrice: candle.high)
        let lowY = frame.y(forPrice: candle.low)
        let openY = frame.y(forPrice: candle.open)
        let closeY = frame.y(forPrice: candle.close)
        let bodyTop = min(openY, closeY)
        let bodyHeight = max(abs(openY - closeY), 2)
        let glowColor = candle.isBullish ? style.upColor : style.downColor
        let outerBlurRadius: CGFloat = 10

        // A little larger than the real candle, so the traced outline sits just outside its edges
        // rather than directly on top of them.
        let expand: CGFloat = 2
        var shape = Path()
        shape.addRoundedRect(
            in: CGRect(x: centerX - 1.5, y: highY, width: 3, height: max(lowY - highY, 2)),
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

        if style.crosshairDimOpacity > 0 {
            // Covers every pane, not just the price pane the candle lives in — dimming everything
            // uniformly reads as consistent, since there's no matching per-pane point highlight to
            // carve a second hole for.
            let coverage = CGRect(
                x: 0,
                y: 0,
                width: max(frame.layout.plot.maxX, frame.layout.priceAxis.maxX),
                height: frame.panes.last?.layout.plot.maxY ?? frame.layout.plot.maxY
            )
            // Even-odd fill: the outer rectangle and the inner `shape` overlap, so the overlapping
            // region cancels out, leaving a dimmed rectangle with a candle-shaped hole in it.
            var scrimPath = Path(coverage)
            scrimPath.addPath(shape)
            var scrim = context
            scrim.addFilter(.blur(radius: outerBlurRadius))
            scrim.fill(
                scrimPath,
                with: .color(.black.opacity(style.crosshairDimOpacity)),
                style: FillStyle(eoFill: true)
            )
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
}
#endif
