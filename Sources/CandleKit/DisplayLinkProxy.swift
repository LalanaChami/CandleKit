#if os(iOS)
import QuartzCore

/// Forwards `CADisplayLink` frame callbacks to a closure without letting the display link keep
/// anything alive.
///
/// `CADisplayLink` retains its `target` strongly for as long as it's added to a run loop. Passing
/// `self` directly as the target — as a first pass at this code once did — creates a one-way retain
/// cycle: the object can never deinit while its own animation is running, and if the object is the
/// only thing that would ever call `invalidate()`, it never gets the chance. That leaves a chart
/// (and everything it retains — candle data, caches, callbacks) alive forever if the view holding it
/// disappears mid-animation.
///
/// Using this proxy as the target instead means the display link only ever retains this small
/// object. The owner is captured weakly, so it can deinit normally even while the link is still
/// running; the callback then simply becomes a no-op. Callers should still call `invalidate()`
/// deterministically when they can (see `stopAnimations()` and `dismantleUIView`) — this proxy is
/// the safety net for the cases that slip through, not a replacement for that.
@MainActor
final class DisplayLinkProxy: NSObject {
    private let onFrame: (CADisplayLink) -> Void

    init(onFrame: @escaping (CADisplayLink) -> Void) {
        self.onFrame = onFrame
        super.init()
    }

    @objc func step(_ link: CADisplayLink) {
        onFrame(link)
    }

    /// Creates and activates a display link that calls `onFrame` on `owner` for as long as `owner`
    /// is alive and the link hasn't been invalidated. `owner` is captured weakly.
    static func scheduled<Owner: AnyObject>(
        target owner: Owner,
        preferredRange: CAFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120),
        onFrame: @escaping (Owner, CADisplayLink) -> Void
    ) -> CADisplayLink {
        let proxy = DisplayLinkProxy { [weak owner] link in
            guard let owner else { return }
            onFrame(owner, link)
        }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.step(_:)))
        link.preferredFrameRateRange = preferredRange
        link.add(to: .main, forMode: .common)
        return link
    }
}
#endif
