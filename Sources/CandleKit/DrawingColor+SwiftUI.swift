#if os(iOS)
import SwiftUI

/// `CandleKitCore` can't depend on `SwiftUI.Color` (Linux has no SwiftUI, see `DrawingColor`'s own
/// doc comment), so the conversion lives here, at the UI-layer boundary — the same place
/// `IndicatorColorRole` gets resolved into a real `Color`. Public so an app building its own color
/// picker for `.defaultDrawingStyle(...)`/a drawing's `style.color` can render a swatch that matches
/// exactly, instead of reimplementing this conversion.
extension Color {
    public init(_ drawingColor: DrawingColor) {
        self.init(
            .sRGB,
            red: drawingColor.red,
            green: drawingColor.green,
            blue: drawingColor.blue,
            opacity: drawingColor.opacity
        )
    }
}

extension DrawingColor {
    /// The reverse of `Color.init(_:)` above, needed so a saved `ChartLayout`
    /// (`ChartLayout+CandleKit.swift`) can capture a chart style's `Color` properties in the same
    /// portable form a drawing's own colour already uses. `UIColor`'s RGBA accessor is the
    /// straightforward way to pull components back out of an opaque `Color` — resolving through
    /// `.sRGB` on the way in above means round-tripping through it here is exact, not approximate.
    public init(_ color: Color) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, opacity: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &opacity)
        self.init(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(opacity))
    }
}
#endif
