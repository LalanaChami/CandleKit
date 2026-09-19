import Foundation

/// The pure math hit testing and anchor placement need — separated from any rendering or gesture
/// code, like `IndicatorMath`, so it's directly unit-testable and reusable by an app that wants to
/// build its own drawing tool UI on top of `CandleKitCore` without CandleKit's SwiftUI layer.
public enum DrawingGeometry {

    // MARK: - Anchor ↔ screen position

    /// Maps a drawing anchor's `Date` onto the chart's fractional, index-based x position (see
    /// `Viewport`'s own doc comment for why the axis is index-based rather than timestamp-based).
    /// `nil` only when `candles` is empty — there is no position to map onto.
    ///
    /// An exact match (the common case — most anchors get created on a candle, especially with
    /// snapping, see the design note §7) returns that candle's own center, `index + 0.5`. When no
    /// candle has that exact time — one pruned from a shortened history window, or a freehand
    /// anchor placed between two candles — this interpolates linearly between the two bracketing
    /// candles by elapsed time, and extrapolates past either end using the spacing of the nearest
    /// pair of candles, so an anchor slightly before the first loaded candle or after the last one
    /// still lands at a sensible position instead of clamping to the edge.
    public static func position(for time: Date, in candles: [Candle]) -> Double? {
        guard !candles.isEmpty else { return nil }
        guard candles.count > 1 else { return 0.5 }

        // Reuses `Candle`'s own binary search rather than a second copy of the same logic.
        let low = candles.lowerBoundIndex(for: time)

        if low == 0 {
            let first = candles[0].time.timeIntervalSince1970
            let second = candles[1].time.timeIntervalSince1970
            let step = second - first
            guard step > 0 else { return 0.5 }
            let elapsed = time.timeIntervalSince1970 - first
            return 0.5 + elapsed / step
        }
        if low == candles.count {
            let lastIndex = candles.count - 1
            let last = candles[lastIndex].time.timeIntervalSince1970
            let secondLast = candles[lastIndex - 1].time.timeIntervalSince1970
            let step = last - secondLast
            guard step > 0 else { return Double(lastIndex) + 0.5 }
            let elapsed = time.timeIntervalSince1970 - last
            return Double(lastIndex) + 0.5 + elapsed / step
        }

        let after = candles[low]
        if after.time == time {
            return Double(low) + 0.5
        }
        let before = candles[low - 1]
        let beforeTime = before.time.timeIntervalSince1970
        let afterTime = after.time.timeIntervalSince1970
        let span = afterTime - beforeTime
        guard span > 0 else { return Double(low - 1) + 0.5 }
        let fraction = (time.timeIntervalSince1970 - beforeTime) / span
        return Double(low - 1) + 0.5 + fraction
    }

    // MARK: - Hit testing

    /// A plain 2D point. `CandleKitCore` has no `CGPoint` — Linux has no CoreGraphics — so this is
    /// the portable stand-in every function below uses; the UI layer converts to and from `CGPoint`
    /// at the boundary. Coordinates are in whatever space the caller is testing in (typically plot
    /// points), not tied to price or time.
    public struct Point: Hashable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Shortest distance from `point` to the segment `a`–`b`. The basis for hit-testing a bounded
    /// drawing (a trend line's actual extent, a rectangle's edges) — the caller applies its own
    /// touch tolerance on top of this (see the design note §3's 22pt minimum).
    public static func distance(from point: Point, toSegment a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, a) }
        let t = clamp01(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared)
        return distance(point, Point(x: a.x + t * dx, y: a.y + t * dy))
    }

    /// Shortest distance from `point` to the *infinite* line through `a` and `b` — for a
    /// `.horizontalLine`/`.verticalLine`, which extend past their stored anchors in both directions.
    public static func distance(from point: Point, toLineThrough a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, a) }
        let t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        return distance(point, Point(x: a.x + t * dx, y: a.y + t * dy))
    }

    /// Shortest distance from `point` to a ray starting at `origin` and passing through `through` —
    /// for `.horizontalRay`/`.ray`, which extend past `through` but stop at `origin`. Like
    /// `distance(from:toLineThrough:_:)`, but clamped so a point "behind" the origin measures to the
    /// origin itself rather than to the infinite backward extension of the line.
    public static func distance(from point: Point, toRayFrom origin: Point, through: Point) -> Double {
        let dx = through.x - origin.x
        let dy = through.y - origin.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, origin) }
        let t = max(0, ((point.x - origin.x) * dx + (point.y - origin.y) * dy) / lengthSquared)
        return distance(point, Point(x: origin.x + t * dx, y: origin.y + t * dy))
    }

    /// Shortest distance from `point` to the boundary (not the interior) of the axis-aligned
    /// rectangle with corners `a` and `b` — a `.rectangle` is hit-tested against its edges, not
    /// treated as a filled tap target, so tapping its middle doesn't select it while tapping its
    /// clearly-visible outline does.
    public static func distanceToRectangleEdge(from point: Point, corner a: Point, _ b: Point) -> Double {
        let minX = min(a.x, b.x), maxX = max(a.x, b.x)
        let minY = min(a.y, b.y), maxY = max(a.y, b.y)
        let corners = [
            Point(x: minX, y: minY), Point(x: maxX, y: minY),
            Point(x: maxX, y: maxY), Point(x: minX, y: maxY),
        ]
        var closest = Double.infinity
        for index in corners.indices {
            let next = corners[(index + 1) % corners.count]
            closest = min(closest, distance(from: point, toSegment: corners[index], next))
        }
        return closest
    }

    private static func distance(_ a: Point, _ b: Point) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
