#if os(iOS)
import SwiftUI

/// Everything except the crosshair, drawn in one Canvas.
struct ChartBaseLayer: View {
    let frame: ChartFrame
    let style: CandleChartStyle
    let appearPhase: Double
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, _ in
            let renderer = BaseLayerRenderer(frame: frame, style: style, pixels: PixelGrid(scale: displayScale), appearPhase: appearPhase)
            renderer.draw(in: &context)
        }
        .allowsHitTesting(false)
    }
}

struct BaseLayerRenderer {
    let frame: ChartFrame
    let style: CandleChartStyle
    let pixels: PixelGrid
    /// 0 = all candles hidden (start of appear animation), 1 = fully visible (steady state).
    let appearPhase: Double

    /// Number of quantised opacity levels used by the appear animation. Bucket 0 is invisible, so
    /// this gives 7 visible steps across a fade zone only a couple of candles wide.
    private static let appearBucketCount = 8

    func draw(in context: inout GraphicsContext) {
        ChartPerformance.measure(.drawTotal) {
            drawPhases(in: &context)
        }
    }

    private func drawPhases(in context: inout GraphicsContext) {
        var plotContext = context
        plotContext.clip(to: Path(frame.layout.plot))
        ChartPerformance.measure(.drawGrid) { drawGrid(in: &plotContext) }
        if appearPhase < 1.0 {
            // During the appear animation candles draw per-candle (no path batching) so each can
            // carry its own staggered opacity. Volume, indicators and the last-price line fade in
            // together at the overall phase so they trail the candles visually.
            ChartPerformance.measure(.drawAppear) { drawAnimatedCandles(in: &plotContext) }
            var fadedContext = plotContext
            fadedContext.opacity *= appearPhase
            ChartPerformance.measure(.drawVolume) { drawVolume(in: &fadedContext) }
            ChartPerformance.measure(.drawIndicators) { drawIndicators(in: &fadedContext) }
            drawLastPriceLine(in: &fadedContext)
        } else {
            ChartPerformance.measure(.drawVolume) { drawVolume(in: &plotContext) }
            ChartPerformance.measure(.drawCandles) { drawCandles(in: &plotContext) }
            ChartPerformance.measure(.drawIndicators) { drawIndicators(in: &plotContext) }
            drawLastPriceLine(in: &plotContext)
        }
        ChartPerformance.measure(.drawAxes) { drawAxes(in: &context) }
    }

    // MARK: Geometry

    /// Body and wick widths in whole device pixels, with matching parity so the wick is exactly centered.
    private var widthsInPixels: (body: CGFloat, wick: CGFloat) {
        let wick = max(1, pixels.scale.rounded())
        var body = max(wick, (CGFloat(frame.viewport.spacing) * style.bodyWidthRatio * pixels.scale).rounded(.down))
        if Int(body - wick) % 2 != 0 {
            body -= 1
        }
        return (max(body, wick), wick)
    }

    /// Left edge of a candle body, in device pixels.
    private func bodyLeftInPixels(_ index: Int, bodyWidth: CGFloat) -> CGFloat {
        let center = (frame.centerX(ofCandle: index) * pixels.scale).rounded()
        return (center - bodyWidth / 2).rounded(.down)
    }

    // MARK: Layers

    private func drawGrid(in context: inout GraphicsContext) {
        let plot = frame.layout.plot
        var grid = Path()
        for price in frame.priceTicks.values {
            let y = pixels.hairlineCenter(frame.y(forPrice: price))
            guard y >= plot.minY, y <= plot.maxY else { continue }
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
        }
        for tick in frame.timeTicks {
            let x = pixels.hairlineCenter(frame.centerX(ofCandle: tick.index))
            grid.move(to: CGPoint(x: x, y: plot.minY))
            grid.addLine(to: CGPoint(x: x, y: plot.maxY))
        }
        context.stroke(grid, with: .color(style.gridColor), lineWidth: pixels.hairline)
    }

    private func drawVolume(in context: inout GraphicsContext) {
        guard let band = frame.layout.volumeBand, frame.volumeMax > 0 else { return }
        let bodyWidth = widthsInPixels.body
        let bandHeight = band.upperBound - band.lowerBound
        var rising = Path()
        var falling = Path()

        for index in frame.visible {
            let candle = frame.candles[index]
            guard candle.volume > 0 else { continue }
            let height = max(pixels.hairline, pixels.snap(CGFloat(candle.volume / frame.volumeMax) * bandHeight))
            let rect = CGRect(
                x: bodyLeftInPixels(index, bodyWidth: bodyWidth) / pixels.scale,
                y: band.upperBound - height,
                width: bodyWidth / pixels.scale,
                height: height
            )
            if candle.isBullish {
                rising.addRect(rect)
            } else {
                falling.addRect(rect)
            }
        }
        context.fill(rising, with: .color(style.upColor.opacity(style.volumeOpacity)))
        context.fill(falling, with: .color(style.downColor.opacity(style.volumeOpacity)))
    }

    /// Candles are batched into a handful of paths, so the draw-call count is constant
    /// no matter how many candles are on screen.
    private func drawCandles(in context: inout GraphicsContext) {
        let (bodyWidth, wickWidth) = widthsInPixels
        let scale = pixels.scale
        let drawsBodies = bodyWidth > wickWidth
        var risingBodies = Path()
        var fallingBodies = Path()
        var hollowBodies = Path()
        var risingWicks = Path()
        var fallingWicks = Path()

        for index in frame.visible {
            let candle = frame.candles[index]
            let bodyLeft = bodyLeftInPixels(index, bodyWidth: bodyWidth)
            let wickX = (bodyLeft + (bodyWidth - wickWidth) / 2) / scale
            let wickPoints = wickWidth / scale

            let highY = pixels.snap(frame.y(forPrice: candle.high))
            let lowY = pixels.snap(frame.y(forPrice: candle.low))
            let openY = pixels.snap(frame.y(forPrice: candle.open))
            let closeY = pixels.snap(frame.y(forPrice: candle.close))
            let bodyTop = min(openY, closeY)
            let bodyHeight = max(abs(openY - closeY), pixels.hairline)
            let body = CGRect(x: bodyLeft / scale, y: bodyTop, width: bodyWidth / scale, height: bodyHeight)

            if candle.isBullish && style.hollowUpCandles && drawsBodies {
                // Hollow candles show the wick only outside the body.
                risingWicks.addRect(CGRect(x: wickX, y: highY, width: wickPoints, height: max(0, bodyTop - highY)))
                risingWicks.addRect(CGRect(x: wickX, y: body.maxY, width: wickPoints, height: max(0, lowY - body.maxY)))
                hollowBodies.addRect(body.insetBy(dx: wickPoints / 2, dy: min(wickPoints / 2, bodyHeight / 2)))
            } else {
                let wick = CGRect(x: wickX, y: highY, width: wickPoints, height: max(lowY - highY, pixels.hairline))
                if candle.isBullish {
                    risingWicks.addRect(wick)
                    if drawsBodies { risingBodies.addRect(body) }
                } else {
                    fallingWicks.addRect(wick)
                    if drawsBodies { fallingBodies.addRect(body) }
                }
            }
        }

        context.fill(risingWicks, with: .color(style.upColor))
        context.fill(fallingWicks, with: .color(style.downColor))
        context.fill(risingBodies, with: .color(style.upColor))
        context.fill(fallingBodies, with: .color(style.downColor))
        if !hollowBodies.isEmpty {
            context.stroke(hollowBodies, with: .color(style.upColor), lineWidth: wickWidth / scale)
        }
    }

    /// Appear-animation path. A reveal line sweeps left-to-right across the plot at constant
    /// speed (points/second, not index-fraction), so every candle gets the same exposure time
    /// regardless of how many are on screen or how far the user has zoomed in. Each candle fades
    /// in over a zone 2.5 candle slots wide, giving a soft leading edge on the wave.
    ///
    /// Candles are grouped into a small number of opacity buckets rather than drawn one at a time.
    /// The original version copied the `GraphicsContext` per candle and issued two or three fills
    /// for each — with several hundred candles on screen that's well over a thousand draw calls and
    /// as many context copies *per frame*, which is why the animation stuttered on exactly the wide
    /// zoom levels where it should have looked best. Quantising opacity into `appearBucketCount`
    /// steps caps it at a couple of dozen fills instead. The fade zone only ever spans a few candles,
    /// so the banding this introduces isn't visible.
    private func drawAnimatedCandles(in context: inout GraphicsContext) {
        guard !frame.visible.isEmpty else { return }

        let (bodyWidth, wickWidth) = widthsInPixels
        let scale = pixels.scale
        let drawsBodies = bodyWidth > wickWidth

        // The reveal line moves from (plotMinX - fadeZone) to (plotMaxX + fadeZone) as phase
        // goes 0→1, so the first candle starts fading in at phase 0 and the last finishes at 1.
        let plotMinX = Double(frame.layout.plot.minX)
        let plotMaxX = Double(frame.layout.plot.maxX)
        let fadeZone = max(12.0, frame.viewport.spacing * 2.5)
        let revealX  = (plotMinX - fadeZone) + appearPhase * (plotMaxX - plotMinX + 2 * fadeZone)

        let buckets = Self.appearBucketCount
        let topBucket = Double(buckets - 1)
        var risingWicks   = [Path](repeating: Path(), count: buckets)
        var fallingWicks  = [Path](repeating: Path(), count: buckets)
        var risingBodies  = [Path](repeating: Path(), count: buckets)
        var fallingBodies = [Path](repeating: Path(), count: buckets)
        var hollowBodies  = [Path](repeating: Path(), count: buckets)

        for index in frame.visible {
            let cx = Double(frame.centerX(ofCandle: index))
            let opacity = max(0, min(1, (revealX - cx) / fadeZone))
            // Bucket 0 is fully transparent, so skipping it also skips candles not yet revealed.
            let bucket = Int((opacity * topBucket).rounded())
            guard bucket > 0 else { continue }

            let candle   = frame.candles[index]
            let bodyLeft = bodyLeftInPixels(index, bodyWidth: bodyWidth)
            let wickX    = (bodyLeft + (bodyWidth - wickWidth) / 2) / scale
            let wickPts  = wickWidth / scale

            let highY   = pixels.snap(frame.y(forPrice: candle.high))
            let lowY    = pixels.snap(frame.y(forPrice: candle.low))
            let openY   = pixels.snap(frame.y(forPrice: candle.open))
            let closeY  = pixels.snap(frame.y(forPrice: candle.close))
            let bodyTop = min(openY, closeY)
            let bodyH   = max(abs(openY - closeY), pixels.hairline)
            let body    = CGRect(x: bodyLeft / scale, y: bodyTop, width: bodyWidth / scale, height: bodyH)

            if candle.isBullish && style.hollowUpCandles && drawsBodies {
                risingWicks[bucket].addRect(CGRect(x: wickX, y: highY, width: wickPts, height: max(0, bodyTop - highY)))
                risingWicks[bucket].addRect(CGRect(x: wickX, y: body.maxY, width: wickPts, height: max(0, lowY - body.maxY)))
                hollowBodies[bucket].addRect(body.insetBy(dx: wickPts / 2, dy: min(wickPts / 2, bodyH / 2)))
            } else {
                let wick = CGRect(x: wickX, y: highY, width: wickPts, height: max(lowY - highY, pixels.hairline))
                if candle.isBullish {
                    risingWicks[bucket].addRect(wick)
                    if drawsBodies { risingBodies[bucket].addRect(body) }
                } else {
                    fallingWicks[bucket].addRect(wick)
                    if drawsBodies { fallingBodies[bucket].addRect(body) }
                }
            }
        }

        for bucket in 1..<buckets {
            let opacity = Double(bucket) / topBucket
            var bucketContext = context
            bucketContext.opacity *= opacity

            if !risingWicks[bucket].isEmpty {
                bucketContext.fill(risingWicks[bucket], with: .color(style.upColor))
            }
            if !fallingWicks[bucket].isEmpty {
                bucketContext.fill(fallingWicks[bucket], with: .color(style.downColor))
            }
            if !risingBodies[bucket].isEmpty {
                bucketContext.fill(risingBodies[bucket], with: .color(style.upColor))
            }
            if !fallingBodies[bucket].isEmpty {
                bucketContext.fill(fallingBodies[bucket], with: .color(style.downColor))
            }
            if !hollowBodies[bucket].isEmpty {
                bucketContext.stroke(hollowBodies[bucket], with: .color(style.upColor), lineWidth: wickWidth / scale)
            }
        }
    }

    private func drawIndicators(in context: inout GraphicsContext) {
        for (indicator, values) in zip(frame.indicators, frame.indicatorSeries) {
            var path = Path()
            var penDown = false
            for index in frame.lineRange {
                guard index < values.count, let value = values[index] else {
                    penDown = false
                    continue
                }
                let point = CGPoint(x: frame.centerX(ofCandle: index), y: frame.y(forPrice: value))
                if penDown {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    penDown = true
                }
            }
            context.stroke(
                path,
                with: .color(indicator.color),
                style: StrokeStyle(lineWidth: indicator.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawLastPriceLine(in context: inout GraphicsContext) {
        guard let last = frame.candles.last else { return }
        let plot = frame.layout.plot
        let y = pixels.hairlineCenter(frame.y(forPrice: last.close))
        var line = Path()
        line.move(to: CGPoint(x: plot.minX, y: y))
        line.addLine(to: CGPoint(x: plot.maxX, y: y))
        context.stroke(
            line,
            with: .color((last.isBullish ? style.upColor : style.downColor).opacity(0.8)),
            style: StrokeStyle(lineWidth: 1, dash: [2, 3])
        )
    }

    private func drawAxes(in context: inout GraphicsContext) {
        let layout = frame.layout

        var border = Path()
        let borderX = pixels.hairlineCenter(layout.plot.maxX)
        border.move(to: CGPoint(x: borderX, y: layout.plot.minY))
        border.addLine(to: CGPoint(x: borderX, y: layout.plot.maxY))
        let borderY = pixels.hairlineCenter(layout.plot.maxY)
        border.move(to: CGPoint(x: layout.plot.minX, y: borderY))
        border.addLine(to: CGPoint(x: layout.priceAxis.maxX, y: borderY))
        context.stroke(border, with: .color(style.gridColor), lineWidth: pixels.hairline)

        // Labels are pre-formatted in makeFrame; this loop must not call any FormatStyle.
        for (price, label) in zip(frame.priceTicks.values, frame.priceTickLabels) {
            let y = frame.y(forPrice: price)
            guard y > layout.plot.minY + 6, y < layout.plot.maxY - 6 else { continue }
            context.draw(
                ChartText.label(label, color: style.axisLabelColor),
                at: CGPoint(x: layout.priceAxis.minX + 6, y: y),
                anchor: .leading
            )
        }

        let timeFadeZone = 48.0
        for (tick, label) in zip(frame.timeTicks, frame.timeTickLabels) {
            let x = frame.centerX(ofCandle: tick.index)
            let minX = layout.timeAxis.minX
            let maxX = layout.timeAxis.maxX
            guard x > minX + 4, x < maxX - 4 else { continue }
            let opacity = min((x - minX) / timeFadeZone, (maxX - x) / timeFadeZone, 1.0)
            var labelContext = context
            labelContext.opacity *= opacity
            labelContext.draw(
                ChartText.label(
                    label,
                    color: style.axisLabelColor,
                    emphasized: tick.unit > frame.baseTimeUnit
                ),
                at: CGPoint(x: x, y: layout.timeAxis.midY),
                anchor: .center
            )
        }

        // The last-price tag is no longer drawn here — see `LastPriceBadge` in
        // CandlestickChart.swift. It needed to become a real SwiftUI view so its digits can use
        // `.contentTransition(.numericText())`, which has no Canvas equivalent.
    }
}
#endif
