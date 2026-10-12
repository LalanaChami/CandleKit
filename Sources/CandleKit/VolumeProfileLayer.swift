#if os(iOS)
import SwiftUI

/// Options for `.volumeProfile(_:)`.
public struct VolumeProfileStyle: Sendable {
    /// Number of price buckets across the visible price range. More buckets, finer detail.
    public var bucketCount: Int
    /// Widest bar as a share of the plot width.
    public var maximumWidthShare: Double
    /// Share of the volume the highlighted value area should hold (0.7 is customary).
    public var valueAreaShare: Double
    /// Draws a line across the chart at the point of control, the price with the most volume.
    public var showsPointOfControl: Bool

    public init(
        bucketCount: Int = 24,
        maximumWidthShare: Double = 0.28,
        valueAreaShare: Double = 0.7,
        showsPointOfControl: Bool = true
    ) {
        self.bucketCount = max(2, bucketCount)
        self.maximumWidthShare = min(max(maximumWidthShare, 0.05), 0.6)
        self.valueAreaShare = min(max(valueAreaShare, 0), 1)
        self.showsPointOfControl = showsPointOfControl
    }
}

/// Remembers the last profile so scrolling by a fraction of a candle doesn't recompute it. A plain
/// reference type: nothing observes it.
final class VolumeProfileCache {
    private var key: Key?
    private var cached: VolumeProfile?

    private struct Key: Equatable {
        var visible: Range<Int>
        var count: Int
        var lastClose: Double
        var lastVolume: Double
        var bucketCount: Int
        var share: Double
    }

    func profile(for frame: ChartFrame, style: VolumeProfileStyle) -> VolumeProfile? {
        guard let last = frame.candles.last else { return nil }
        let newKey = Key(
            visible: frame.visible, count: frame.candles.count, lastClose: last.close,
            lastVolume: last.volume, bucketCount: style.bucketCount, share: style.valueAreaShare
        )
        if newKey == key { return cached }
        cached = VolumeProfile.compute(
            candles: frame.candles, range: frame.visible,
            bucketCount: style.bucketCount, valueAreaShare: style.valueAreaShare
        )
        key = newKey
        return cached
    }
}

/// Horizontal volume-by-price bars along the right edge of the plot, for the candles on screen.
struct VolumeProfileLayer: View {
    let state: CandleChartState
    let style: VolumeProfileStyle
    let chartStyle: CandleChartStyle
    let cache: VolumeProfileCache

    var body: some View {
        let _ = state.revision
        if let frame = state.currentFrame, let profile = cache.profile(for: frame, style: style) {
            Canvas { context, _ in
                var clipped = context
                clipped.clip(to: Path(frame.layout.plot))
                Self.draw(profile, frame: frame, style: style, chartStyle: chartStyle, in: &clipped)
            }
            .allowsHitTesting(false)
        }
    }

    private static func draw(
        _ profile: VolumeProfile,
        frame: ChartFrame,
        style: VolumeProfileStyle,
        chartStyle: CandleChartStyle,
        in context: inout GraphicsContext
    ) {
        let plot = frame.layout.plot
        let maxVolume = profile.volumes.max() ?? 0
        guard maxVolume > 0 else { return }
        let maxWidth = plot.width * style.maximumWidthShare
        var inArea = Path()
        var outside = Path()
        for (index, volume) in profile.volumes.enumerated() where volume > 0 {
            let bottom = profile.lowPrice + profile.bucketHeight * Double(index)
            let top = bottom + profile.bucketHeight
            let yTop = frame.y(forPrice: top)
            let yBottom = frame.y(forPrice: bottom)
            let width = maxWidth * CGFloat(volume / maxVolume)
            // A hairline gap between buckets keeps neighbouring bars readable.
            let rect = CGRect(x: plot.maxX - width, y: yTop, width: width, height: max(1, yBottom - yTop - 1))
            if profile.valueArea.contains(index) { inArea.addRect(rect) } else { outside.addRect(rect) }
        }
        let base = chartStyle.axisLabelColor
        context.fill(outside, with: .color(base.opacity(0.22)))
        context.fill(inArea, with: .color(Color.blue.opacity(0.32)))
        if style.showsPointOfControl {
            let y = frame.y(forPrice: profile.price(ofBucket: profile.pointOfControl))
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: y))
            line.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(line, with: .color(Color.blue.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }
}
#endif
