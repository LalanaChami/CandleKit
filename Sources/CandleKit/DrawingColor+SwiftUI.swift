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
#endif
