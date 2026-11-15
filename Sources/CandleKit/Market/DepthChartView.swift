#if os(iOS)
import SwiftUI

/// A depth chart: cumulative bid size falling away to the left of the mid price and cumulative
/// ask size to the right, drawn as two filled steps.
///
/// ```swift
/// DepthChartView(book)
///     .depthWindow(0.02)
///     .frame(height: 180)
/// ```
///
/// Drawn in a single canvas, so the cost doesn't grow with the number of levels beyond walking
/// them once. The view needs no chart and can be placed anywhere.
public struct DepthChartView: View {
    private let book: OrderBook
    private var window = 0.02
    private var style = MarketDataStyle.standard

    public init(_ book: OrderBook) {
        self.book = book
    }

    public var body: some View {
        if let curve = DepthCurve(book: book, window: window) {
            Canvas { context, size in
                Self.draw(curve, style: style, in: &context, size: size)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Depth chart"))
            .accessibilityValue(Text(Self.summary(of: curve, style: style)))
        } else {
            ContentUnavailableView("No depth", systemImage: "chart.xyaxis.line")
        }
    }

    /// How far either side of the mid price to show, as a share of it. Default 0.02 (±2%).
    /// Zero or a negative value shows the whole book.
    public func depthWindow(_ window: Double) -> DepthChartView {
        var copy = self
        copy.window = window
        return copy
    }

    /// Colors and number formatting.
    public func marketDataStyle(_ style: MarketDataStyle) -> DepthChartView {
        var copy = self
        copy.style = style
        return copy
    }

    // MARK: Drawing

    private static let labelBand: CGFloat = 16

    private static func draw(_ curve: DepthCurve, style: MarketDataStyle, in context: inout GraphicsContext, size: CGSize) {
        let low = curve.priceRange.lowerBound
        let high = curve.priceRange.upperBound
        let plotHeight = size.height - labelBand
        guard high > low, curve.maxCumulativeSize > 0, plotHeight > 0, size.width > 0 else { return }

        func x(_ price: Double) -> CGFloat {
            CGFloat((price - low) / (high - low)) * size.width
        }
        func y(_ total: Double) -> CGFloat {
            plotHeight * CGFloat(1 - total / curve.maxCumulativeSize)
        }

        let midX = x(curve.midPrice)
        fillSide(curve.bids, startX: midX, edgeX: 0, color: style.bidColor, plotHeight: plotHeight, x: x, y: y, in: &context)
        fillSide(curve.asks, startX: midX, edgeX: size.width, color: style.askColor, plotHeight: plotHeight, x: x, y: y, in: &context)

        var midLine = Path()
        midLine.move(to: CGPoint(x: midX, y: 0))
        midLine.addLine(to: CGPoint(x: midX, y: plotHeight))
        context.stroke(midLine, with: .color(Color.secondary.opacity(0.5)), lineWidth: 1)

        func label(_ price: Double) -> Text {
            Text(style.priceText(price)).font(.caption2).foregroundStyle(.secondary)
        }
        context.draw(label(low), at: CGPoint(x: 0, y: size.height), anchor: .bottomLeading)
        context.draw(label(curve.midPrice), at: CGPoint(x: midX, y: size.height), anchor: .bottom)
        context.draw(label(high), at: CGPoint(x: size.width, y: size.height), anchor: .bottomTrailing)
    }

    /// One side as a staircase: flat at the previous total until the next level's price, then a
    /// step to that level's total, running from the mid price out to the edge of the view.
    private static func fillSide(
        _ levels: [DepthLevel],
        startX: CGFloat,
        edgeX: CGFloat,
        color: Color,
        plotHeight: CGFloat,
        x: (Double) -> CGFloat,
        y: (Double) -> CGFloat,
        in context: inout GraphicsContext
    ) {
        guard !levels.isEmpty else { return }
        var outline = Path()
        outline.move(to: CGPoint(x: startX, y: plotHeight))
        var previousY = plotHeight
        for level in levels {
            let levelX = x(level.price)
            outline.addLine(to: CGPoint(x: levelX, y: previousY))
            previousY = y(level.cumulativeSize)
            outline.addLine(to: CGPoint(x: levelX, y: previousY))
        }
        outline.addLine(to: CGPoint(x: edgeX, y: previousY))

        var area = outline
        area.addLine(to: CGPoint(x: edgeX, y: plotHeight))
        area.closeSubpath()
        context.fill(area, with: .color(color.opacity(0.25)))
        context.stroke(outline, with: .color(color), lineWidth: 1.5)
    }

    private static func summary(of curve: DepthCurve, style: MarketDataStyle) -> String {
        let bidTotal = curve.bids.last?.cumulativeSize ?? 0
        let askTotal = curve.asks.last?.cumulativeSize ?? 0
        return "Bids \(style.sizeText(bidTotal)) down to \(style.priceText(curve.priceRange.lowerBound)), "
            + "asks \(style.sizeText(askTotal)) up to \(style.priceText(curve.priceRange.upperBound))"
    }
}

#Preview {
    DepthChartView(MarketSampleData.orderBook())
        .frame(height: 180)
        .padding()
}
#endif
