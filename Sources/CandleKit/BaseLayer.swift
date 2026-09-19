#if os(iOS)
import SwiftUI

/// Everything except the crosshair, drawn in one Canvas.
struct ChartBaseLayer: View {
    let frame: ChartFrame
    let style: CandleChartStyle
    let appearPhase: Double
    /// The candle under the crosshair, or `nil` when no crosshair is up. Every other visible
    /// candle draws a touch duller while this is set — see `BaseLayerRenderer.drawCandles`.
    var focusedCandleIndex: Int? = nil
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, _ in
            let renderer = BaseLayerRenderer(
                frame: frame,
                style: style,
                pixels: PixelGrid(scale: displayScale),
                appearPhase: appearPhase,
                focusedCandleIndex: focusedCandleIndex
            )
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
    /// The candle under the crosshair, or `nil` when no crosshair is up.
    var focusedCandleIndex: Int? = nil

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
        ChartPerformance.measure(.drawIndicators) { drawPanes(in: &context) }
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
    ///
    /// When a crosshair is up, every candle *except* the focused one is batched separately and
    /// filled at reduced opacity instead of its normal, full-strength color — the "little dull"
    /// look a hovered candle should stand out against. Both batches come from the exact same
    /// per-candle rectangles (`CandleGeometry.compute`, the same helper the crosshair's own glow
    /// uses), so which batch a candle lands in is the only thing that changes about it; there's no
    /// separate overlay shape that could drift out of alignment with what's actually drawn here.
    private func drawCandles(in context: inout GraphicsContext) {
        let (bodyWidth, wickWidth) = widthsInPixels
        let scale = pixels.scale
        let drawsBodies = bodyWidth > wickWidth
        var risingBodies = Path()
        var fallingBodies = Path()
        var hollowBodies = Path()
        var risingWicks = Path()
        var fallingWicks = Path()
        // Populated only while a crosshair is up; stay empty (and unused) otherwise.
        var dimRisingBodies = Path()
        var dimFallingBodies = Path()
        var dimHollowBodies = Path()
        var dimRisingWicks = Path()
        var dimFallingWicks = Path()

        for index in frame.visible {
            let candle = frame.candles[index]
            let geometry = CandleGeometry.compute(index: index, frame: frame, style: style, pixels: pixels)
            let body = geometry.body
            let wick = geometry.wick
            let isDimmed = focusedCandleIndex != nil && focusedCandleIndex != index

            if candle.isBullish && style.hollowUpCandles && drawsBodies {
                // Hollow candles show the wick only outside the body.
                let upperWick = CGRect(x: wick.minX, y: wick.minY, width: wick.width, height: max(0, body.minY - wick.minY))
                let lowerWick = CGRect(x: wick.minX, y: body.maxY, width: wick.width, height: max(0, wick.maxY - body.maxY))
                let hollowBody = body.insetBy(dx: wick.width / 2, dy: min(wick.width / 2, body.height / 2))
                if isDimmed {
                    dimRisingWicks.addRect(upperWick)
                    dimRisingWicks.addRect(lowerWick)
                    dimHollowBodies.addRect(hollowBody)
                } else {
                    risingWicks.addRect(upperWick)
                    risingWicks.addRect(lowerWick)
                    hollowBodies.addRect(hollowBody)
                }
            } else if candle.isBullish {
                if isDimmed {
                    dimRisingWicks.addRect(wick)
                    if drawsBodies { dimRisingBodies.addRect(body) }
                } else {
                    risingWicks.addRect(wick)
                    if drawsBodies { risingBodies.addRect(body) }
                }
            } else {
                if isDimmed {
                    dimFallingWicks.addRect(wick)
                    if drawsBodies { dimFallingBodies.addRect(body) }
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

        if focusedCandleIndex != nil {
            // `crosshairDimOpacity` (default 0.35) is how much duller a non-focused candle gets,
            // not how dark an overlay on top of it is — reducing the fill's own opacity blends it
            // toward whatever's behind it (grid, background), reading as a muted, flattened candle
            // rather than a separate gray shape sitting over a sharp one.
            let dimOpacity = 1 - max(0, min(1, style.crosshairDimOpacity))
            context.fill(dimRisingWicks, with: .color(style.upColor.opacity(dimOpacity)))
            context.fill(dimFallingWicks, with: .color(style.downColor.opacity(dimOpacity)))
            context.fill(dimRisingBodies, with: .color(style.upColor.opacity(dimOpacity)))
            context.fill(dimFallingBodies, with: .color(style.downColor.opacity(dimOpacity)))
            if !dimHollowBodies.isEmpty {
                context.stroke(dimHollowBodies, with: .color(style.upColor.opacity(dimOpacity)), lineWidth: wickWidth / scale)
            }
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

    /// Where an indicator's values map to on screen. Panes and the price overlay differ only in
    /// this, so every drawing routine below takes one instead of reaching for the price scale.
    private struct ValueMapping {
        let y: (Double) -> CGFloat
        let plot: CGRect
    }

    private var priceMapping: ValueMapping {
        ValueMapping(y: { frame.y(forPrice: $0) }, plot: frame.layout.plot)
    }

    /// Draws every price-pane indicator: fills first so lines sit on top, then reference levels,
    /// then the plots themselves.
    private func drawIndicators(in context: inout GraphicsContext) {
        let mapping = priceMapping
        for indicator in frame.indicators {
            draw(indicator, using: mapping, in: &context)
        }
    }

    /// Draws each indicator pane: its own grid, separator, contents and value axis.
    ///
    /// Every pane is clipped to itself, so an indicator that briefly exceeds its autoscaled range
    /// can't bleed into the candles above it.
    func drawPanes(in context: inout GraphicsContext) {
        for separatorY in frame.layout.separators {
            var line = Path()
            let y = pixels.hairlineCenter(separatorY)
            line.move(to: CGPoint(x: frame.layout.plot.minX, y: y))
            line.addLine(to: CGPoint(x: frame.layout.priceAxis.maxX, y: y))
            context.stroke(line, with: .color(style.gridColor), lineWidth: pixels.hairline)
        }

        for pane in frame.panes {
            let mapping = ValueMapping(y: { pane.y(forValue: $0) }, plot: pane.layout.plot)

            var paneContext = context
            paneContext.clip(to: Path(pane.layout.plot))
            drawPaneGrid(pane, in: &paneContext)
            for indicator in pane.indicators {
                draw(indicator, using: mapping, in: &paneContext)
            }

            drawPaneAxis(pane, in: &context)
            drawPaneTitle(pane, in: &context)
        }
    }

    private func drawPaneGrid(_ pane: ResolvedPane, in context: inout GraphicsContext) {
        var grid = Path()
        for value in pane.ticks.values {
            let y = pixels.hairlineCenter(pane.y(forValue: value))
            guard y >= pane.layout.plot.minY, y <= pane.layout.plot.maxY else { continue }
            grid.move(to: CGPoint(x: pane.layout.plot.minX, y: y))
            grid.addLine(to: CGPoint(x: pane.layout.plot.maxX, y: y))
        }
        context.stroke(grid, with: .color(style.gridColor), lineWidth: pixels.hairline)
    }

    private func drawPaneAxis(_ pane: ResolvedPane, in context: inout GraphicsContext) {
        for (value, label) in zip(pane.ticks.values, pane.tickLabels) {
            let y = pane.y(forValue: value)
            guard y > pane.layout.plot.minY + 5, y < pane.layout.plot.maxY - 5 else { continue }
            context.draw(
                ChartText.label(label, color: style.axisLabelColor),
                at: CGPoint(x: pane.layout.valueAxis.minX + 6, y: y),
                anchor: .leading
            )
        }
    }

    /// The indicator's name in the pane's top-left corner, so a stack of panes is readable without
    /// a legend.
    private func drawPaneTitle(_ pane: ResolvedPane, in context: inout GraphicsContext) {
        guard let first = pane.indicators.first else { return }
        context.draw(
            ChartText.label(first.label, color: style.axisLabelColor, emphasized: true),
            at: CGPoint(x: pane.layout.plot.minX + 6, y: pane.layout.plot.minY + 4),
            anchor: .topLeading
        )
    }

    private func draw(_ indicator: ResolvedIndicator, using mapping: ValueMapping, in context: inout GraphicsContext) {
        drawFills(of: indicator, using: mapping, in: &context)
        drawLevels(of: indicator, using: mapping, in: &context)
        for plot in indicator.result.plots {
            draw(plot, of: indicator, using: mapping, in: &context)
        }
    }

    private func draw(
        _ plot: IndicatorPlot,
        of indicator: ResolvedIndicator,
        using mapping: ValueMapping,
        in context: inout GraphicsContext
    ) {
        switch plot.style {
        case let .line(_, dash):
            context.stroke(
                polyline(plot.values, using: mapping),
                with: .color(indicator.color(for: plot.colorRole)),
                style: StrokeStyle(
                    lineWidth: indicator.width(for: plot.style),
                    lineCap: dash == nil ? .round : .butt,
                    lineJoin: .round,
                    dash: dash?.map { CGFloat($0) } ?? []
                )
            )

        case .steppedLine:
            context.stroke(
                steppedPolyline(plot.values, using: mapping),
                with: .color(indicator.color(for: plot.colorRole)),
                style: StrokeStyle(lineWidth: indicator.width(for: plot.style), lineJoin: .miter)
            )

        case let .histogram(baseline):
            drawHistogram(plot, baseline: baseline, of: indicator, using: mapping, in: &context)

        case let .points(radius):
            drawPoints(plot, radius: CGFloat(radius), of: indicator, using: mapping, in: &context)

        case .hidden:
            break
        }
    }

    /// A polyline over `lineRange`, lifting the pen across `nil` gaps so a warm-up period or a
    /// missing value leaves a break rather than a line to nowhere.
    private func polyline(_ values: [Double?], using mapping: ValueMapping) -> Path {
        var path = Path()
        var penDown = false
        for index in frame.lineRange {
            guard index < values.count, let value = values[index], value.isFinite else {
                penDown = false
                continue
            }
            let point = CGPoint(x: frame.centerX(ofCandle: index), y: mapping.y(value))
            if penDown {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                penDown = true
            }
        }
        return path
    }

    /// Holds each value until the next one, for indicators like SuperTrend whose level is constant
    /// between changes and should not be interpolated.
    private func steppedPolyline(_ values: [Double?], using mapping: ValueMapping) -> Path {
        var path = Path()
        var previous: CGPoint?
        for index in frame.lineRange {
            guard index < values.count, let value = values[index], value.isFinite else {
                previous = nil
                continue
            }
            let point = CGPoint(x: frame.centerX(ofCandle: index), y: mapping.y(value))
            if let previous {
                path.addLine(to: CGPoint(x: point.x, y: previous.y))
                path.addLine(to: point)
            } else {
                path.move(to: point)
            }
            previous = point
        }
        return path
    }

    /// Batched into two paths — one per sign — so a long histogram stays a constant number of draw
    /// calls, the same rule the candles follow.
    private func drawHistogram(
        _ plot: IndicatorPlot,
        baseline: Double,
        of indicator: ResolvedIndicator,
        using mapping: ValueMapping,
        in context: inout GraphicsContext
    ) {
        let width = max(pixels.hairline, CGFloat(frame.viewport.spacing) * style.bodyWidthRatio)
        let baselineY = mapping.y(baseline)
        var positive = Path()
        var negative = Path()

        for index in frame.visible {
            guard index < plot.values.count, let value = plot.values[index], value.isFinite else { continue }
            let valueY = mapping.y(value)
            let top = min(valueY, baselineY)
            let height = max(abs(valueY - baselineY), pixels.hairline)
            let rect = CGRect(x: frame.centerX(ofCandle: index) - width / 2, y: top, width: width, height: height)
            if value >= baseline {
                positive.addRect(rect)
            } else {
                negative.addRect(rect)
            }
        }

        context.fill(positive, with: .color(indicator.color(for: plot.colorRole, value: 1)))
        context.fill(negative, with: .color(indicator.color(for: plot.colorRole, value: -1)))
    }

    private func drawPoints(
        _ plot: IndicatorPlot,
        radius: CGFloat,
        of indicator: ResolvedIndicator,
        using mapping: ValueMapping,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        for index in frame.visible {
            guard index < plot.values.count, let value = plot.values[index], value.isFinite else { continue }
            let center = CGPoint(x: frame.centerX(ofCandle: index), y: mapping.y(value))
            path.addEllipse(in: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            ))
        }
        context.fill(path, with: .color(indicator.color(for: plot.colorRole)))
    }

    /// The shaded region between two plots — Bollinger's channel, Ichimoku's cloud.
    ///
    /// Built as a single closed path running forward along the upper edge and back along the lower,
    /// restarted wherever either side has a gap so a warm-up period doesn't produce a fill anchored
    /// to nothing.
    private func drawFills(
        of indicator: ResolvedIndicator,
        using mapping: ValueMapping,
        in context: inout GraphicsContext
    ) {
        for fill in indicator.result.fills {
            guard let lower = indicator.result.plot(fill.lowerPlotKey)?.values,
                  let upper = indicator.result.plot(fill.upperPlotKey)?.values else { continue }

            var path = Path()
            var run: [(x: CGFloat, lower: CGFloat, upper: CGFloat)] = []

            func flush() {
                guard run.count > 1 else { run.removeAll(); return }
                path.move(to: CGPoint(x: run[0].x, y: run[0].upper))
                for point in run.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x, y: point.upper))
                }
                for point in run.reversed() {
                    path.addLine(to: CGPoint(x: point.x, y: point.lower))
                }
                path.closeSubpath()
                run.removeAll()
            }

            for index in frame.lineRange {
                guard index < lower.count, index < upper.count,
                      let low = lower[index], let high = upper[index],
                      low.isFinite, high.isFinite else {
                    flush()
                    continue
                }
                run.append((
                    x: frame.centerX(ofCandle: index),
                    lower: mapping.y(low),
                    upper: mapping.y(high)
                ))
            }
            flush()

            context.fill(path, with: .color(indicator.color(for: fill.colorRole).opacity(fill.opacity)))
        }
    }

    private func drawLevels(
        of indicator: ResolvedIndicator,
        using mapping: ValueMapping,
        in context: inout GraphicsContext
    ) {
        for level in indicator.result.levels {
            let y = pixels.hairlineCenter(mapping.y(level.value))
            guard y >= mapping.plot.minY, y <= mapping.plot.maxY else { continue }
            var path = Path()
            path.move(to: CGPoint(x: mapping.plot.minX, y: y))
            path.addLine(to: CGPoint(x: mapping.plot.maxX, y: y))
            context.stroke(
                path,
                with: .color(indicator.color(for: level.colorRole)),
                style: StrokeStyle(lineWidth: pixels.hairline, dash: level.dash?.map { CGFloat($0) } ?? [])
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

        // No vertical divider between the plot and the price axis: when a glass material is set
        // (`CandlestickChart.PriceAxisGlassPanel`), the panel's own edge reads as the boundary, and
        // a stroked line on top of translucent glass looked redundant. The horizontal divider along
        // the bottom stays either way.
        var border = Path()
        let borderY = pixels.hairlineCenter(layout.plot.maxY)
        border.move(to: CGPoint(x: layout.plot.minX, y: borderY))
        border.addLine(to: CGPoint(x: layout.priceAxis.maxX, y: borderY))
        context.stroke(border, with: .color(style.gridColor), lineWidth: pixels.hairline)

        // Price tick labels are drawn by `PriceAxisGlassPanel` as real `Text` views now, not here —
        // a `Material` only blurs what's behind the view it's attached to, so text painted into
        // this same Canvas would have been blurred along with the candles instead of staying crisp
        // on top of them. When no material is set, `PriceAxisGlassPanel` still draws the same
        // labels (just without a background layer beneath them), so this isn't material-only.

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
