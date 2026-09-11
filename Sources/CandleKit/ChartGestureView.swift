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
        coordinator.stopMomentum()
    }
}

@MainActor
final class ChartGestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    var state: CandleChartState

    private let panRecognizer: UIPanGestureRecognizer
    private let pinchRecognizer: UIPinchGestureRecognizer
    private let longPressRecognizer: UILongPressGestureRecognizer
    private let doubleTapRecognizer: UITapGestureRecognizer

    private var displayLink: CADisplayLink?
    private var momentumVelocity: Double = 0
    private var lastFrameTimestamp: CFTimeInterval = 0

    /// Matches `UIScrollView.DecelerationRate.normal`: velocity retained per millisecond.
    private static let decelerationPerMillisecond = 0.998
    private static let minimumMomentumVelocity = 80.0
    private static let stopVelocity = 10.0

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
        longPressRecognizer.minimumPressDuration = 0.25
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
            stopMomentum()
            applyTranslation(of: recognizer)
        case .changed:
            applyTranslation(of: recognizer)
        case .ended:
            startMomentum(velocity: Double(recognizer.velocity(in: recognizer.view).x))
        default:
            break
        }
    }

    private func applyTranslation(of recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: recognizer.view)
        recognizer.setTranslation(.zero, in: recognizer.view)
        state.pan(byPoints: Double(translation.x))
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            if recognizer.state == .began {
                stopMomentum()
            }
            // With one finger lifted the focal point jumps; wait until both are down again.
            guard recognizer.numberOfTouches >= 2 else { return }
            let anchor = recognizer.location(in: recognizer.view)
            state.zoom(by: Double(recognizer.scale), anchorX: Double(anchor.x))
            recognizer.scale = 1
        default:
            break
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: recognizer.view)
        switch recognizer.state {
        case .began:
            stopMomentum()
            state.updateCrosshair(x: location.x, y: location.y)
        case .changed:
            state.updateCrosshair(x: location.x, y: location.y)
        default:
            state.clearCrosshair()
        }
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        stopMomentum()
        state.resetZoom()
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
        stopMomentum()
        guard abs(velocity) > Self.minimumMomentumVelocity else { return }
        momentumVelocity = velocity
        lastFrameTimestamp = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(stepMomentum(_:)))
        // ProMotion devices also need CADisableMinimumFrameDurationOnPhone in the app's Info.plist.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func stepMomentum(_ link: CADisplayLink) {
        let now = link.timestamp
        let elapsed = min(max(now - lastFrameTimestamp, 0), 1.0 / 30)
        lastFrameTimestamp = now
        momentumVelocity *= pow(Self.decelerationPerMillisecond, elapsed * 1_000)
        let hitEdge = state.pan(byPoints: momentumVelocity * elapsed)
        if hitEdge || abs(momentumVelocity) < Self.stopVelocity {
            stopMomentum()
        }
    }

    /// Display links retain their target, so this must run when momentum ends or the view goes away.
    func stopMomentum() {
        displayLink?.invalidate()
        displayLink = nil
        momentumVelocity = 0
    }
}
#endif
