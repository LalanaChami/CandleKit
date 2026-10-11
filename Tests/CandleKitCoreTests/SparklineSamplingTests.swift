import Testing
@testable import CandleKitCore

// Expected index lists come from an independent Python one-liner: [i * (n - 1) // (k - 1) for i in range(k)].
@Suite("SparklineSampling")
struct SparklineSamplingTests {
    @Test func thinsEvenlyAndKeepsEnds() {
        #expect(SparklineSampling.indices(count: 10, maxPoints: 4) == [0, 3, 6, 9])
        #expect(SparklineSampling.indices(count: 7, maxPoints: 3) == [0, 3, 6])
        let long = SparklineSampling.indices(count: 100, maxPoints: 30)
        #expect(long.count == 30)
        #expect(long.first == 0)
        #expect(long.last == 99)
        #expect(Array(long.prefix(6)) == [0, 3, 6, 10, 13, 17])
    }

    @Test func justOverTheLimitStaysStrictlyIncreasing() {
        let picks = SparklineSampling.indices(count: 31, maxPoints: 30)
        #expect(picks.count == 30)
        #expect(Set(picks).count == 30)
        #expect(picks.suffix(2) == [28, 30])
    }

    @Test func shortInputIsReturnedWhole() {
        #expect(SparklineSampling.indices(count: 3, maxPoints: 5) == [0, 1, 2])
        #expect(SparklineSampling.indices(count: 5, maxPoints: 5) == [0, 1, 2, 3, 4])
    }

    @Test func degenerateInputs() {
        #expect(SparklineSampling.indices(count: 0, maxPoints: 5).isEmpty)
        #expect(SparklineSampling.indices(count: 5, maxPoints: 0).isEmpty)
        #expect(SparklineSampling.indices(count: 5, maxPoints: 1) == [4])
    }
}
