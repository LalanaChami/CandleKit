import Foundation

/// Deterministic fake market data for previews, demos and tests.
public enum CandleSampleData {
    /// A random-walk series. The same seed always produces the same candles.
    ///
    /// Prices are rounded to two decimals, so `startPrice` must be at least 1.
    public static func randomWalk(
        count: Int,
        start: Date = Date(timeIntervalSince1970: 1_767_225_600), // 2026-01-01 00:00 UTC
        interval: TimeInterval = 3_600,
        startPrice: Double = 100,
        volatility: Double = 0.01,
        seed: UInt64 = 42
    ) -> [Candle] {
        precondition(startPrice >= 1, "randomWalk rounds to cents; use a startPrice of at least 1")
        var generator = SplitMix64(seed: seed)
        var candles: [Candle] = []
        candles.reserveCapacity(max(0, count))
        var previousClose = rounded(startPrice)

        for index in 0..<max(0, count) {
            let open = previousClose
            let close = max(1, rounded(open * (1 + generator.nextGaussian() * volatility)))
            let upperWick = abs(generator.nextGaussian()) * volatility * 0.5 * open
            let lowerWick = abs(generator.nextGaussian()) * volatility * 0.5 * open
            let high = rounded(max(open, close) + upperWick)
            let low = max(0.01, rounded(min(open, close) - lowerWick))
            let volume = (1_000 + generator.nextDouble() * 9_000).rounded()

            candles.append(Candle(
                time: start.addingTimeInterval(Double(index) * interval),
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume
            ))
            previousClose = close
        }
        return candles
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

/// Small, fast, seedable generator (SplitMix64).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func nextDouble() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// Standard normal via Box–Muller.
    mutating func nextGaussian() -> Double {
        let u1 = max(nextDouble(), .leastNonzeroMagnitude)
        let u2 = nextDouble()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
