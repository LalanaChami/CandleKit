import Foundation
import Testing
@testable import CandleKitCore

private func close(_ a: Double?, _ b: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) < 1e-9
}

@Suite("Order lines")
struct ChartOrderLineTests {
    @Test func snapsToTick() {
        #expect(close(OrderLineMath.snapped(100.26, tick: 0.5), 100.5))
        #expect(close(OrderLineMath.snapped(100.24, tick: 0.5), 100.0))
        #expect(close(OrderLineMath.snapped(0.1234, tick: 0.01), 0.12))
    }

    @Test func snapBadTick() {
        #expect(OrderLineMath.snapped(100.26, tick: nil) == 100.26)
        #expect(OrderLineMath.snapped(100.26, tick: 0) == 100.26)
        #expect(OrderLineMath.snapped(100.26, tick: -1) == 100.26)
        #expect(OrderLineMath.snapped(100.26, tick: .nan) == 100.26)
    }

    @Test func percentDistance() {
        #expect(close(OrderLineMath.percentDistance(of: 101, from: 100), 0.01))
        #expect(close(OrderLineMath.percentDistance(of: 95, from: 100), -0.05))
        #expect(OrderLineMath.percentDistance(of: 101, from: 0) == nil)
        #expect(OrderLineMath.percentDistance(of: .nan, from: 100) == nil)
        #expect(OrderLineMath.percentDistance(of: 101, from: .nan) == nil)
    }

    @Test func lineDefaults() {
        let line = ChartOrderLine(id: "o1", price: 100, kind: .buy, label: "Buy 1")
        #expect(line.isDraggable == false)
        #expect(line.id == "o1")
    }
}
