import Foundation
import Testing
@testable import CandleKitCore

@Suite("Publish throttle")
struct PublishThrottleTests {
    @Test func firstPublishIsImmediate() {
        #expect(PublishThrottle(interval: 0.2).delay(at: 1000) == 0)
    }

    @Test func waitsOutTheInterval() {
        var throttle = PublishThrottle(interval: 0.2)
        throttle.markPublished(at: 10)
        #expect(abs(throttle.delay(at: 10.05) - 0.15) < 1e-9)
        #expect(throttle.delay(at: 10.2) < 1e-9)
        #expect(throttle.delay(at: 11) == 0)
    }

    @Test func clockGoingBackwards() {
        var throttle = PublishThrottle(interval: 0.2)
        throttle.markPublished(at: 10)
        #expect(throttle.delay(at: 9) == 0)
    }

    @Test func badIntervals() {
        #expect(PublishThrottle(interval: -1).interval == 0)
        #expect(PublishThrottle(interval: .nan).interval == 0)
    }
}
