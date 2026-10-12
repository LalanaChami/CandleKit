#if os(iOS)
import SwiftUI

/// Renders every visible, non-hidden `Drawing`, the tool-in-progress preview, and the selected
/// drawing's anchor handles — a separate Canvas layer over the candles, the same relationship
/// `CrosshairLayer` has to `ChartBaseLayer`.
struct DrawingsLayer: View {
    let state: CandleChartState
    let controller: DrawingController
    let drawings: [Drawing]

    var body: some View {
        // Tracks the viewport (so drawings pan and zoom with the candles) and the controller's own
        // revision (selection changes, live drag preview) — the same "read revision once, redraw
        // this one Canvas" split every other layer in this file uses.
        let _ = state.revision
        let _ = controller.revision
        // Read everything the renderer needs from `controller` here, in `body` — which, like every
        // View's body, runs on the main actor — rather than inside the `Canvas` closure below. That
        // closure runs off the main actor, so touching a `@MainActor` object's properties from
        // inside it (as an earlier version of this file did, passing `controller` straight through)
        // doesn't type-check; plain values captured out here have no such restriction.
        let selectedDrawingID = controller.selectedDrawingID
        let previewDrawing = controller.previewDrawing
        if let frame = state.currentFrame {
            Canvas { context, _ in
                let renderer = DrawingsLayerRenderer(
                    frame: frame,
                    drawings: drawings,
                    selectedDrawingID: selectedDrawingID,
                    previewDrawing: previewDrawing
                )
                renderer.draw(in: &context)
            }
            .allowsHitTesting(false)
        }
    }
}

struct DrawingsLayerRenderer {
    let frame: ChartFrame
    let drawings: [Drawing]
    let selectedDrawingID: UUID?
    let previewDrawing: Drawing?

    func draw(in context: inout GraphicsContext) {
        var plotContext = context
        plotContext.clip(to: Path(frame.layout.plot))
        for drawing in drawings where !drawing.isHidden {
            draw(drawing, selected: drawing.id == selectedDrawingID, in: &plotContext)
        }
        if let previewDrawing {
            draw(previewDrawing, selected: false, in: &plotContext)
            // A trader watching a price line follow their finger wants to know exactly where it'll
            // land before letting go, so a two-anchor tool gets a live price/percent delta near the
            // drag point while it's still in progress. A committed multi-anchor drawing doesn't
            // repeat this — it would just be permanent clutter on every trend line on the chart.
            drawMeasurementBadge(for: previewDrawing, in: &plotContext)
        }

        // Every horizontal/vertical price-or-time line — live preview and already-committed alike —
        // gets its value tagged on the axis, exactly like the chart's own last-price badge. That's
        // how every real trading platform marks a drawn level, and it's the whole point of drawing
        // one: knowing the number, not just seeing the line. Axis rects sit outside `layout.plot`,
        // so these are drawn against the outer, unclipped context — the same split
        // `BaseLayerRenderer.drawPhases` uses between its plot content and its own axes.
        for drawing in drawings where !drawing.isHidden {
            drawAxisTag(for: drawing, in: &context)
        }
        if let previewDrawing {
            drawAxisTag(for: previewDrawing, in: &context)
        }
    }

    private func draw(_ drawing: Drawing, selected: Bool, in context: inout GraphicsContext) {
        guard let points = DrawingScreenMapping.screenPoints(for: drawing, in: frame) else { return }
        let plot = frame.layout.plot
        let color = Color(drawing.style.color)
        let strokeStyle = StrokeStyle(
            lineWidth: CGFloat(drawing.style.lineWidth),
            // `.map(CGFloat.init)` is ambiguous here — `CGFloat` has several initializers overloads
            // and an unapplied `CGFloat.init` reference doesn't pin down which one — so this spells
            // out the `Double -> CGFloat` conversion explicitly instead.
            dash: drawing.style.dash?.map { CGFloat($0) } ?? []
        )

        switch drawing.kind {
        case .horizontalLine:
            stroke(from: CGPoint(x: plot.minX, y: points[0].y), to: CGPoint(x: plot.maxX, y: points[0].y), color: color, style: strokeStyle, in: &context)

        case .verticalLine:
            stroke(from: CGPoint(x: points[0].x, y: plot.minY), to: CGPoint(x: points[0].x, y: plot.maxY), color: color, style: strokeStyle, in: &context)

        case .textNote:
            let text = context.resolve(Text(drawing.text?.isEmpty == false ? drawing.text! : "Note").font(.caption).foregroundStyle(color))
            context.draw(text, at: points[0], anchor: .bottomLeading)

        case .trendLine:
            stroke(from: points[0], to: points[1], color: color, style: strokeStyle, in: &context)

        case .horizontalRay:
            // Anchor 1 is the fixed point the ray extends from; which side anchor 2 fell on when
            // the drawing was made decides the direction — see `DrawingScreenMapping.distance`,
            // which hit-tests against exactly the same segment this draws.
            let y = points[0].y
            let goesRight = points[1].x >= points[0].x
            let endX = goesRight ? plot.maxX : plot.minX
            stroke(from: CGPoint(x: points[0].x, y: y), to: CGPoint(x: endX, y: y), color: color, style: strokeStyle, in: &context)

        case .ray:
            let far = DrawingScreenMapping.extendedFarPoint(from: points[0], through: points[1], plot: plot)
            stroke(from: points[0], to: far, color: color, style: strokeStyle, in: &context)

        case .rectangle:
            let rect = CGRect(
                x: min(points[0].x, points[1].x),
                y: min(points[0].y, points[1].y),
                width: abs(points[1].x - points[0].x),
                height: abs(points[1].y - points[0].y)
            )
            let path = Path(rect)
            if let fillOpacity = drawing.style.fillOpacity {
                context.fill(path, with: .color(color.opacity(fillOpacity)))
            }
            context.stroke(path, with: .color(color), style: strokeStyle)

        case .fibonacciRetracement:
            drawFibonacciLevels(points[0], points[1], color: color, lineWidth: CGFloat(drawing.style.lineWidth), in: &context)

        case .parallelChannel:
            guard points.count == 3 else { return }
            drawChannel(points, color: color, fillOpacity: drawing.style.fillOpacity ?? 0.08, style: strokeStyle, in: &context)

        case .fibonacciExtension:
            guard points.count == 3, drawing.anchors.count == 3 else { return }
            drawFibonacciExtension(drawing.anchors, points, color: color, lineWidth: CGFloat(drawing.style.lineWidth), in: &context)

        case .riskReward:
            guard points.count == 3, drawing.anchors.count == 3 else { return }
            drawRiskReward(drawing.anchors, points, in: &context)
        }

        if selected {
            for point in points {
                context.stroke(Path(ellipseIn: handleRect(at: point, radius: 6)), with: .color(color), lineWidth: 2)
                context.fill(Path(ellipseIn: handleRect(at: point, radius: 3)), with: .color(.white))
            }
        }
    }

    /// Tags a horizontal line/ray's price, or a vertical line's time, on the price or time axis —
    /// the anchor a trader actually cares about, read straight from the model rather than re-derived
    /// from screen geometry. Anchor 1 is always the fixed point for these kinds (design note §1.2),
    /// so it's the right one to label even while a second anchor elsewhere is still being dragged.
    private func drawAxisTag(for drawing: Drawing, in context: inout GraphicsContext) {
        guard let anchor = drawing.anchors.first,
              let points = DrawingScreenMapping.screenPoints(for: drawing, in: frame), let point = points.first
        else { return }
        let background = Color(drawing.style.color)
        let foreground = contrastingForeground(for: drawing.style.color)
        switch drawing.kind {
        case .horizontalLine, .horizontalRay:
            ChartText.drawPriceTag(
                ChartFormat.price(anchor.price, digits: frame.priceFractionDigits),
                y: point.y,
                in: frame.layout.priceAxis,
                background: background,
                foreground: foreground,
                context: &context
            )
        case .verticalLine:
            ChartText.drawTimeTag(
                ChartFormat.detailedTime(anchor.time, interval: frame.interval),
                x: point.x,
                in: frame.layout.timeAxis,
                background: background,
                foreground: foreground,
                context: &context
            )
        case .trendLine, .ray, .rectangle, .fibonacciRetracement, .textNote,
             .parallelChannel, .fibonacciExtension, .riskReward:
            break
        }
    }

    /// A floating "how far did this move" readout — signed price delta and percent change — next to
    /// a two-anchor tool's live second anchor while it's still being dragged. The number a trader
    /// drawing a trend line or measuring a range actually wants before releasing their finger.
    private func drawMeasurementBadge(for drawing: Drawing, in context: inout GraphicsContext) {
        guard drawing.kind.anchorCount == 2, drawing.anchors.count == 2,
              let points = DrawingScreenMapping.screenPoints(for: drawing, in: frame), points.count == 2
        else { return }
        let start = drawing.anchors[0]
        let end = drawing.anchors[1]
        let deltaPrice = end.price - start.price
        let percent = start.price != 0 ? deltaPrice / start.price : 0
        let digits = frame.priceFractionDigits
        let text = context.resolve(
            Text("\(ChartFormat.signedPrice(deltaPrice, digits: digits))  (\(ChartFormat.percent(percent)))")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        )
        // Both bounds spelled out as explicit `CGFloat`s — an untyped `240` alongside a bare
        // `.greatestFiniteMagnitude` left the compiler unable to settle on one floating-point type
        // for both at once ("ambiguous use of 'greatestFiniteMagnitude'"), unlike `ChartText`'s own
        // use of the same pattern, where `rect.width` is already typed `CGFloat`.
        let size = text.measure(in: CGSize(width: CGFloat(240), height: CGFloat.greatestFiniteMagnitude))
        let horizontalPadding: CGFloat = 6
        let badgeColor: Color = deltaPrice >= 0 ? .green : .red
        // Offset up and to the right of the live anchor so the badge doesn't sit under the finger.
        let origin = CGPoint(x: points[1].x + 10, y: points[1].y - size.height - 16)
        let rect = CGRect(x: origin.x, y: origin.y, width: size.width + horizontalPadding * 2, height: size.height + 6)
        context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(badgeColor.opacity(0.92)))
        context.draw(text, at: CGPoint(x: rect.minX + horizontalPadding, y: rect.midY), anchor: .leading)
    }

    /// Perceptually-cheap luminance check (ITU-R BT.601 weights) to keep an axis tag's text legible
    /// against whatever color a trader picked for the line — the same problem `LastPriceBadge`
    /// doesn't have to solve, since its background is always the chart's own fixed up/down palette.
    private func contrastingForeground(for color: DrawingColor) -> Color {
        let luminance = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
        return luminance > 0.6 ? .black : .white
    }

    // Standard retracement levels — 0 and 1 mark the two anchors themselves, the rest are the
    // levels every charting package this competes with draws for this tool.
    private static let fibonacciLevels: [Double] = [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1]

    private func drawFibonacciLevels(_ a: CGPoint, _ b: CGPoint, color: Color, lineWidth: CGFloat, in context: inout GraphicsContext) {
        let minX = min(a.x, b.x)
        let maxX = max(a.x, b.x)
        for level in Self.fibonacciLevels {
            let y = a.y + (b.y - a.y) * CGFloat(level)
            stroke(from: CGPoint(x: minX, y: y), to: CGPoint(x: maxX, y: y), color: color.opacity(0.85), style: StrokeStyle(lineWidth: max(1, lineWidth * 0.75)), in: &context)
            let label = context.resolve(Text(String(format: "%.1f%%", level * 100)).font(.caption2).foregroundStyle(color))
            context.draw(label, at: CGPoint(x: minX + 4, y: y - 8), anchor: .topLeading)
        }
    }

    private func drawChannel(_ points: [CGPoint], color: Color, fillOpacity: Double, style: StrokeStyle, in context: inout GraphicsContext) {
        let (first, second) = DrawingScreenMapping.channelLines(points)
        var band = Path()
        band.move(to: first.0)
        band.addLine(to: first.1)
        band.addLine(to: second.1)
        band.addLine(to: second.0)
        band.closeSubpath()
        context.fill(band, with: .color(color.opacity(fillOpacity)))
        stroke(from: first.0, to: first.1, color: color, style: style, in: &context)
        stroke(from: second.0, to: second.1, color: color, style: style, in: &context)
        // Dashed midline.
        stroke(
            from: CGPoint(x: (first.0.x + second.0.x) / 2, y: (first.0.y + second.0.y) / 2),
            to: CGPoint(x: (first.1.x + second.1.x) / 2, y: (first.1.y + second.1.y) / 2),
            color: color.opacity(0.6),
            style: StrokeStyle(lineWidth: max(1, style.lineWidth * 0.75), dash: [5, 4]),
            in: &context
        )
    }

    /// Projection levels from C of the A→B move, drawn from C's x to the right of the plot, with
    /// the level's price as the label.
    private func drawFibonacciExtension(
        _ anchors: [DrawingAnchor], _ points: [CGPoint], color: Color, lineWidth: CGFloat, in context: inout GraphicsContext
    ) {
        let a = anchors[0].price, b = anchors[1].price, c = anchors[2].price
        let startX = points[2].x
        let endX = max(frame.layout.plot.maxX, startX + 40)
        for level in FibonacciExtension.levels {
            let price = FibonacciExtension.price(level: level, a: a, b: b, c: c)
            let y = frame.y(forPrice: price)
            stroke(from: CGPoint(x: startX, y: y), to: CGPoint(x: endX, y: y), color: color.opacity(0.85),
                   style: StrokeStyle(lineWidth: max(1, lineWidth * 0.75)), in: &context)
            let text = "\(String(format: "%.3g", level))  \(ChartFormat.price(price, digits: frame.priceFractionDigits))"
            let label = context.resolve(Text(text).font(.caption2.monospacedDigit()).foregroundStyle(color))
            context.draw(label, at: CGPoint(x: startX + 4, y: y - 8), anchor: .topLeading)
        }
        // Guide from A to B to C so it's clear what's being projected.
        var guide = Path()
        guide.move(to: points[0]); guide.addLine(to: points[1]); guide.addLine(to: points[2])
        context.stroke(guide, with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    /// The planned trade: green between entry and target, red between entry and stop, the ratio on
    /// the entry line, and the price move and (with an account size set) share of each end.
    private func drawRiskReward(_ anchors: [DrawingAnchor], _ points: [CGPoint], in context: inout GraphicsContext) {
        let plan = PositionPlan(entry: anchors[0].price, target: anchors[1].price, stop: anchors[2].price)
        let box = DrawingScreenMapping.riskRewardBox(points)
        let entryY = points[0].y
        let targetY = points[1].y
        let stopY = points[2].y
        let reward = Path(CGRect(x: box.minX, y: min(entryY, targetY), width: box.width, height: abs(targetY - entryY)))
        let risk = Path(CGRect(x: box.minX, y: min(entryY, stopY), width: box.width, height: abs(stopY - entryY)))
        let good = Color.green
        let bad = Color.red
        context.fill(reward, with: .color(good.opacity(plan.isValid ? 0.18 : 0.06)))
        context.fill(risk, with: .color(bad.opacity(plan.isValid ? 0.18 : 0.30)))
        stroke(from: CGPoint(x: box.minX, y: entryY), to: CGPoint(x: box.maxX, y: entryY), color: .primary.opacity(0.8),
               style: StrokeStyle(lineWidth: 1.5), in: &context)
        stroke(from: CGPoint(x: box.minX, y: targetY), to: CGPoint(x: box.maxX, y: targetY), color: good,
               style: StrokeStyle(lineWidth: 1.5), in: &context)
        stroke(from: CGPoint(x: box.minX, y: stopY), to: CGPoint(x: box.maxX, y: stopY), color: bad,
               style: StrokeStyle(lineWidth: 1.5), in: &context)

        let digits = frame.priceFractionDigits
        func percent(_ price: Double) -> String { plan.percentMove(to: price).map { " (\(ChartFormat.percent($0)))" } ?? "" }
        let ratioText: String
        if let ratio = plan.rewardToRisk {
            ratioText = "R:R \(String(format: "%.2f", ratio))  \(plan.side == .long ? "Long" : "Short")"
        } else {
            ratioText = "Stop is on the wrong side of the entry"
        }
        let entryLabel = context.resolve(Text(ratioText).font(.caption2.weight(.semibold)).foregroundStyle(.primary))
        context.draw(entryLabel, at: CGPoint(x: box.minX + 4, y: entryY - 2), anchor: .bottomLeading)
        let targetLabel = context.resolve(
            Text("Target \(ChartFormat.price(plan.target, digits: digits))\(percent(plan.target))")
                .font(.caption2.monospacedDigit()).foregroundStyle(good)
        )
        context.draw(targetLabel, at: CGPoint(x: box.minX + 4, y: targetY + (targetY < entryY ? 2 : -2)),
                     anchor: targetY < entryY ? .topLeading : .bottomLeading)
        let stopLabel = context.resolve(
            Text("Stop \(ChartFormat.price(plan.stop, digits: digits))\(percent(plan.stop))")
                .font(.caption2.monospacedDigit()).foregroundStyle(bad)
        )
        context.draw(stopLabel, at: CGPoint(x: box.minX + 4, y: stopY + (stopY > entryY ? -2 : 2)),
                     anchor: stopY > entryY ? .bottomLeading : .topLeading)
    }

    private func stroke(from: CGPoint, to: CGPoint, color: Color, style: StrokeStyle, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), style: style)
    }

    private func handleRect(at point: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
    }
}
#endif
