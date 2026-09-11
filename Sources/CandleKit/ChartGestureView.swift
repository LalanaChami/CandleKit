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
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ChartGestureCoordinator) {
        coordinator.stopAllAnimations()
    }
}

@MainActor
final class ChartGestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    var state: CandleChartState

    private let panRecognizer: UIPanGestureRecognizer
    private let pinchRecognizer: UIPinchGestureRecognizer
    private let longPressRecognizer: UILongPressGestureRecognizer
    private let doubleTapRecognizer: UITapGestureRecognizer

    // MARK: Momentum

    private var momentumDisplayLink: CADisplayLink?
    private var momentumVelocity: Double = 0
    private var lastMomentumTimestamp: CFTimeInterval = 0
    private var firedEdgeHaptic = false

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

    private lazy var impactLight  = UIImpactFeedbackGenerator(style: .light)
    private lazy var impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private lazy var impactRigid  = UIImpactFeedbackGenerator(style: .rigid)
    private lazy var impactSoft   = UIImpactFeedbackGenerator(style: .soft)

    // MARK: Zoom-limit detection

    private var didFireZoomLimitHaptic = false

    init(state: CandleChartState) {
        self.state = state
        panRecognizer = UIPanGestureRecognizer()
        pinchRecognizer = UIPinchGestureRecognizer()
        longPressRecognizer = UILongPressGestureRecognizer()
        doubleTapRecognizer = UITapGestureRecognizer()
        super.init()
    }

    func install(on view: UIView) {
        panRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        pinchRecognizer.addTarget(self, action: #selector(handlePinch(_:)))
        longPressRecognizer.addTarget(self, action: #selector(handleLongPress(_:)))
        longPressRecognizer.minimumPressDuration = 0.15
        doubleTapRecognizer.addTarget(self, action: #selector(handleDoubleTap(_:)))
        doubleTapRecognizer.numberOfTapsRequired = 2

        let recognizers: [UIGestureRecognizer] = [panRecognizer, pinchRecognizer, longPressRecognizer, doubleTapRecognizer]
        for recognizer in recognizers {
            recognizer.delegate = self
            view.addGestureRecognizer(recognizer)
        }
    }

    // MARK: Handlers

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            stopAllAnimations()          // sets isScrolling = false via stopMomentum/stopSpring
            state.cancelAnimation()
            state.isScrolling = true     // re-arm: panning has begun
            impactLight.prepare()
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
            impactMedium.impactOccurred()
            state.updateCrosshair(x: location.x, y: location.y)
        case .changed:
            state.updateCrosshair(x: location.x, y: location.y)
        default:
            impactSoft.impactOccurred()
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
        guard gestureRecognizer === panRecognizer else { return true }
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
        firedEdgeHaptic = false
        lastMomentumTimestamp = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(stepMomentum(_:)))
        // ProMotion devices also need CADisableMinimumFrameDurationOnPhone in the app's Info.plist.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        momentumDisplayLink = link
    }

    @objc private func stepMomentum(_ link: CADisplayLink) {
        // targetTimestamp = when this frame appears on screen; computing physics to that moment
        // removes the one-frame display lag that link.timestamp-based calculations carry.
        let now = link.targetTimestamp
        let elapsed = min(max(now - lastMomentumTimestamp, 0), 1.0 / 30)
        lastMomentumTimestamp = now
        momentumVelocity *= pow(Self.decelerationPerMillisecond, elapsed * 1_000)
        let hitEdge = state.pan(byPoints: momentumVelocity * elapsed)
        if hitEdge && !firedEdgeHaptic {
            impactLight.impactOccurred()
            firedEdgeHaptic = true
        }
        if hitEdge || abs(momentumVelocity) < Self.stopVelocity {
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
        state.isRubberBanding = true  // keep makeFrame from clamping during spring-back
        springTargetRightEdge = state.clampedRightEdge()
        springEdgeVelocity = 0
        lastSpringTimestamp = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(stepSpringBack(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        springDisplayLink = link
    }

    @objc private func stepSpringBack(_ link: CADisplayLink) {
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
