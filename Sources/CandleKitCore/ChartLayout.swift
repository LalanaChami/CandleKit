import Foundation

// What a trader spends real time building — a colour scheme, an indicator setup, a page of
// trend lines and Fibonacci retracements — currently lives only in an app's `@State` and is gone
// the moment the app relaunches. `ChartLayout` is the versioned, `Codable` value that lets an app
// save and restore all of it. Everything it wraps is already portable: `Drawing` and
// `IndicatorDescriptor` are already `Codable` and UI-framework-free, and `Viewport` just gained
// the same conformance. Style is the one piece that needs a stand-in for `SwiftUI.Color`/
// `Material` — see `StyleSnapshot` below, which reuses `DrawingColor` for exactly the reason
// `Drawing.swift`'s own doc comment gives for it: this file has to build and test on Linux.
//
// See `docs/ROADMAP.md` 7.3. Deliberately excludes indicator-pane sizes (5.11's pane-resize
// feature doesn't exist yet — nothing to capture) and doesn't model "timeframe" as a CandleKit
// type (candle data, and which timeframe it represents, is entirely app-supplied). What it does
// capture: style, indicators (with per-instance colour/width/visibility overrides), drawings, and
// the viewport.

/// One indicator attached to a saved layout: which one, its parameters, and the per-instance
/// display overrides `ChartIndicator` carries that `IndicatorDescriptor` alone doesn't (colours,
/// line width, visibility). Rehydrate against an `IndicatorCatalog` at the UI-layer boundary —
/// see `ChartIndicator.init?(_:catalog:)` in `Sources/CandleKit/ChartLayout+CandleKit.swift`.
public struct PersistedIndicator: Codable, Sendable, Equatable {
    public var descriptor: IndicatorDescriptor
    /// Empty means "use the chart style's palette," matching `ChartIndicator.colors`.
    public var colors: [DrawingColor]
    public var lineWidth: Double?
    public var isVisible: Bool

    public init(
        descriptor: IndicatorDescriptor,
        colors: [DrawingColor] = [],
        lineWidth: Double? = nil,
        isVisible: Bool = true
    ) {
        self.descriptor = descriptor
        self.colors = colors
        self.lineWidth = lineWidth
        self.isVisible = isVisible
    }
}

/// One saved chart configuration: style, indicators, drawings and scroll position. Save one with
/// `ChartLayout(style:indicators:drawings:viewport:timeframeIdentifier:)` (built from
/// `CandleChartStyle.snapshot`, `chartIndicators.map(\.persisted)`, an app's `[Drawing]`, and
/// `CandleChartState.currentViewport`); restore it the same way in reverse. `CandleKit` itself
/// never reads or writes this to disk — 7.4 in the roadmap deliberately leaves the store (files,
/// `UserDefaults`, SwiftData, a server) up to the app.
public struct ChartLayout: Codable, Sendable, Equatable {
    /// Bumped whenever a field is added, renamed or removed in a way older code can't just ignore.
    /// `1` has never shipped a migration, so there's nothing to migrate yet — this exists so the
    /// first time there *is* something, `init(from:)` below already has somewhere to hang it.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var style: StyleSnapshot
    public var indicators: [PersistedIndicator]
    public var drawings: [Drawing]
    public var viewport: Viewport
    /// Opaque, app-defined identifier for whichever timeframe was selected (`"1H"`, `"1D"`, a
    /// symbol+interval key — whatever the app's own model uses). CandleKit has no concept of
    /// timeframes of its own; this is a pass-through slot so an app doesn't need a second, separate
    /// persistence mechanism just to restore which one was active alongside everything else here.
    public var timeframeIdentifier: String?

    public init(
        style: StyleSnapshot,
        indicators: [PersistedIndicator] = [],
        drawings: [Drawing] = [],
        viewport: Viewport,
        timeframeIdentifier: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.style = style
        self.indicators = indicators
        self.drawings = drawings
        self.viewport = viewport
        self.timeframeIdentifier = timeframeIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, style, indicators, drawings, viewport, timeframeIdentifier
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version <= Self.currentSchemaVersion else {
            throw ChartLayoutError.unsupportedSchemaVersion(version)
        }
        schemaVersion = version
        style = try container.decode(StyleSnapshot.self, forKey: .style)
        // `decodeIfPresent`, not `decode`: a layout saved by a newer CandleKit that added one of
        // these arrays should still load in an older one, the same forward-compatibility
        // `IndicatorParameter.applying(_:)` already gives unknown parameter keys.
        indicators = try container.decodeIfPresent([PersistedIndicator].self, forKey: .indicators) ?? []
        drawings = try container.decodeIfPresent([Drawing].self, forKey: .drawings) ?? []
        viewport = try container.decode(Viewport.self, forKey: .viewport)
        timeframeIdentifier = try container.decodeIfPresent(String.self, forKey: .timeframeIdentifier)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(style, forKey: .style)
        try container.encode(indicators, forKey: .indicators)
        try container.encode(drawings, forKey: .drawings)
        try container.encode(viewport, forKey: .viewport)
        try container.encodeIfPresent(timeframeIdentifier, forKey: .timeframeIdentifier)
    }

    /// A saved layout's style — `CandleChartStyle` mirrored field-for-field, with `DrawingColor`
    /// standing in for `SwiftUI.Color`, for the same Linux-buildable reason `Drawing`'s colour is
    /// `DrawingColor` rather than `Color`. See `CandleChartStyle.init(_:)` and `.snapshot` in
    /// `Sources/CandleKit/ChartLayout+CandleKit.swift` for the conversion.
    ///
    /// Deliberately doesn't capture `CandleChartStyle.priceAxisMaterial`: `SwiftUI.Material` has no
    /// public way to introspect an arbitrary value back into one of its named levels (it isn't
    /// `Equatable` and exposes no accessor), so there's no faithful way to read an app's current
    /// setting back out of it, only to construct one from a known case. A style rebuilt from a
    /// saved layout (`CandleChartStyle.init(_:)`) always comes back with `priceAxisMaterial: nil`;
    /// an app using the glass axis re-applies it itself afterwards via `.candleChartStyle(...)`.
    public struct StyleSnapshot: Codable, Sendable, Equatable {
        public var upColor: DrawingColor
        public var downColor: DrawingColor
        public var hollowUpCandles: Bool
        public var bodyWidthRatio: Double
        public var volumeOpacity: Double
        public var gridColor: DrawingColor
        public var axisLabelColor: DrawingColor
        public var crosshairColor: DrawingColor
        public var indicatorPalette: [DrawingColor]
        public var crosshairDimOpacity: Double

        public init(
            upColor: DrawingColor,
            downColor: DrawingColor,
            hollowUpCandles: Bool,
            bodyWidthRatio: Double,
            volumeOpacity: Double,
            gridColor: DrawingColor,
            axisLabelColor: DrawingColor,
            crosshairColor: DrawingColor,
            indicatorPalette: [DrawingColor],
            crosshairDimOpacity: Double
        ) {
            self.upColor = upColor
            self.downColor = downColor
            self.hollowUpCandles = hollowUpCandles
            self.bodyWidthRatio = bodyWidthRatio
            self.volumeOpacity = volumeOpacity
            self.gridColor = gridColor
            self.axisLabelColor = axisLabelColor
            self.crosshairColor = crosshairColor
            self.indicatorPalette = indicatorPalette
            self.crosshairDimOpacity = crosshairDimOpacity
        }
    }
}

public enum ChartLayoutError: Error, Sendable, Equatable {
    /// Decoded a layout saved by a CandleKit version newer than this one. Surfaced rather than
    /// guessed at, since silently misreading an unknown schema is exactly how a user's saved
    /// annotations get corrupted.
    case unsupportedSchemaVersion(Int)
}
