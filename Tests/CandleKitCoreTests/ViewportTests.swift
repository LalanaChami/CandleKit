import Foundation
import Testing
@testable import CandleKitCore

@Suite("Viewport")
struct ViewportTests {
    @Test func positionAndXRoundTrip() {
        let viewport = Viewport(rightEdge: 100, spacing: 8)
        for x in [0.0, 12.5, 200, 390] {
            let position = viewport.position(atX: x, width: 390)
            #expect(abs(viewport.x(atPosition: position, width: 390) - x) < 1e-9)
        }
    }

    @Test func latestLeavesRightPadding() {
        let viewport = Viewport.latest(count: 100, spacing: 10, rightPadding: 3)
        // Candle 99 is centered at 99.5, which is 3.5 slots from the right edge at 103.
        #expect(viewport.centerX(ofCandle: 99, width: 400) == 365)
    }

    @Test func visibleRangeIncludesPartiallyVisibleCandles() {
        let viewport = Viewport(rightEdge: 50.5, spacing: 10) // left edge at 40.5
        #expect(viewport.visibleRange(width: 100, count: 1_000) == 40..<51)
    }

    @Test func visibleRangeIsClampedToData() {
        #expect(Viewport(rightEdge: 5, spacing: 10).visibleRange(width: 100, count: 3) == 0..<3)
        #expect(Viewport(rightEdge: -20, spacing: 10).visibleRange(width: 100, count: 3).isEmpty)
        #expect(Viewport(rightEdge: 5, spacing: 10).visibleRange(width: 100, count: 0).isEmpty)
    }

    @Test func draggingRightRevealsOlderCandles() {
        var viewport = Viewport(rightEdge: 100, spacing: 10)
        viewport.pan(byPoints: 50)
        #expect(viewport.rightEdge == 95)
    }

    @Test func zoomKeepsAnchorUnderFinger() {
        var viewport = Viewport(rightEdge: 100, spacing: 10)
        let width = 390.0
        let anchorX = 120.0
        let before = viewport.position(atX: anchorX, width: width)
        viewport.zoom(by: 1.7, anchorX: anchorX, width: width, limits: ZoomLimits(minimumSpacing: 1, maximumSpacing: 100))
        #expect(abs(viewport.spacing - 17) < 1e-9)
        #expect(abs(viewport.position(atX: anchorX, width: width) - before) < 1e-9)
    }

    @Test func zoomRespectsLimits() {
        var viewport = Viewport(rightEdge: 100, spacing: 10)
        viewport.zoom(by: 100, anchorX: 200, width: 390, limits: ZoomLimits())
        #expect(viewport.spacing == 48)
        viewport.zoom(by: 0.0001, anchorX: 200, width: 390, limits: ZoomLimits())
        #expect(viewport.spacing == 1.5)
    }

    @Test func clampKeepsHalfAScreenOfData() {
        let limits = ZoomLimits()
        // 400pt at 10pt spacing shows 40 candles; half a screen is 20.
        let farRight = Viewport(rightEdge: 1_000, spacing: 10).clamped(count: 100, width: 400, limits: limits)
        #expect(farRight.rightEdge == 120)
        let farLeft = Viewport(rightEdge: -50, spacing: 10).clamped(count: 100, width: 400, limits: limits)
        #expect(farLeft.rightEdge == 20)
        let invalid = Viewport(rightEdge: .nan, spacing: 10).clamped(count: 100, width: 400, limits: limits)
        #expect(invalid.rightEdge == 120)
    }

    @Test func candleIndexSnapsAndClamps() {
        let viewport = Viewport(rightEdge: 10, spacing: 10)
        #expect(viewport.candleIndex(atX: 95, width: 100, count: 10) == 9)
        #expect(viewport.candleIndex(atX: 5, width: 100, count: 10) == 0)
        #expect(viewport.candleIndex(atX: -500, width: 100, count: 10) == 0)
        #expect(viewport.candleIndex(atX: 5_000, width: 100, count: 10) == 9)
        #expect(viewport.candleIndex(atX: 5, width: 100, count: 0) == nil)
    }
}

@Suite("Series changes")
struct SeriesChangeTests {
    private func series(_ range: Range<Int>) -> [Candle] {
        range.map { index in
            Candle(time: Date(timeIntervalSince1970: Double(index) * 60), open: 1, high: 2, low: 0.5, close: 1.5)
        }
    }

    @Test func detectsEachKindOfChange() {
        let old = series(10..<20)
        let summary = SeriesSummary(old)
        #expect(SeriesChange.between(nil, old) == .initial)
        #expect(SeriesChange.between(summary, old) == .unchanged)
        #expect(SeriesChange.between(summary, series(10..<22)) == .extended(prepended: 0, appended: 2))
        #expect(SeriesChange.between(summary, series(5..<20)) == .extended(prepended: 5, appended: 0))
        #expect(SeriesChange.between(summary, series(0..<25)) == .extended(prepended: 10, appended: 5))
        #expect(SeriesChange.between(summary, series(30..<40)) == .replaced)
        #expect(SeriesChange.between(summary, series(12..<20)) == .replaced)
        #expect(SeriesChange.between(summary, []) == .replaced)
    }

    @Test func inPlaceUpdateOfLastCandleIsUnchanged() {
        let old = series(0..<10)
        var updated = old
        updated[9].close = 99
        #expect(SeriesChange.between(SeriesSummary(old), updated) == .unchanged)
    }

    @Test func appendScrollsOnlyWhenFollowingLatest() {
        var following = Viewport.latest(count: 100, spacing: 8, rightPadding: 3)
        following.apply(.extended(prepended: 0, appended: 1), previousCount: 100, newCount: 101, rightPadding: 3)
        #expect(following.rightEdge == 104)

        var browsingHistory = Viewport(rightEdge: 80, spacing: 8)
        browsingHistory.apply(.extended(prepended: 0, appended: 1), previousCount: 100, newCount: 101, rightPadding: 3)
        #expect(browsingHistory.rightEdge == 80)
    }

    @Test func prependKeepsSameCandlesOnScreen() {
        var viewport = Viewport(rightEdge: 80, spacing: 8)
        viewport.apply(.extended(prepended: 50, appended: 0), previousCount: 100, newCount: 150, rightPadding: 3)
        #expect(viewport.rightEdge == 130)
    }

    @Test func replacementJumpsToLatest() {
        var viewport = Viewport(rightEdge: 12, spacing: 8)
        viewport.apply(.replaced, previousCount: 100, newCount: 40, rightPadding: 3)
        #expect(viewport == Viewport(rightEdge: 43, spacing: 8))
    }

    @Test func lowerBoundFindsInsertionPoint() {
        let candles = series(0..<10)
        #expect(candles.lowerBoundIndex(for: Date(timeIntervalSince1970: 0)) == 0)
        #expect(candles.lowerBoundIndex(for: Date(timeIntervalSince1970: 150)) == 3)
        #expect(candles.lowerBoundIndex(for: Date(timeIntervalSince1970: 10_000)) == 10)
    }
}
