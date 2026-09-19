#if os(iOS)
import SwiftUI

/// Bridges `DrawingGeometry`'s portable, UI-framework-free math to `ChartFrame`'s real `CGPoint`
/// screen space. Plays the same role `CandleGeometry` plays for candle bodies: one shared place to
/// convert a drawing's anchors to pixels, used by both the renderer and hit testing, so the two can
/// never independently compute (and silently disagree about) where a drawing actually sits — the
/// exact bug the crosshair's dimming overlay had before `CandleGeometry` was introduced.
enum DrawingScreenMapping {
    /// Each of `drawing.anchors`, converted to a point in the plot's own coordinate space (the same
    /// space `frame.centerX(ofCandle:)`/`frame.y(forPrice:)` already use). `nil` only when `frame`
    /// has no candles to look the anchors' times up against.
    static func screenPoints(for drawing: Drawing, in frame: ChartFrame) -> [CGPoint]? {
        var points: [CGPoint] = []
        points.reserveCapacity(drawing.anchors.count)
        for anchor in drawing.anchors {
            guard let position = DrawingGeometry.position(for: anchor.time, in: frame.candles) else { return nil }
            let x = frame.layout.plot.minX + CGFloat(frame.viewport.x(atPosition: position, width: frame.plotWidth))
            let y = frame.y(forPrice: anchor.price)
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }

    /// Converts a raw touch point — already in the gesture view's coordinates, which is exactly the
    /// plot rect (see `ChartGestureView`) — into a `DrawingAnchor`, snapping to the nearest visible
    /// candle's open/high/low/close within `snapRadius` points when `snapping` is on (design note
    /// §7). `snapped` tells the caller whether a snap actually happened, so it can fire the same
    /// light haptic tap a new snap target gets elsewhere in this codebase.
    static func anchor(
        at point: CGPoint,
        in frame: ChartFrame,
        snapping: Bool,
        snapRadius: Double
    ) -> (anchor: DrawingAnchor, snapped: Bool)? {
        let localX = Double(point.x - frame.layout.plot.minX)
        let position = frame.viewport.position(atX: localX, width: frame.plotWidth)
        guard let time = DrawingGeometry.time(forPosition: position, in: frame.candles) else { return nil }
        let price = frame.priceScale.invert(Double(point.y))

        guard snapping else { return (DrawingAnchor(time: time, price: price), false) }

        var best: (time: Date, price: Double, distanceSquared: Double)?
        let radiusSquared = snapRadius * snapRadius
        for index in frame.visible {
            let candle = frame.candles[index]
            let x = Double(frame.centerX(ofCandle: index))
            for value in [candle.open, candle.high, candle.low, candle.close] {
                let y = Double(frame.y(forPrice: value))
                let dx = x - Double(point.x)
                let dy = y - Double(point.y)
                let distanceSquared = dx * dx + dy * dy
                guard distanceSquared <= radiusSquared else { continue }
                if best == nil || distanceSquared < best!.distanceSquared {
                    best = (candle.time, value, distanceSquared)
                }
            }
        }
        if let best {
            return (DrawingAnchor(time: best.time, price: best.price), true)
        }
        return (DrawingAnchor(time: time, price: price), false)
    }

    /// Where a `.ray`/`.horizontalRay` should extend *to*, given its two screen anchors — far enough
    /// past `plot`'s bounds that the layer's own clip to the plot rect cuts it off cleanly, rather
    /// than computing the exact edge intersection. `origin` extends through (not from) `through`.
    static func extendedFarPoint(from origin: CGPoint, through: CGPoint, plot: CGRect) -> CGPoint {
        let dx = through.x - origin.x
        let dy = through.y - origin.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return through }
        // Four times the plot's own diagonal is comfortably past any edge at any zoom level.
        let scale = (plot.width + plot.height) * 4 / length
        return CGPoint(x: origin.x + dx * scale, y: origin.y + dy * scale)
    }

    /// Shortest distance from a touch to a drawing's visible stroke, dispatching to the
    /// `DrawingGeometry` primitive that matches what `DrawingsLayerRenderer` actually draws for that
    /// `kind` — kept in lockstep with the renderer for the same reason `screenPoints` is shared
    /// rather than recomputed, so a drawing is always exactly as easy to tap as it looks.
    static func distance(to drawing: Drawing, screenPoints points: [CGPoint], from touch: CGPoint, plot: CGRect) -> Double {
        func pt(_ p: CGPoint) -> DrawingGeometry.Point { DrawingGeometry.Point(x: Double(p.x), y: Double(p.y)) }
        let target = pt(touch)

        switch drawing.kind {
        case .horizontalLine:
            return DrawingGeometry.distance(
                from: target,
                toLineThrough: pt(CGPoint(x: plot.minX, y: points[0].y)),
                pt(CGPoint(x: plot.maxX, y: points[0].y))
            )
        case .verticalLine:
            return DrawingGeometry.distance(
                from: target,
                toLineThrough: pt(CGPoint(x: points[0].x, y: plot.minY)),
                pt(CGPoint(x: points[0].x, y: plot.maxY))
            )
        case .textNote:
            return DrawingGeometry.distance(from: target, toSegment: pt(points[0]), pt(points[0]))
        case .trendLine:
            return DrawingGeometry.distance(from: target, toSegment: pt(points[0]), pt(points[1]))
        case .horizontalRay:
            // Anchor 1 is the fixed point the ray starts from; anchor 2 only tells the renderer
            // which direction (left or right) the ray extends in — see `DrawingsLayerRenderer`.
            let y = points[0].y
            let goesRight = points[1].x >= points[0].x
            let endX = goesRight ? plot.maxX : plot.minX
            return DrawingGeometry.distance(from: target, toSegment: pt(CGPoint(x: points[0].x, y: y)), pt(CGPoint(x: endX, y: y)))
        case .ray:
            return DrawingGeometry.distance(from: target, toRayFrom: pt(points[0]), through: pt(points[1]))
        case .rectangle, .fibonacciRetracement:
            // A Fibonacci retracement is hit-tested against its bounding box, same as a rectangle —
            // precise enough to select the whole tool without needing per-level hit testing.
            return DrawingGeometry.distanceToRectangleEdge(from: target, corner: pt(points[0]), pt(points[1]))
        }
    }
}
#endif
