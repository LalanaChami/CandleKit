import Foundation
import Testing
@testable import CandleKitCore

@Suite("Viewport navigation")
struct ViewportNavigationTests {
    private func candles(_ count: Int) -> [Candle] {
        (0..<count).map { i in
            Candle(time: Date(timeIntervalSince1970: Double(i) * 100), open: 1, high: 2, low: 0.5, close: 1.5)
        }
    }

    @Test func nearestIndexPicksTheClosestCandle() {
        let series = candles(5)   // times 0, 100, 200, 300, 400
        #expect(ViewportNavigation.nearestIndex(to: Date(timeIntervalSince1970: 140), in: series) == 1)
        #expect(ViewportNavigation.nearestIndex(to: Date(timeIntervalSince1970: 160), in: series) == 2)
        #expect(ViewportNavigation.nearestIndex(to: Date(timeIntervalSince1970: 200), in: series) == 2)
    }

    @Test func nearestIndexTiesGoToTheEarlierCandle() {
        #expect(ViewportNavigation.nearestIndex(to: Date(timeIntervalSince1970: 150), in: candles(5)) == 1)
    }

    @Test func nearestIndexClampsAtBothEnds() {
        let series = candles(5)
        #expect(ViewportNavigation.nearestIndex(to: Date(timeIntervalSince1970: -999), in: series) == 0)
        #expect(ViewportNavigation.nearestIndex(to: Date(timeIntervalSince1970: 99999), in: series) == 4)
        #expect(ViewportNavigation.nearestIndex(to: Date(), in: []) == nil)
    }

    @Test func rightEdgeForEachAlignment() {
        // width 200, spacing 10 -> 20 slots on screen.
        #expect(ViewportNavigation.rightEdge(forCandle: 50, alignment: .leading, width: 200, spacing: 10) == 70)
        #expect(ViewportNavigation.rightEdge(forCandle: 50, alignment: .center, width: 200, spacing: 10) == 60.5)
        #expect(ViewportNavigation.rightEdge(forCandle: 50, alignment: .trailing, width: 200, spacing: 10) == 51)
    }

    @Test func centeredCandleLandsInTheMiddleOfThePlot() {
        let edge = ViewportNavigation.rightEdge(forCandle: 50, alignment: .center, width: 200, spacing: 10)
        let viewport = Viewport(rightEdge: edge, spacing: 10)
        #expect(abs(viewport.centerX(ofCandle: 50, width: 200) - 100) < 1e-9)
    }

    @Test func leadingAndTrailingLandOnTheEdges() {
        let leading = Viewport(rightEdge: ViewportNavigation.rightEdge(forCandle: 50, alignment: .leading, width: 200, spacing: 10), spacing: 10)
        #expect(abs(leading.x(atPosition: 50, width: 200)) < 1e-9)
        let trailing = Viewport(rightEdge: ViewportNavigation.rightEdge(forCandle: 50, alignment: .trailing, width: 200, spacing: 10), spacing: 10)
        #expect(abs(trailing.x(atPosition: 51, width: 200) - 200) < 1e-9)
    }

    @Test func spacingForVisibleCountIsClamped() {
        let limits = ZoomLimits(minimumSpacing: 2, maximumSpacing: 40)
        #expect(ViewportNavigation.spacing(forVisibleCount: 20, width: 200, limits: limits) == 10)
        #expect(ViewportNavigation.spacing(forVisibleCount: 1, width: 200, limits: limits) == 40)
        #expect(ViewportNavigation.spacing(forVisibleCount: 1000, width: 200, limits: limits) == 2)
        #expect(ViewportNavigation.spacing(forVisibleCount: 0, width: 200, limits: limits) == 2)
    }

    @Test func visibleTimesCoverTheVisibleCandles() {
        let series = candles(100)
        let viewport = Viewport(rightEdge: 60, spacing: 10)   // 20 slots: positions 40...60
        let times = ViewportNavigation.visibleTimes(candles: series, viewport: viewport, width: 200)
        #expect(times?.lowerBound == series[40].time)
        #expect(times?.upperBound == series[59].time)
        #expect(ViewportNavigation.visibleTimes(candles: [], viewport: viewport, width: 200) == nil)
    }
}
