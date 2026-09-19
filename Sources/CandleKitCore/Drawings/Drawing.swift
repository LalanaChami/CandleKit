import Foundation

// The drawing-tools model — see `docs/design/drawing-tools.md` for the reasoning this file is a
// direct implementation of, especially §1.1 (why anchors are `(Date, price)`, never an index) and
// §1.2 (why this is `Codable` structs plus a `Binding`, not a result-builder API).
//
// Deliberately free of any UI framework, like the indicator model: pure Foundation, builds and
// tests on Linux. Color is `DrawingColor` (plain RGBA components), not `SwiftUI.Color`, for the
// same reason `IndicatorColorRole` exists instead of a `Color` on `IndicatorPlot`.

/// One point a drawing is anchored to, in the terms that survive history changes: a moment in time
/// and a price — never a candle index, which shifts when older history is prepended.
public struct DrawingAnchor: Codable, Hashable, Sendable {
    public var time: Date
    public var price: Double

    public init(time: Date, price: Double) {
        self.time = time
        self.price = price
    }
}

/// What a finished drawing *is*. Stable across releases the same way `IndicatorDescriptor`'s
/// identifier is — this is what a saved layout stores, so a case can be added but never renamed or
/// removed without a migration story.
public enum DrawingKind: String, Codable, Sendable, CaseIterable {
    case horizontalLine, horizontalRay, verticalLine, trendLine, ray, rectangle
    case fibonacciRetracement, textNote

    /// How many anchors a drawing of this kind needs. The renderer and hit-testing both use this to
    /// stay generic instead of switching on `DrawingKind` a second time.
    public var anchorCount: Int {
        switch self {
        case .horizontalLine, .verticalLine, .textNote: return 1
        case .horizontalRay, .trendLine, .ray, .rectangle, .fibonacciRetracement: return 2
        }
    }
}

/// What a person can pick from a drawing toolbar. Distinct from `DrawingKind` — which is what a
/// *finished* drawing is tagged as — so a future pseudo-tool with no matching persisted kind (an
/// eraser, a "select nothing, just pan" cursor made explicit rather than represented by `nil`) can
/// be added here without touching what `Drawing.kind` can be. Every current case maps 1:1 to a
/// `DrawingKind` of the same name; `DrawingController` (the still-to-come gesture-layer piece — see
/// the design note's §8 table) is what turns "this tool is active" into "here is a new `Drawing`."
public enum DrawingTool: String, Sendable, CaseIterable {
    case horizontalLine, horizontalRay, verticalLine, trendLine, ray, rectangle
    case fibonacciRetracement, textNote

    public var kind: DrawingKind {
        // `DrawingTool` and `DrawingKind` share raw values one-for-one today, so this can't fail —
        // spelled as a lookup rather than `DrawingKind(rawValue: rawValue)!` so it stays correct
        // (and keeps compiling, loudly, via the `switch`'s exhaustiveness check) if the two ever
        // diverge instead of silently force-unwrapping into a crash.
        switch self {
        case .horizontalLine: return .horizontalLine
        case .horizontalRay: return .horizontalRay
        case .verticalLine: return .verticalLine
        case .trendLine: return .trendLine
        case .ray: return .ray
        case .rectangle: return .rectangle
        case .fibonacciRetracement: return .fibonacciRetracement
        case .textNote: return .textNote
        }
    }
}

/// A plain RGBA color — `CandleKitCore` has no `SwiftUI.Color` (Linux has no SwiftUI), so this is
/// the portable, `Codable` stand-in a drawing's style is stored in. The UI layer converts to and
/// from `Color` at the boundary, the same way it resolves `IndicatorColorRole` into real colors.
public struct DrawingColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    /// A neutral default so a newly created drawing always has *some* explicit color rather than
    /// depending on the UI layer to invent one — a mid-blue, distinct from the chart's own up/down
    /// palette so drawings read as annotations rather than data series.
    public static let `default` = DrawingColor(red: 0.2, green: 0.5, blue: 0.95)
}

/// Visual configuration for one drawing. Deliberately per-drawing (not a chart-wide default alone)
/// so two trend lines on the same chart can carry different colors, matching how a trader actually
/// annotates a chart.
public struct DrawingStyle: Codable, Hashable, Sendable {
    public var color: DrawingColor
    public var lineWidth: Double
    /// `nil` for a solid line.
    public var dash: [Double]?
    /// Fill opacity for a shape that encloses an area (rectangle, and Tier 2's ellipse/triangle/
    /// channel). `nil` for a stroke-only drawing — a trend line has nothing to fill.
    public var fillOpacity: Double?

    public init(
        color: DrawingColor = .default,
        lineWidth: Double = 1.5,
        dash: [Double]? = nil,
        fillOpacity: Double? = nil
    ) {
        self.color = color
        self.lineWidth = lineWidth
        self.dash = dash
        self.fillOpacity = fillOpacity
    }
}

/// One drawing on the chart — the unit an app's `[Drawing]` array (bound via `.drawings($drawings)`)
/// stores, persists, and mutates. See the design note for the full model rationale.
public struct Drawing: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var kind: DrawingKind
    /// `kind.anchorCount` entries, in a kind-specific order documented on each `DrawingKind` case's
    /// use — for example `.rectangle`'s two anchors are opposite corners, `.ray`'s first anchor is
    /// the origin the ray extends from.
    public var anchors: [DrawingAnchor]
    public var style: DrawingStyle
    /// Prevents move/resize/delete through the chart's own gestures (§4 of the design note) without
    /// affecting programmatic edits to the struct.
    public var isLocked: Bool
    /// Hides the drawing from rendering and hit testing without removing it — the same
    /// toggle-without-losing-configuration pattern `ChartIndicator.isVisible` uses.
    public var isHidden: Bool
    /// Only meaningful for `.textNote`; `nil` for every other kind.
    public var text: String?

    public init(
        id: UUID = UUID(),
        kind: DrawingKind,
        anchors: [DrawingAnchor],
        style: DrawingStyle = DrawingStyle(),
        isLocked: Bool = false,
        isHidden: Bool = false,
        text: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.anchors = anchors
        self.style = style
        self.isLocked = isLocked
        self.isHidden = isHidden
        self.text = text
    }

    /// `true` when `anchors.count` matches what `kind` requires — every drawing the chart itself
    /// creates satisfies this by construction; this exists mainly to validate drawings coming from
    /// a saved layout or another source, which might be stale after a `DrawingKind` migration.
    public var hasValidAnchorCount: Bool {
        anchors.count == kind.anchorCount
    }
}
