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
        }

        if selected {
            for point in points {
                context.stroke(Path(ellipseIn: handleRect(at: point, radius: 6)), with: .color(color), lineWidth: 2)
                context.fill(Path(ellipseIn: handleRect(at: point, radius: 3)), with: .color(.white))
            }
        }
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
