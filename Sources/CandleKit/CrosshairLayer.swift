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
}
#endif
