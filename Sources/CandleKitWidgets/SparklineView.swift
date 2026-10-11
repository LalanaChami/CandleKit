#if canImport(SwiftUI)
import SwiftUI
import CandleKitCore

/// A minimal price line for places with a tiny draw budget: Live Activities, the Dynamic Island,
/// watch faces and complications.
///
/// It takes plain closing prices rather than candles so the same values can travel in an
/// `ActivityAttributes.ContentState` or a watch complication timeline entry. At most `maxPoints`
/// values are drawn; longer input is thinned by keeping evenly spaced samples and always the last one.
/// Drawn with a single `Shape`, no `Canvas`, no state, no animation.
public struct SparklineView: View {
    private let values: [Double]
    private let color: Color
    private let lineWidth: CGFloat

    public init(_ values: [Double], color: Color = .green, lineWidth: CGFloat = 1.5, maxPoints: Int = 30) {
        self.values = SparklineView.thinned(values, maxPoints: Swift.max(2, maxPoints))
        self.color = color
        self.lineWidth = lineWidth
    }

    /// Convenience for a candle series: uses the closes.
    public init(candles: [Candle], color: Color = .green, lineWidth: CGFloat = 1.5, maxPoints: Int = 30) {
        self.init(candles.map(\.close), color: color, lineWidth: lineWidth, maxPoints: maxPoints)
    }

    /// Keeps at most `maxPoints` values, evenly spaced, always including the first and last.
    /// The index arithmetic lives in Core (`SparklineSampling`), where it is unit tested.
    private static func thinned(_ values: [Double], maxPoints: Int) -> [Double] {
        SparklineSampling.indices(count: values.count, maxPoints: maxPoints).map { values[$0] }
    }

    public var body: some View {
        SparklineShape(values: values)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .accessibilityHidden(true)
    }
}

private struct SparklineShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        let finite = values.filter(\.isFinite)
        guard finite.count >= 2, let low = finite.min(), let high = finite.max() else { return Path() }
        let scale = LinearScale(domain: low...high, rangeStart: rect.maxY, rangeEnd: rect.minY)
        let step = rect.width / CGFloat(finite.count - 1)
        var path = Path()
        for (index, value) in finite.enumerated() {
            let point = CGPoint(x: rect.minX + step * CGFloat(index), y: CGFloat(scale.map(value)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
#endif
