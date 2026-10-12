import Foundation
import Testing
@testable import CandleKitCore

@Suite("Position plan and three-anchor drawings")
struct PositionPlanTests {
    private func anchor(_ t: Double, _ price: Double) -> DrawingAnchor {
        DrawingAnchor(time: Date(timeIntervalSince1970: t), price: price)
    }

    @Test func longPlanHasTwoToOneRatio() {
        let plan = PositionPlan(entry: 100, target: 110, stop: 95)
        #expect(plan.side == .long)
        #expect(plan.isValid)
        #expect(plan.riskPerUnit == 5)
        #expect(plan.rewardPerUnit == 10)
        #expect(plan.rewardToRisk == 2)
    }

    @Test func shortPlanMirrorsLong() {
        let plan = PositionPlan(entry: 100, target: 90, stop: 105)
        #expect(plan.side == .short)
        #expect(plan.isValid)
        #expect(plan.rewardToRisk == 2)
    }

    @Test func stopOnTheWrongSideIsInvalid() {
        #expect(!PositionPlan(entry: 100, target: 110, stop: 105).isValid)   // long with stop above entry
        #expect(!PositionPlan(entry: 100, target: 90, stop: 95).isValid)     // short with stop below
        #expect(PositionPlan(entry: 100, target: 110, stop: 105).rewardToRisk == nil)
        #expect(PositionPlan(entry: 100, target: 110, stop: 105).quantity(riskAmount: 100) == nil)
    }

    @Test func degeneratePlansAreInvalid() {
        #expect(!PositionPlan(entry: 100, target: 100, stop: 95).isValid)
        #expect(!PositionPlan(entry: 100, target: 110, stop: 100).isValid)
        #expect(!PositionPlan(entry: .nan, target: 110, stop: 95).isValid)
    }

    @Test func quantityRoundsDownToTheStep() {
        let plan = PositionPlan(entry: 100, target: 110, stop: 97)   // 3 per unit
        #expect(plan.quantity(riskAmount: 100) == 33)
        #expect(plan.quantity(riskAmount: 100, step: 0.5) == 33)
        #expect(plan.quantity(riskAmount: 100, step: 5) == 30)
        #expect(PositionPlan(entry: 100, target: 110, stop: 95).quantity(riskAmount: 100) == 20)
    }

    @Test func quantityFromAccountShare() {
        let plan = PositionPlan(entry: 100, target: 110, stop: 95)
        #expect(plan.quantity(accountSize: 10_000, riskFraction: 0.01) == 20)   // risks 100
        #expect(plan.quantity(accountSize: 0, riskFraction: 0.01) == nil)
        #expect(plan.quantity(riskAmount: -5) == nil)
    }

    @Test func percentMoveIsRelativeToTheEntry() {
        let plan = PositionPlan(entry: 100, target: 110, stop: 95)
        #expect(abs(plan.percentMove(to: 110)! - 0.10) < 1e-12)
        #expect(abs(plan.percentMove(to: 95)! + 0.05) < 1e-12)
        #expect(PositionPlan(entry: 0, target: 1, stop: -1).percentMove(to: 1) == nil)
    }

    @Test func fibonacciExtensionProjectsFromC() {
        let want: [Double] = [110, 122.36, 130, 135.44, 142.36, 150, 162.36]
        for (level, expected) in zip(FibonacciExtension.levels, want) {
            #expect(abs(FibonacciExtension.price(level: level, a: 100, b: 120, c: 110) - expected) < 1e-9)
        }
    }

    @Test func threeAnchorKindsGetADefaultThirdAnchor() {
        let placed = [anchor(0, 100), anchor(100, 120)]
        let fib = DrawingKind.fibonacciExtension.completingAnchors(placed)
        #expect(fib.count == 3)
        #expect(abs(fib[2].price - (120 - 0.618 * 20)) < 1e-9)
        #expect(fib[2].time == placed[1].time)

        let channel = DrawingKind.parallelChannel.completingAnchors(placed)
        #expect(channel.count == 3)
        #expect(abs(channel[2].price - 110) < 1e-9)   // a rising line: second line below the end point

        let falling = DrawingKind.parallelChannel.completingAnchors([anchor(0, 120), anchor(100, 100)])
        #expect(abs(falling[2].price - 110) < 1e-9)   // a falling line: second line above it

        let risk = DrawingKind.riskReward.completingAnchors([anchor(0, 100), anchor(100, 110)])
        #expect(risk.count == 3)
        #expect(risk[2].price == 95)
        #expect(PositionPlan(entry: risk[0].price, target: risk[1].price, stop: risk[2].price).rewardToRisk == 2)
    }

    @Test func shortRiskRewardDefaultsToAStopAboveTheEntry() {
        let risk = DrawingKind.riskReward.completingAnchors([anchor(0, 100), anchor(100, 90)])
        #expect(risk[2].price == 105)
    }

    @Test func otherKindsAreUnchanged() {
        let placed = [anchor(0, 100), anchor(100, 120)]
        #expect(DrawingKind.trendLine.completingAnchors(placed) == placed)
        #expect(DrawingKind.riskReward.completingAnchors([anchor(0, 1)]).count == 1)
    }

    @Test func newKindsRoundTripThroughCodable() throws {
        for kind in [DrawingKind.parallelChannel, .fibonacciExtension, .riskReward] {
            let drawing = Drawing(kind: kind, anchors: kind.completingAnchors([anchor(0, 100), anchor(100, 110)]))
            let data = try JSONEncoder().encode(drawing)
            let decoded = try JSONDecoder().decode(Drawing.self, from: data)
            #expect(decoded == drawing)
            #expect(decoded.hasValidAnchorCount)
        }
    }

    @Test func everyToolMapsToAKind() {
        #expect(DrawingTool.riskReward.kind == .riskReward)
        #expect(DrawingTool.parallelChannel.kind.anchorCount == 3)
        #expect(DrawingTool.allCases.count == DrawingKind.allCases.count)
    }
}
