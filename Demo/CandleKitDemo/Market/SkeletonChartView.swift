import SwiftUI

/// Placeholder chart shown while candle data loads. Draws deterministic placeholder candles
/// using overlapping sine waves so the shape is consistent across appearances, with a gradient
/// band that sweeps left to right to signal activity.
struct SkeletonChartView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(elapsed.truncatingRemainder(dividingBy: 1.5) / 1.5)
            Canvas { context, size in
                Self.drawCandles(in: &context, size: size, isDark: isDark)
                Self.drawShimmer(in: &context, size: size, phase: phase, isDark: isDark)
            }
        }
    }

    private static func drawCandles(in context: inout GraphicsContext, size: CGSize, isDark: Bool) {
        let count = 30
        let slotW = size.width / CGFloat(count)
        let bodyW = max(3, slotW * 0.65).rounded()
        let midY  = size.height * 0.5
        let amp   = size.height * 0.28
        let bodyFill = GraphicsContext.Shading.color(Color.secondary.opacity(isDark ? 0.28 : 0.18))
        let wickFill = GraphicsContext.Shading.color(Color.secondary.opacity(isDark ? 0.18 : 0.11))

        for i in 0..<count {
            let d = Double(i)
            // Two sine waves at incommensurate frequencies produce a natural-looking waveform.
            let o = sin(d * 0.71 + 0.40) * 0.32 + 0.50
            let c = sin(d * 1.13 + 1.75) * 0.32 + 0.50
            let h = max(o, c) + abs(sin(d * 2.31 + 0.90)) * 0.10
            let l = min(o, c) - abs(sin(d * 1.87 + 2.10)) * 0.10

            let cx = CGFloat(i) * slotW + slotW / 2
            let oY = midY - CGFloat(o - 0.5) * amp * 2
            let cY = midY - CGFloat(c - 0.5) * amp * 2
            let hY = midY - CGFloat(h - 0.5) * amp * 2
            let lY = midY - CGFloat(l - 0.5) * amp * 2

            var wick = Path()
            wick.move(to:    CGPoint(x: cx, y: hY))
            wick.addLine(to: CGPoint(x: cx, y: lY))
            context.stroke(wick, with: wickFill, lineWidth: 1)

            let top = min(oY, cY)
            let bodyH = max(abs(oY - cY), 3)
            context.fill(Path(CGRect(x: cx - bodyW / 2, y: top, width: bodyW, height: bodyH)), with: bodyFill)
        }
    }

    // Narrow gradient band that sweeps left → right over 1.5 s.
    private static func drawShimmer(in context: inout GraphicsContext, size: CGSize, phase: CGFloat, isDark: Bool) {
        let shimX = (size.width + 200) * phase - 100
        let bandHalf: CGFloat = 60
        let highlight = Color.white.opacity(isDark ? 0.07 : 0.55)

        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear,    location: 0),
                    .init(color: highlight, location: 0.5),
                    .init(color: .clear,    location: 1),
                ]),
                startPoint: CGPoint(x: shimX - bandHalf, y: 0),
                endPoint:   CGPoint(x: shimX + bandHalf, y: 0)
            )
        )
    }
}

#Preview {
    VStack(spacing: 0) {
        SkeletonChartView()
            .frame(height: 300)
        SkeletonChartView()
            .frame(height: 300)
            .preferredColorScheme(.dark)
    }
}
