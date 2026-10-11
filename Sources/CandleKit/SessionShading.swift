#if os(iOS)
import SwiftUI

/// How ``CandlestickChart/tradingSessions(_:shading:)`` tints the plot behind each kind of session.
///
/// Regular sessions are never tinted. The defaults are semantic system colors at low opacity, so they
/// stay readable in light mode, dark mode and increased contrast.
public struct SessionShadingStyle {
    public var preMarket: Color
    public var afterHours: Color
    public var overnight: Color

    public init(
        preMarket: Color = Color.orange.opacity(0.10),
        afterHours: Color = Color.indigo.opacity(0.10),
        overnight: Color = Color.gray.opacity(0.12)
    ) {
        self.preMarket = preMarket
        self.afterHours = afterHours
        self.overnight = overnight
    }

    /// The tint for a session kind, or `nil` for kinds that aren't shaded.
    func color(for kind: TradingSession.Kind) -> Color? {
        switch kind {
        case .regular: return nil
        case .preMarket: return preMarket
        case .afterHours: return afterHours
        case .overnight: return overnight
        }
    }
}
#endif
