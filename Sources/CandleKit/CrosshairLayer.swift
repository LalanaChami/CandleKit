#if os(iOS)
import SwiftUI

/// The crosshair lives in its own view that reads only crosshair state, so moving a finger
/// redraws a few lines and two tags instead of every candle.
struct CrosshairLayer: View {
    let state: CandleChartState
    let frame: ChartFrame
    let style: CandleChartStyle
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let index = state.crosshairIndex
        let pointerY = state.crosshairY

        Canvas { context, _ in
            guard let index, let pointerY, frame.candles.indices.contains(index) else { return }
            let pixels = PixelGrid(scale: displayScale)
            let plot = frame.layout.plot
            let x = pixels.hairlineCenter(frame.centerX(ofCandle: index))
            let y = pixels.hairlineCenter(min(max(pointerY, plot.minY), plot.maxY))

            var lines = Path()
            lines.move(to: CGPoint(x: x, y: plot.minY))
            lines.addLine(to: CGPoint(x: x, y: plot.maxY))
            lines.move(to: CGPoint(x: plot.minX, y: y))
            lines.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(lines, with: .color(style.crosshairColor), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            let tagBackground = Color.primary
            let tagForeground = Color(uiColor: .systemBackground)
            ChartText.drawPriceTag(
                ChartFormat.price(frame.price(atY: y), digits: frame.priceFractionDigits),
                y: y,
                in: frame.layout.priceAxis,
                background: tagBackground,
                foreground: tagForeground,
                context: &context
            )
            ChartText.drawTimeTag(
                ChartFormat.detailedTime(frame.candles[index].time, interval: frame.interval),
                x: x,
                in: frame.layout.timeAxis,
                background: tagBackground,
                foreground: tagForeground,
                context: &context
            )
        }
        .allowsHitTesting(false)
        .sensoryFeedback(.selection, trigger: index) { _, newValue in
            newValue != nil
        }
    }
}
#endif
