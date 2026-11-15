import Foundation

/// Decides when a fast-changing value may be published again. Pure: the caller supplies the time
/// (any steadily increasing clock, in seconds).
public struct PublishThrottle: Sendable, Equatable {
    /// Minimum seconds between two publishes. Negative or non-finite values are treated as 0.
    public let interval: TimeInterval
    /// When the last publish was recorded; `nil` before the first.
    public private(set) var lastPublish: TimeInterval?

    public init(interval: TimeInterval) {
        self.interval = interval.isFinite && interval > 0 ? interval : 0
    }

    /// `0` when a publish is allowed at `now`; otherwise the seconds still to wait.
    public func delay(at now: TimeInterval) -> TimeInterval {
        guard let last = lastPublish, now >= last else { return 0 }
        return max(0, interval - (now - last))
    }

    /// Records a publish at `now`.
    public mutating func markPublished(at now: TimeInterval) {
        lastPublish = now
    }
}
