import Foundation
import Testing
@testable import CandleKitCore

// Expected values come from a short independent Python script that carries a float remainder the
// same way (earned = remainder + dt * rate; reveal floor(earned)), not from this implementation.
@Suite("Replay")
struct ReplayTests {
    @Test func wholeCandlesAreRevealedAndTheRestIsCarried() {
        var clock = ReplayClock()
        // dt 0.5 s at 3/s = 1.5 -> reveal 1, carry 0.5; again 1.5+0.5 = 2.0 -> reveal 2, carry 0.
        #expect(clock.advance(by: 0.5, candlesPerSecond: 3) == 1)
        #expect(abs(clock.remainder - 0.5) < 1e-12)
        #expect(clock.advance(by: 0.5, candlesPerSecond: 3) == 2)
        #expect(abs(clock.remainder - 0.0) < 1e-12)
    }

    @Test func slowSpeedsAccumulateAcrossTicks() {
        var clock = ReplayClock()
        // 0.5 candles per second, 30 Hz ticks: first candle after 2 s (60 ticks of 1/30 s).
        var revealed = 0
        for _ in 0..<59 { revealed += clock.advance(by: 1.0 / 30.0, candlesPerSecond: 0.5) }
        #expect(revealed == 0)
        revealed += clock.advance(by: 1.0 / 30.0, candlesPerSecond: 0.5)
        #expect(revealed == 1)
    }

    @Test func changingSpeedKeepsTheRemainder() {
        var clock = ReplayClock()
        #expect(clock.advance(by: 0.3, candlesPerSecond: 2) == 0)   // 0.6
        #expect(clock.advance(by: 0.3, candlesPerSecond: 4) == 1)   // 0.6 + 1.2 = 1.8 -> 1, carry 0.8
        #expect(abs(clock.remainder - 0.8) < 1e-12)
    }

    @Test func invalidInputsAddNothing() {
        var clock = ReplayClock()
        #expect(clock.advance(by: -1, candlesPerSecond: 5) == 0)
        #expect(clock.advance(by: 1, candlesPerSecond: 0) == 0)
        #expect(clock.advance(by: .nan, candlesPerSecond: 5) == 0)
        #expect(clock.advance(by: 1, candlesPerSecond: .infinity) == 0)
        #expect(clock.remainder == 0)
    }

    @Test func hugeElapsedTimeDoesNotOverflow() {
        var clock = ReplayClock()
        #expect(clock.advance(by: 1e30, candlesPerSecond: 10) == 1_000_000_000)
    }

    @Test func resetClearsTheRemainder() {
        var clock = ReplayClock()
        _ = clock.advance(by: 0.4, candlesPerSecond: 3)
        clock.reset()
        #expect(clock.remainder == 0)
    }

    @Test func visibleCountIsClamped() {
        #expect(ReplayMath.visibleCount(position: 50, count: 100) == 50)
        #expect(ReplayMath.visibleCount(position: 0, count: 100) == 2)
        #expect(ReplayMath.visibleCount(position: -5, count: 100) == 2)
        #expect(ReplayMath.visibleCount(position: 500, count: 100) == 100)
        #expect(ReplayMath.visibleCount(position: 1, count: 1) == 1)
        #expect(ReplayMath.visibleCount(position: 10, count: 0) == 0)
        #expect(ReplayMath.visibleCount(position: 0, count: 100, minimum: 10) == 10)
    }
}
