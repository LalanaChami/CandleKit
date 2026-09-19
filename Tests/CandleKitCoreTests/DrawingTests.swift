import Foundation
import Testing
@testable import CandleKitCore

@Suite("Drawing model")
struct DrawingModelTests {
    @Test func anchorCountsMatchKind() {
        #expect(DrawingKind.horizontalLine.anchorCount == 1)
        #expect(DrawingKind.verticalLine.anchorCount == 1)
        #expect(DrawingKind.textNote.anchorCount == 1)
        #expect(DrawingKind.horizontalRay.anchorCount == 2)
        #expect(DrawingKind.trendLine.anchorCount == 2)
        #expect(DrawingKind.ray.anchorCount == 2)
        #expect(DrawingKind.rectangle.anchorCount == 2)
        #expect(DrawingKind.fibonacciRetracement.anchorCount == 2)
    }

    @Test func everyToolMapsToAMatchingKind() {
        for tool in DrawingTool.allCases {
            #expect(tool.kind.rawValue == tool.rawValue)
        }
    }

    @Test func hasValidAnchorCount() {
        let good = Drawing(kind: .trendLine, anchors: [
            DrawingAnchor(time: .now, price: 1),
            DrawingAnchor(time: .now, price: 2),
        ])
        #expect(good.hasValidAnchorCount)

        let bad = Drawing(kind: .trendLine, anchors: [DrawingAnchor(time: .now, price: 1)])
        #expect(!bad.hasValidAnchorCount)
    }

    @Test func codableRoundTrip() throws {
        let original = Drawing(
            kind: .fibonacciRetracement,
            anchors: [
                DrawingAnchor(time: Date(timeIntervalSince1970: 1_700_000_000), price: 101.5),
                DrawingAnchor(time: Date(timeIntervalSince1970: 1_700_086_400), price: 98.25),
            ],
            style: DrawingStyle(color: DrawingColor(red: 0.9, green: 0.1, blue: 0.1, opacity: 0.8), lineWidth: 2, dash: [4, 2], fillOpacity: 0.15),
            isLocked: true,
            isHidden: false,
            text: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Drawing.self, from: data)
        #expect(decoded == original)
    }

    @Test func textNoteCarriesText() {
        let note = Drawing(kind: .textNote, anchors: [DrawingAnchor(time: .now, price: 50)], text: "Support")
        #expect(note.text == "Support")
        #expect(note.hasValidAnchorCount)
    }
}

@Suite("Drawing geometry")
struct DrawingGeometryTests {
    private func candle(_ epochSeconds: Double, _ close: Double = 100) -> Candle {
        Candle(time: Date(timeIntervalSince1970: epochSeconds), open: close, high: close, low: close, close: close)
    }

    // Ten hourly candles, one hour apart, starting at epoch 0.
    private var hourlyCandles: [Candle] {
        (0..<10).map { candle(Double($0) * 3600) }
    }

    @Test func positionIsNilForEmptyCandles() {
        #expect(DrawingGeometry.position(for: .now, in: []) == nil)
    }

    @Test func positionForSingleCandleIsAlwaysHalf() {
        let single = [candle(0)]
        #expect(DrawingGeometry.position(for: Date(timeIntervalSince1970: 999), in: single) == 0.5)
    }

    @Test func positionAtExactCandleTimeIsItsCenter() {
        let candles = hourlyCandles
        let position = DrawingGeometry.position(for: Date(timeIntervalSince1970: 3 * 3600), in: candles)
        #expect(position == 3.5)
    }

    @Test func positionBetweenCandlesInterpolates() {
        let candles = hourlyCandles
        // Halfway between candle 2 (7200s) and candle 3 (10800s).
        let position = DrawingGeometry.position(for: Date(timeIntervalSince1970: 9000), in: candles)
        #expect(position != nil)
        #expect(abs(position! - 3.0) < 1e-9) // (2 + 0.5) + 0.5 of the way to (3 + 0.5) = 3.0
    }

    @Test func positionBeforeFirstCandleExtrapolates() {
        let candles = hourlyCandles
        // One hour before the first candle — same spacing as the rest, so it should land exactly
        // one slot to the left of the first candle's center.
        let position = DrawingGeometry.position(for: Date(timeIntervalSince1970: -3600), in: candles)
        #expect(position != nil)
        #expect(abs(position! - (-0.5)) < 1e-9)
    }

    @Test func positionAfterLastCandleExtrapolates() {
        let candles = hourlyCandles
        let lastTime = 9.0 * 3600
        let position = DrawingGeometry.position(for: Date(timeIntervalSince1970: lastTime + 3600), in: candles)
        #expect(position != nil)
        #expect(abs(position! - 10.5) < 1e-9)
    }

    @Test func distanceToSegmentIsZeroOnTheSegment() {
        let a = DrawingGeometry.Point(x: 0, y: 0)
        let b = DrawingGeometry.Point(x: 10, y: 0)
        let onSegment = DrawingGeometry.Point(x: 5, y: 0)
        #expect(DrawingGeometry.distance(from: onSegment, toSegment: a, b) < 1e-9)
    }

    @Test func distanceToSegmentClampsPastTheEndpoints() {
        let a = DrawingGeometry.Point(x: 0, y: 0)
        let b = DrawingGeometry.Point(x: 10, y: 0)
        // Past `b`, perpendicular offset 3 — nearest point on the *segment* is `b` itself, so the
        // distance is to (10, 0), not to the infinite line's foot at (12, 0).
        let beyondB = DrawingGeometry.Point(x: 12, y: 3)
        let distance = DrawingGeometry.distance(from: beyondB, toSegment: a, b)
        #expect(abs(distance - (13.0).squareRoot()) < 1e-9) // sqrt(2^2 + 3^2)
    }

    @Test func distanceToInfiniteLineIgnoresEndpoints() {
        let a = DrawingGeometry.Point(x: 0, y: 0)
        let b = DrawingGeometry.Point(x: 10, y: 0)
        // Far past `b` on the same line — an infinite line has zero distance here, unlike a segment.
        let farPastB = DrawingGeometry.Point(x: 1000, y: 0)
        #expect(DrawingGeometry.distance(from: farPastB, toLineThrough: a, b) < 1e-9)
    }

    @Test func distanceToRayClampsBehindTheOrigin() {
        let origin = DrawingGeometry.Point(x: 0, y: 0)
        let through = DrawingGeometry.Point(x: 10, y: 0)
        // Behind the origin, perpendicular offset 4 — nearest point on the ray is the origin.
        let behind = DrawingGeometry.Point(x: -3, y: 4)
        let distance = DrawingGeometry.distance(from: behind, toRayFrom: origin, through: through)
        #expect(abs(distance - 5.0) < 1e-9) // sqrt(3^2 + 4^2)
    }

    @Test func distanceToRayAheadOfOriginMatchesTheLine() {
        let origin = DrawingGeometry.Point(x: 0, y: 0)
        let through = DrawingGeometry.Point(x: 10, y: 0)
        let ahead = DrawingGeometry.Point(x: 20, y: 3)
        #expect(abs(DrawingGeometry.distance(from: ahead, toRayFrom: origin, through: through) - 3.0) < 1e-9)
    }

    @Test func distanceToRectangleEdgeIsZeroOnTheBoundary() {
        let corner1 = DrawingGeometry.Point(x: 0, y: 0)
        let corner2 = DrawingGeometry.Point(x: 10, y: 10)
        let onEdge = DrawingGeometry.Point(x: 5, y: 0)
        #expect(DrawingGeometry.distanceToRectangleEdge(from: onEdge, corner: corner1, corner2) < 1e-9)
    }

    @Test func distanceToRectangleEdgeIsPositiveInTheInterior() {
        let corner1 = DrawingGeometry.Point(x: 0, y: 0)
        let corner2 = DrawingGeometry.Point(x: 10, y: 10)
        let center = DrawingGeometry.Point(x: 5, y: 5)
        // Center of a 10x10 square is 5 points from every edge.
        #expect(abs(DrawingGeometry.distanceToRectangleEdge(from: center, corner: corner1, corner2) - 5.0) < 1e-9)
    }

    @Test func distanceToRectangleEdgeWorksRegardlessOfCornerOrder() {
        // `corner1`/`corner2` need not be top-left/bottom-right — any two opposite corners work.
        let bottomRight = DrawingGeometry.Point(x: 10, y: 0)
        let topLeft = DrawingGeometry.Point(x: 0, y: 10)
        let onEdge = DrawingGeometry.Point(x: 0, y: 5)
        #expect(DrawingGeometry.distanceToRectangleEdge(from: onEdge, corner: bottomRight, topLeft) < 1e-9)
    }
}
