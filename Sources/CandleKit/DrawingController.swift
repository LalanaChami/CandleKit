#if os(iOS)
import Observation
import SwiftUI

/// Everything about drawing tools that is chart-local, transient UI state — never part of the app's
/// own `[Drawing]` model. Which tool is active lives in the app's `Binding<DrawingTool?>`; this owns
/// what sits *between* the two: an in-progress creation, the current selection, and dispatch for
/// `ChartGestureCoordinator`'s pan/tap handlers. See `docs/design/drawing-tools.md` §2–§3 for the
/// reasoning; `CandlestickChart` creates exactly one per chart instance (mirroring `CandleChartState`)
/// and keeps its bindings current every `body` pass via `attach`.
///
/// Not created at all unless the app calls `.drawings(...)` — see `CandlestickChart`'s modifiers —
/// so a chart that never touches drawing tools pays nothing beyond one small, otherwise-idle object.
@MainActor
@Observable
public final class DrawingController {
    // MARK: Observed — reading these is what makes `DrawingsLayer` redraw when they change.

    private(set) var revision = 0
    /// The currently selected drawing's id, or `nil`. Selection is chart-local UI state, never
    /// written into the persisted `Drawing` model (design note §3).
    public private(set) var selectedDrawingID: UUID?

    // MARK: Configuration

    /// Whether a placed or dragged anchor snaps to the nearest visible candle's open/high/low/close
    /// within `snapRadius` (design note §7). On by default, matching most charting apps.
    public var snappingEnabled = true
    /// Snap search radius, in points, around the raw touch location.
    public var snapRadius: Double = 14

    // MARK: Rebound every `CandlestickChart.body` pass — not itself part of the redraw trigger,
    // exactly like `CandleChartState`'s own `@ObservationIgnored` bookkeeping.

    @ObservationIgnored private var drawingsBinding: Binding<[Drawing]>?
    @ObservationIgnored private var toolBinding: Binding<DrawingTool?>?
    /// Mirrors `selectedDrawingID` outward so an app can build its own inspector or "Delete" button
    /// (design note §4/§5 — deletion itself is a plain operation on the app's own `drawings` array,
    /// needing no further CandleKit API beyond knowing what's selected). One-way, controller → app:
    /// every internal selection change is pushed here, but this isn't polled for external writes —
    /// see `CandlestickChart.selectedDrawing(_:)`.
    @ObservationIgnored private var selectedDrawingBinding: Binding<UUID?>?
    @ObservationIgnored private var frameProvider: () -> ChartFrame? = { nil }
    @ObservationIgnored private var defaultStyleProvider: () -> DrawingStyle = { DrawingStyle() }

    // MARK: Creation in progress (one anchor placed, tracking a live drag toward the next)

    @ObservationIgnored private var pendingTool: DrawingTool?
    @ObservationIgnored private var pendingAnchors: [DrawingAnchor] = []
    @ObservationIgnored private(set) var previewAnchor: DrawingAnchor?

    // MARK: Moving a selected drawing

    @ObservationIgnored private var dragStartAnchor: DrawingAnchor?
    @ObservationIgnored private var dragStartAnchors: [DrawingAnchor]?

    /// Set by `anchor(at:)` on every call; `ChartGestureCoordinator` reads this right after calling
    /// `updatePrimaryGesture` to decide whether to fire its existing light-impact haptic, the same
    /// generator it already uses elsewhere — see design note §7.
    private(set) var didSnapLastUpdate = false

    private static let hitTolerance: Double = 22

    public init() {}

    func attach(
        drawings: Binding<[Drawing]>?,
        tool: Binding<DrawingTool?>?,
        selection: Binding<UUID?>?,
        frame: @escaping () -> ChartFrame?,
        defaultStyle: @escaping () -> DrawingStyle
    ) {
        drawingsBinding = drawings
        toolBinding = tool
        selectedDrawingBinding = selection
        frameProvider = frame
        defaultStyleProvider = defaultStyle
    }

    public var activeTool: DrawingTool? { toolBinding?.wrappedValue }

    private var drawings: [Drawing] { drawingsBinding?.wrappedValue ?? [] }

    /// A synthetic, never-persisted `Drawing` built from the anchors placed so far plus the live
    /// drag point, purely for `DrawingsLayer` to render while a tool is mid-creation — including a
    /// single-anchor tool being dragged into position, where `pendingAnchors` is empty and
    /// `previewAnchor` alone is the whole drawing.
    var previewDrawing: Drawing? {
        guard let pendingTool, let previewAnchor else { return nil }
        return Drawing(kind: pendingTool.kind, anchors: pendingAnchors + [previewAnchor], style: defaultStyleProvider())
    }

    // MARK: Gesture entry points — called by `ChartGestureCoordinator`. `point` is always in the
    // gesture view's own coordinate space, which is exactly the plot rect (see `ChartGestureView`).

    /// Whether a one-finger drag starting at `point` should be claimed for drawing (create, or
    /// move/select in cursor mode) instead of panning the chart. `ChartGestureCoordinator` calls
    /// this once, at gesture-began time, and keeps that answer for the rest of the gesture — the
    /// mode is decided once, not renegotiated mid-drag (design note §2).
    func shouldClaimPrimaryGesture(at point: CGPoint) -> Bool {
        activeTool != nil || hitTest(point) != nil
    }

    func beginPrimaryGesture(at point: CGPoint) {
        didSnapLastUpdate = false
        if let tool = activeTool {
            // A trader positioning a horizontal price line, or a vertical time marker, wants to see
            // it follow their finger before committing to where it lands — the same drag-to-position
            // every real charting app gives a single-anchor tool, not just a blind tap (`handleTap`
            // remains for a quick, no-drag tap-to-place). `pendingAnchors` stays empty for these —
            // `previewAnchor` alone already is the whole drawing — while a multi-anchor tool fixes
            // its first anchor here and only drags the second.
            guard let anchor = anchor(at: point) else { return }
            pendingTool = tool
            pendingAnchors = tool.kind.anchorCount > 1 ? [anchor] : []
            previewAnchor = anchor
            bump()
            return
        }

        setSelection(hitTest(point))
        if let selectedDrawingID, let drawing = drawings.first(where: { $0.id == selectedDrawingID }),
           !drawing.isLocked, let anchor = anchor(at: point) {
            dragStartAnchor = anchor
            dragStartAnchors = drawing.anchors
        } else {
            dragStartAnchor = nil
            dragStartAnchors = nil
        }
        bump()
    }

    func updatePrimaryGesture(at point: CGPoint) {
        if pendingTool != nil {
            guard let anchor = anchor(at: point) else { return }
            previewAnchor = anchor
            bump()
            return
        }

        guard let selectedDrawingID,
              let index = drawings.firstIndex(where: { $0.id == selectedDrawingID }),
              !drawings[index].isLocked,
              let dragStartAnchor, let dragStartAnchors,
              let current = anchor(at: point)
        else { return }

        // The whole drawing translates by the same time/price delta — moving one anchor at a time
        // (a resize handle) is a fast follow, not part of this first pass; see the design note.
        let deltaTime = current.time.timeIntervalSince(dragStartAnchor.time)
        let deltaPrice = current.price - dragStartAnchor.price
        var moved = drawings[index]
        moved.anchors = dragStartAnchors.map {
            DrawingAnchor(time: $0.time.addingTimeInterval(deltaTime), price: $0.price + deltaPrice)
        }
        setDrawing(moved, at: index)
        bump()
    }

    func endPrimaryGesture(at point: CGPoint) {
        defer {
            dragStartAnchor = nil
            dragStartAnchors = nil
        }
        guard pendingTool != nil else { return }
        if let anchor = anchor(at: point) {
            previewAnchor = anchor
        }
        commitPending()
    }

    /// A plain tap, distinct from a drag. Commits a single-anchor tool, or toggles selection in
    /// cursor mode. `ChartGestureCoordinator` reports this from its own tap recognizer — a tap never
    /// also arrives through the primary-gesture (pan) entry points above. Returns whether a drawing
    /// was actually placed, so the coordinator knows when a placement haptic is warranted.
    @discardableResult
    func handleTap(at point: CGPoint) -> Bool {
        if let tool = activeTool {
            guard tool.kind.anchorCount == 1, let anchor = anchor(at: point) else { return false }
            append(Drawing(kind: tool.kind, anchors: [anchor], style: defaultStyleProvider()))
            return true
        }
        setSelection(hitTest(point))
        bump()
        return false
    }

    // MARK: Private

    private func setSelection(_ id: UUID?) {
        selectedDrawingID = id
        selectedDrawingBinding?.wrappedValue = id
    }

    private func commitPending() {
        defer {
            pendingTool = nil
            pendingAnchors = []
            previewAnchor = nil
            bump()
        }
        guard let pendingTool, let previewAnchor else { return }
        let anchors = Array((pendingAnchors + [previewAnchor]).prefix(pendingTool.kind.anchorCount))
        append(Drawing(kind: pendingTool.kind, anchors: anchors, style: defaultStyleProvider()))
    }

    private func append(_ drawing: Drawing) {
        guard var array = drawingsBinding?.wrappedValue else { return }
        array.append(drawing)
        drawingsBinding?.wrappedValue = array
    }

    private func setDrawing(_ drawing: Drawing, at index: Int) {
        guard var array = drawingsBinding?.wrappedValue, array.indices.contains(index) else { return }
        array[index] = drawing
        drawingsBinding?.wrappedValue = array
    }

    private func anchor(at point: CGPoint) -> DrawingAnchor? {
        guard let frame = frameProvider(),
              let result = DrawingScreenMapping.anchor(at: point, in: frame, snapping: snappingEnabled, snapRadius: snapRadius)
        else { return nil }
        didSnapLastUpdate = result.snapped
        return result.anchor
    }

    /// Topmost-wins hit test against every visible, non-hidden drawing (design note §3). Locked
    /// drawings are still hit-tested here — locking blocks move/resize/delete, not selection.
    private func hitTest(_ point: CGPoint) -> UUID? {
        guard let frame = frameProvider() else { return nil }
        for drawing in drawings.reversed() where !drawing.isHidden {
            guard let points = DrawingScreenMapping.screenPoints(for: drawing, in: frame) else { continue }
            let distance = DrawingScreenMapping.distance(to: drawing, screenPoints: points, from: point, plot: frame.layout.plot)
            if distance <= Self.hitTolerance { return drawing.id }
        }
        return nil
    }

    private func bump() { revision &+= 1 }
}
#endif
