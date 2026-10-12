import Foundation

extension DrawingKind {
    /// The full anchor list for a drawing made by the usual one-drag gesture, which only places the
    /// first two anchors. Three-anchor kinds get a sensible third one that the person can then drag
    /// into place with the selection handles; other kinds return `placed` unchanged.
    ///
    /// - parallelChannel: the second line sits half the first line's price rise above (or below,
    ///   for a falling line) the end point, so the channel is visible straight away.
    /// - fibonacciExtension: C retraces 61.8% of the A→B move, the textbook starting point.
    /// - riskReward: the stop mirrors the target at half the distance, a 2:1 reward-to-risk plan.
    public func completingAnchors(_ placed: [DrawingAnchor]) -> [DrawingAnchor] {
        guard anchorCount == 3, placed.count == 2 else { return placed }
        let a = placed[0]
        let b = placed[1]
        switch self {
        case .parallelChannel:
            let rise = b.price - a.price
            let offset = rise != 0 ? abs(rise) * 0.5 : max(abs(b.price) * 0.01, .leastNormalMagnitude)
            return placed + [DrawingAnchor(time: b.time, price: b.price + (rise >= 0 ? -offset : offset))]
        case .fibonacciExtension:
            return placed + [DrawingAnchor(time: b.time, price: b.price - 0.618 * (b.price - a.price))]
        case .riskReward:
            // anchors: entry, target, stop
            return placed + [DrawingAnchor(time: a.time, price: a.price - (b.price - a.price) / 2)]
        default:
            return placed
        }
    }
}

/// Fibonacci projection levels for a three-anchor extension drawing.
public enum FibonacciExtension {
    /// The ratios drawn, as multiples of the A→B move projected from C.
    public static let levels: [Double] = [0, 0.618, 1, 1.272, 1.618, 2, 2.618]

    /// Price of `level` for anchors A, B, C: `C + level × (B − A)`.
    public static func price(level: Double, a: Double, b: Double, c: Double) -> Double {
        c + level * (b - a)
    }
}

/// Reward-to-risk arithmetic for a planned trade (the `.riskReward` drawing).
///
/// A plan is long when the target is above the entry and short when it is below. It is *valid*
/// only when the stop is on the opposite side of the entry from the target; an invalid plan has no
/// ratio or size, so a mis-dragged stop shows as a problem rather than a misleading number.
public struct PositionPlan: Sendable, Equatable {
    public enum Side: String, Sendable { case long, short }

    public var entry: Double
    public var target: Double
    public var stop: Double

    public init(entry: Double, target: Double, stop: Double) {
        self.entry = entry
        self.target = target
        self.stop = stop
    }

    public var side: Side { target >= entry ? .long : .short }

    public var isValid: Bool {
        guard entry.isFinite, target.isFinite, stop.isFinite, target != entry, stop != entry else { return false }
        return side == .long ? stop < entry : stop > entry
    }

    /// Price distance risked per unit, `nil` when the plan is invalid.
    public var riskPerUnit: Double? { isValid ? abs(entry - stop) : nil }
    /// Price distance gained per unit if the target is hit, `nil` when invalid.
    public var rewardPerUnit: Double? { isValid ? abs(target - entry) : nil }

    /// Reward divided by risk (2 means a 2:1 plan), `nil` when invalid.
    public var rewardToRisk: Double? {
        guard let risk = riskPerUnit, let reward = rewardPerUnit else { return nil }
        return reward / risk
    }

    /// Signed percent move from the entry to `price`, e.g. 0.05 for +5%. `nil` for a zero entry.
    public func percentMove(to price: Double) -> Double? {
        entry != 0 ? (price - entry) / entry : nil
    }

    /// How many units to trade so that hitting the stop loses `riskAmount`, rounded *down* to a
    /// multiple of `step` (use 1 for whole shares, 0.001 for a crypto lot). `nil` when the plan is
    /// invalid or the amount isn't positive. Ignores fees and slippage.
    public func quantity(riskAmount: Double, step: Double = 1) -> Double? {
        guard let risk = riskPerUnit, riskAmount > 0, riskAmount.isFinite, step > 0 else { return nil }
        let raw = riskAmount / risk
        // A small epsilon keeps 3.0000000000000004 from becoming 2.9999999999999996 after the divide.
        return (raw / step + 1e-9).rounded(.down) * step
    }

    /// Like `quantity(riskAmount:step:)`, with the amount given as a share of the account, e.g.
    /// `accountSize: 10_000, riskFraction: 0.01` risks 100.
    public func quantity(accountSize: Double, riskFraction: Double, step: Double = 1) -> Double? {
        guard accountSize > 0, riskFraction > 0 else { return nil }
        return quantity(riskAmount: accountSize * riskFraction, step: step)
    }
}
