#if os(iOS)
import SwiftUI
import UIKit

/// A transparent UIKit view over the plot that owns all chart gestures.
///
/// Real UIKit recognizers are used instead of SwiftUI gestures because they give simultaneous pan and pinch,
/// release velocity for momentum, and precise control over when a pan may begin. Their locations are already
/// in plot coordinates because this view covers exactly the plot.
struct ChartGestureView: UIViewRepresentable {
    let state: CandleChartState
    /// `nil` for a chart with no `.drawings(...)`/`.drawingTool(...)` attached — every drawing-tools
    /// branch below is then skipped and every recognizer behaves exactly as it did before this file
    /// knew drawing tools existed.
    var drawingController: DrawingController? = nil

    func makeCoordinator() -> ChartGestureCoordinator {
        ChartGestureCoordinator(state: state)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        context.coordinator.install(on: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.state = state
        context.coordinator.drawingController = drawingController
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ChartGestureCoordinator) {
        coordinator.stopAllAnimations()
    }
}

@MainActor
final class ChartGestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    var state: CandleChartState
    /// Set (from `nil`) only when the app attaches `.drawings(...)`/`.drawingTool(...)` to the
    /// chart. See the drawing-tools branches in `handlePan`, `handleTap`, and the delegate methods
    /// below — every one of them is a no-op path when this is `nil`, so an ordinary chart's gesture
    /// behavior is untouched by any of this.
    var drawingController: DrawingController?
    /// Decided once, at the start of a pan gesture, and held for its duration — see
    /// `DrawingController.shouldClaimPrimaryGesture`'s own doc comment for why this must not be
    /// renegotiated mid-drag.
    private var isDrawingGesture = false

    private let panRecognizer: UIPanGestureRecognizer
    private let pinchRecognizer: UIPinchGestureRecognizer
    private let longPressRecognizer: UILongPressGestureRecognizer
    private let doubleTapRecognizer: UITapGestureRecognizer
    private let singleTapRecognizer: UITapGestureRecognizer

    // MARK: Momentum

    private var momentumDisplayLink: CADisplayLink?
    private var momentumVelocity: Double = 0
    private var lastMomentumTimestamp: CFTimeInterval = 0
    /// The view whose width momentum needs for rubber-band resistance at the edges. Weak because
    /// the coordinator must not be the reason the view sticks around.
    private weak var hostView: UIView?

    /// Matches `UIScrollView.DecelerationRate.normal`: velocity retained per millisecond.
    private static let decelerationPerMillisecond = 0.998
    private static let minimumMomentumVelocity = 80.0
    private static let stopVelocity = 10.0

    // MARK: Rubber-band spring-back

    private var springDisplayLink: CADisplayLink?
    private var springTargetRightEdge: Double = 0
    private var springEdgeVelocity: Double = 0
    private var lastSpringTimestamp: CFTimeInterval = 0
    private var isOverscrolling = false

    /// Critically-damped spring for snap-back: stiffness=300, damping=2√300≈34.6 → use 35.
    private static let springStiffness = 300.0
    private static let springDamping = 35.0

    // MARK: Haptic generators
    //
    // Haptics here are deliberately sparse: one light tap when the crosshair engages (the ongoing
    // per-candle ticks as it moves come from `CrosshairLayer`'s `.sensoryFeedback`, not from here),
    // one rigid tap when a pinch hits its zoom limit, and one medium tap when double-tap resets the
    // view. Momentum reaching the data edge no longer has its own haptic — it now visibly bounces
    // (see `stepMomentum`), and the motion itself is the feedback. There are no accompanying sound
    // effects: `AudioServicesPlaySystemSound` for routine scrolling and zooming is not how iOS charts
    // (or UIScrollView itself) normally behave, and the specific sound IDs a prior version of this
    // file used are undocumented UIKit internals, not public API.

    private lazy var impactLight  = UIImpactFeedbackGenerator(style: .light)
    private lazy var impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private lazy var impactRigid  = UIImpactFeedbackGenerator(style: .rigid)

    // MARK: Zoom-limit detection

    private var didFireZoomLimitHaptic = false

    init(state: CandleChartState) {
        self.state = state
        panRecognizer = UIPanGestureRecognizer()
        pinchRecognizer = UIPinchGestureRecognizer()
        longPressRecognizer = UILongPressGestureRecognizer()
        doubleTapRecognizer = UITapGestureRecognizer()
        singleTapRecognizer = UITapGestureRecognizer()
        super.init()
    }

    func install(on view: UIView) {
        hostView = view
        panRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        pinchRecognizer.addTarget(self, action: #selector(handlePinch(_:)))
        longPressRecognizer.addTarget(self, action: #selector(handleLongPress(_:)))
        // 0.25s: quick enough to feel responsive, but past the dwell time an ordinary slow drag
        // spends before UIPanGestureRecognizer's own movement threshold is satisfied. A shorter
        // value here made deliberate, careful scrolling occasionally get claimed by long-press
        // instead of pan, since holding still briefly is easy to do by accident at the start of a drag.
        longPressRecognizer.minimumPressDuration = 0.25
        doubleTapRecognizer.addTarget(self, action: #selector(handleDoubleTap(_:)))
        doubleTapRecognizer.numberOfTapsRequired = 2
        // Selecting a drawing, or placing a single-anchor tool, is a tap distinct from the
        // double-tap-to-reset that already exists — must lose to it, the standard UIKit way to let
        // a single tap and a double tap coexist on the same view without the single tap firing first.
        singleTapRecognizer.addTarget(self, action: #selector(handleSingleTap(_:)))
        singleTapRecognizer.numberOfTapsRequired = 1
        singleTapRecognizer.require(toFail: doubleTapRecognizer)

        let recognizers: [UIGestureRecognizer] = [panRecognizer, pinchRecognizer, longPressRecognizer, doubleTapRecognizer, singleTapRecognizer]
        for recognizer in recognizers {
            recognizer.delegate = self
            view.addGestureRecognizer(recognizer)
        }
    }

    // MARK: Handlers

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: recognizer.view)

        if recognizer.state == .began {
            isDrawingGesture = drawingController?.shouldClaimPrimaryGesture(at: location) ?? false
        }

        if isDrawingGesture {
            switch recognizer.state {
            case .began:
                // A trader's finger just started laying down a line — a light tap marks the start
                // of a placement gesture, the same cue `handleLongPress` gives when the crosshair
                // engages. Selecting or dragging an existing drawing (no active tool) stays quiet.
                if drawingController?.activeTool != nil {
                    impactLight.impactOccurred()
                }
                drawingController?.beginPrimaryGesture(at: location)
            case .changed:
                drawingController?.updatePrimaryGesture(at: location)
                if drawingController?.didSnapLastUpdate == true {
                    impactLight.impactOccurred()
                }
            default:
                // A medium tap confirms the drawing actually landed — the same begin/commit weight
                // difference `handleLongPress`/`handleDoubleTap` already use elsewhere in this file.
                let wasCreating = drawingController?.activeTool != nil
                drawingController?.endPrimaryGesture(at: location)
                if wasCreating {
                    impactMedium.impactOccurred()
                }
                isDrawingGesture = false
            }
            return
        }

        switch recognizer.state {
        case .began:
            stopAllAnimations()          // sets isScrolling = false via stopMomentum/stopSpring
            state.cancelAnimation()
            state.isScrolling = true     // re-arm: panning has begun
            isOverscrolling = false
            applyTranslation(of: recognizer)
        case .changed:
            applyTranslation(of: recognizer)
        case .ended:
            if isOverscrolling {
                startSpringBack()        // keeps isScrolling = true until spring settles
            } else {
                let vel = Double(recognizer.velocity(in: recognizer.view).x)
                if abs(vel) > Self.minimumMomentumVelocity {
                    startMomentum(velocity: vel)  // keeps isScrolling = true until momentum stops
                } else {
                    state.isScrolling = false      // short flick, no momentum
                }
            }
            isOverscrolling = false
        default:
            isOverscrolling = false
            state.isScrolling = false
            state.snapToClamped()
        }
    }

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        if drawingController?.handleTap(at: recognizer.location(in: recognizer.view)) == true {
            impactMedium.impactOccurred()
        }
    }

    private func applyTranslation(of recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: recognizer.view)
        recognizer.setTranslation(.zero, in: recognizer.view)
        let plotWidth = Double(recognizer.view?.bounds.width ?? 375)
        isOverscrolling = state.panForDrag(byPoints: Double(translation.x), plotWidth: plotWidth)
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            stopAllAnimations()
            state.cancelAnimation()
            impactRigid.prepare()
            didFireZoomLimitHaptic = false
        case .changed:
            guard recognizer.numberOfTouches >= 2 else { return }
            let anchor = recognizer.location(in: recognizer.view)
            state.zoom(by: Double(recognizer.scale), anchorX: Double(anchor.x))
            recognizer.scale = 1

            // After zoom(), spacing is clamped to ZoomLimits. If it sits at a boundary, the limit was hit.
            if !didFireZoomLimitHaptic {
                let spacing = state.viewport.spacing
                if spacing <= state.zoomLimits.minimumSpacing + 1e-9 || spacing >= state.zoomLimits.maximumSpacing - 1e-9 {
                    impactRigid.impactOccurred()
                    didFireZoomLimitHaptic = true
                }
            }
        default:
            break
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: recognizer.view)
        switch recognizer.state {
        case .began:
            stopAllAnimations()
            impactLight.impactOccurred()
            state.updateCrosshair(x: location.x, y: location.y)
        case .changed:
            state.updateCrosshair(x: location.x, y: location.y)
        default:
            // No haptic on release: `CrosshairLayer`'s `.sensoryFeedback(.selection)` already ticked
            // for every candle the finger crossed, and iOS's own long-press interactions (reordering,
            // context menus) don't add a second cue just for lifting the finger.
            state.clearCrosshair()
        }
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        stopAllAnimations()
        impactMedium.impactOccurred()
        state.animatedResetZoom()
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Neither has anything useful to do mid-draw (design note §2): a pinch can't sensibly
        // resize a tool that isn't placed yet, and the crosshair has nothing to focus while one
        // finger is busy drawing.
        if gestureRecognizer === pinchRecognizer || gestureRecognizer === longPressRecognizer {
            return drawingController?.activeTool == nil
        }
        guard gestureRecognizer === panRecognizer else { return true }
        let location = panRecognizer.location(in: panRecognizer.view)
        if let drawingController, drawingController.shouldClaimPrimaryGesture(at: location) {
            // A tool is active, or an existing drawing sits under the touch: any direction counts,
            // unlike the horizontal-only heuristic below, since a trend line or rectangle is drawn
            // in whatever direction the person actually drags.
            return true
        }
        // Only claim mostly-horizontal drags, so a chart inside a vertical ScrollView still lets the page scroll.
        let velocity = panRecognizer.velocity(in: panRecognizer.view)
        return abs(velocity.x) >= abs(velocity.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer === panRecognizer && otherGestureRecognizer === pinchRecognizer)
            || (gestureRecognizer === pinchRecognizer && otherGestureRecognizer === panRecognizer)
    }

    // MARK: Momentum

    private func startMomentum(velocity: Double) {
        momentumVelocity = velocity
        lastMomentumTimestamp = CACurrentMediaTime()
        // ProMotion devices also need CADisableMinimumFrameDurationOnPhone in the app's Info.plist.
        momentumDisplayLink = DisplayLinkProxy.scheduled(target: self) { coordinator, link in
            coordinator.stepMomentum(link)
        }
    }

    private func stepMomentum(_ link: CADisplayLink) {
        // targetTimestamp = when this frame appears on screen; computing physics to that moment
        // removes the one-frame display lag that link.timestamp-based calculations carry.
        let now = link.targetTimestamp
        let elapsed = min(max(now - lastMomentumTimestamp, 0), 1.0 / 30)
        lastMomentumTimestamp = now
        momentumVelocity *= pow(Self.decelerationPerMillisecond, elapsed * 1_000)

        if UIAccessibility.isReduceMotionEnabled {
            // Direct-manipulation momentum itself isn't a Reduce Motion concern — UIScrollView
            // keeps flinging regardless of the setting — but the bounce below is an unforced
            // extra motion, so skip straight to the old hard stop at the boundary.
            let hitEdge = state.pan(byPoints: momentumVelocity * elapsed)
            if hitEdge || abs(momentumVelocity) < Self.stopVelocity {
                stopMomentum()
            }
            return
        }

        // Let the fling carry slightly past the edge, with the same resistance a manual drag gets,
        // then hand off to the spring the moment it does. A flick that reached the newest or oldest
        // candle used to stop dead here — every other place this file touches the data edge gives
        // some kind of "soft wall" (release-in-overscroll, the pinch zoom limit); this was the one
        // spot that didn't, and it read as a glitch rather than a boundary.
        let plotWidth = Double(hostView?.bounds.width ?? 375)
        let overscrolling = state.panForDrag(byPoints: momentumVelocity * elapsed, plotWidth: plotWidth)
        if overscrolling {
            stopMomentum()
            startSpringBack()
            return
        }
        if abs(momentumVelocity) < Self.stopVelocity {
            stopMomentum()
        }
    }

    private func stopMomentum() {
        momentumDisplayLink?.invalidate()
        momentumDisplayLink = nil
        momentumVelocity = 0
        state.isScrolling = false
    }

    // MARK: Rubber-band spring-back

    private func startSpringBack() {
        stopSpring()

        // Reduce Motion: land on the boundary immediately rather than overshoot-and-settle.
        if UIAccessibility.isReduceMotionEnabled {
            state.snapToClamped()
            return
        }

        state.isRubberBanding = true  // keep makeFrame from clamping during spring-back
        springTargetRightEdge = state.clampedRightEdge()
        springEdgeVelocity = 0
        lastSpringTimestamp = CACurrentMediaTime()
        springDisplayLink = DisplayLinkProxy.scheduled(target: self) { coordinator, link in
            coordinator.stepSpringBack(link)
        }
    }

    private func stepSpringBack(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let elapsed = min(max(now - lastSpringTimestamp, 0), 1.0 / 30)
        lastSpringTimestamp = now

        let displacement = state.viewport.rightEdge - springTargetRightEdge
        springEdgeVelocity += (-Self.springStiffness * displacement - Self.springDamping * springEdgeVelocity) * elapsed
        state.setRightEdgeDirect(state.viewport.rightEdge + springEdgeVelocity * elapsed)

        let displacementPts = abs(displacement * state.viewport.spacing)
        let velocityPts = abs(springEdgeVelocity * state.viewport.spacing)
        if displacementPts < 0.5 && velocityPts < 5 {
            state.snapToClamped()
            stopSpring()
        }
    }

    private func stopSpring() {
        springDisplayLink?.invalidate()
        springDisplayLink = nil
        springEdgeVelocity = 0
        state.isScrolling = false
    }

    // MARK: Combined stop

    /// Stops momentum scrolling and any rubber-band spring-back. Must be called when any new gesture begins.
    func stopAllAnimations() {
        stopMomentum()
        stopSpring()
    }

}
#endif
