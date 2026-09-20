#if os(iOS)
import SwiftUI

// The UI-layer half of `ChartLayout` (see `Sources/CandleKitCore/ChartLayout.swift` for why the
// type itself lives in Core): converting a `CandleChartStyle`/`ChartIndicator` — both of which use
// `SwiftUI.Color` — to and from the portable, `Codable` snapshot types an app actually saves.
// Exactly the boundary `DrawingColor+SwiftUI.swift` already draws for drawings; this is the same
// line for style and indicators.

extension CandleChartStyle {
    /// Rebuilds a style from a saved layout's snapshot. `priceAxisMaterial` isn't part of the
    /// snapshot (see `StyleSnapshot`'s doc comment) and always comes back `nil` here — set it again
    /// afterwards if the app wants the glass axis back.
    public init(_ snapshot: ChartLayout.StyleSnapshot) {
        self.init(
            upColor: Color(snapshot.upColor),
            downColor: Color(snapshot.downColor),
            hollowUpCandles: snapshot.hollowUpCandles,
            bodyWidthRatio: CGFloat(snapshot.bodyWidthRatio),
            volumeOpacity: snapshot.volumeOpacity,
            gridColor: Color(snapshot.gridColor),
            axisLabelColor: Color(snapshot.axisLabelColor),
            crosshairColor: Color(snapshot.crosshairColor),
            indicatorPalette: snapshot.indicatorPalette.map(Color.init),
            priceAxisMaterial: nil,
            crosshairDimOpacity: snapshot.crosshairDimOpacity
        )
    }

    /// This style's saved-layout form. See `StyleSnapshot`'s doc comment for why
    /// `priceAxisMaterial` doesn't round-trip.
    public var snapshot: ChartLayout.StyleSnapshot {
        ChartLayout.StyleSnapshot(
            upColor: DrawingColor(upColor),
            downColor: DrawingColor(downColor),
            hollowUpCandles: hollowUpCandles,
            bodyWidthRatio: Double(bodyWidthRatio),
            volumeOpacity: volumeOpacity,
            gridColor: DrawingColor(gridColor),
            axisLabelColor: DrawingColor(axisLabelColor),
            crosshairColor: DrawingColor(crosshairColor),
            indicatorPalette: indicatorPalette.map(DrawingColor.init),
            crosshairDimOpacity: crosshairDimOpacity
        )
    }
}

extension ChartIndicator {
    /// Rebuilds a configured indicator from a saved layout entry, resolved against `catalog` the
    /// same way `IndicatorCatalog.makeIndicator(from:)` resolves a bare `IndicatorDescriptor`.
    /// `nil` when `catalog` doesn't recognise the identifier — an app that removed a custom
    /// indicator since the layout was saved should drop this one entry rather than fail the whole
    /// load, exactly as `makeIndicator(from:)` itself already handles an unknown identifier.
    public init?(_ persisted: PersistedIndicator, catalog: IndicatorCatalog) {
        guard let indicator = catalog.makeIndicator(from: persisted.descriptor) else { return nil }
        self.init(
            indicator,
            colors: persisted.colors.map(Color.init),
            // Not `.map(CGFloat.init)`: `CGFloat` has several generic initializers (from the
            // `BinaryFloatingPoint`/`BinaryInteger` conformances), so a bare `CGFloat.init` function
            // reference is ambiguous — the compiler has nothing to pick an overload from until it
            // sees a concrete argument. A closure forces `Double`'s already-known type through.
            lineWidth: persisted.lineWidth.map { CGFloat($0) },
            isVisible: persisted.isVisible
        )
    }

    /// This indicator's saved-layout form.
    public var persisted: PersistedIndicator {
        PersistedIndicator(
            descriptor: descriptor,
            colors: colors.map(DrawingColor.init),
            // Same ambiguity as above, mirrored: `Double.init` alone doesn't resolve.
            lineWidth: lineWidth.map { Double($0) },
            isVisible: isVisible
        )
    }
}
#endif
