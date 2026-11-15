#if os(iOS)
import SwiftUI

// The two market overlays that only draw (bid/ask lines and book depth). Both read the frame the
// candle layer built, the same way `VolumeProfileLayer` does, so they must sit after
// `ChartContentLayer` in the chart's ZStack. Neither takes touches.

/// Hosts the non-interactive market overlays, so the chart's own ZStack gains one child, not two.
struct MarketOverlayLayers: View {
    let state: CandleChartState
    let bid: Double?
    let ask: Double?
    let depthBook: OrderBook?
    let depthWidthShare: Double
    let style: MarketDataStyle

    var body: some View {
        if let depthBook, !depthBook.isEmpty {
            DepthOverlayLayer(state: state, book: depthBook, style: style, maximumWidthShare: depthWidthShare)
        }
        if bid != nil || ask != nil {
            QuoteLinesLayer(state: state, bid: bid, ask: ask, style: style)
        }
    }
}

/// Dashed lines across the plot at the current best bid and best ask.
struct QuoteLinesLayer: View {
    let state: CandleChartState
    let bid: Double?
    let ask: Double?
    let style: MarketDataStyle

    var body: some View {
        let _ = state.revision
        if let frame = state.currentFrame {
            Canvas { context, _ in
                let plot = frame.layout.plot
                var clipped = context
                clipped.clip(to: Path(plot))
                Self.strokeLine(at: bid, color: style.bidColor, frame: frame, in: &clipped)
                Self.strokeLine(at: ask, color: style.askColor, frame: frame, in: &clipped)
            }
            .allowsHitTesting(false)
        }
    }

    private static func strokeLine(at price: Double?, color: Color, frame: ChartFrame, in context: inout GraphicsContext) {
        guard let price, price.isFinite else { return }
        let plot = frame.layout.plot
        let y = frame.y(forPrice: price)
        guard y >= plot.minY, y <= plot.maxY else { return }
        var line = Path()
        line.move(to: CGPoint(x: plot.minX, y: y))
        line.addLine(to: CGPoint(x: plot.maxX, y: y))
        context.stroke(line, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
    }
}

/// The order book as horizontal bars along the left edge of the plot, lined up with the price axis.
struct DepthOverlayLayer: View {
    let state: CandleChartState
    let book: OrderBook
    let style: MarketDataStyle
    let maximumWidthShare: Double

    /// Target bar height in points. Buckets are sized from the plot height so bars stay this tall
    /// whatever the zoom.
    private static let barHeight: CGFloat = 4

    var body: some View {
        let _ = state.revision
        if let frame = state.currentFrame, let priceRange = state.currentPriceRange {
            Canvas { context, _ in
                var clipped = context
                clipped.clip(to: Path(frame.layout.plot))
                Self.draw(book, priceRange: priceRange, frame: frame, style: style, widthShare: maximumWidthShare, in: &clipped)
            }
            .allowsHitTesting(false)
        }
    }

    private static func draw(
        _ book: OrderBook,
        priceRange: ClosedRange<Double>,
        frame: ChartFrame,
        style: MarketDataStyle,
        widthShare: Double,
        in context: inout GraphicsContext
    ) {
        let plot = frame.layout.plot
        let bucketCount = max(1, Int(plot.height / barHeight))
        let buckets = OrderBookMath.buckets(of: book, priceRange: priceRange, bucketCount: bucketCount)
        let largest = max(buckets.bids.max() ?? 0, buckets.asks.max() ?? 0)
        guard largest > 0 else { return }

        let low = priceRange.lowerBound
        let height = (priceRange.upperBound - low) / Double(bucketCount)
        let maxWidth = plot.width * CGFloat(widthShare)

        func bars(_ sizes: [Double]) -> Path {
            var path = Path()
            for (index, size) in sizes.enumerated() where size > 0 {
                let yTop = frame.y(forPrice: low + height * Double(index + 1))
                let yBottom = frame.y(forPrice: low + height * Double(index))
                let width = maxWidth * CGFloat(size / largest)
                path.addRect(CGRect(x: plot.minX, y: yTop, width: width, height: max(1, yBottom - yTop - 1)))
            }
            return path
        }

        // Two fills in total, however many levels the book has.
        context.fill(bars(buckets.bids), with: .color(style.bidColor.opacity(0.3)))
        context.fill(bars(buckets.asks), with: .color(style.askColor.opacity(0.3)))
    }
}
#endif
