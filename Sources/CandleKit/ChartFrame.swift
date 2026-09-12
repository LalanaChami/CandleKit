#if os(iOS)
import SwiftUI

struct ChartMetrics {
    var priceAxisWidth: CGFloat
    var timeAxisHeight: CGFloat
    var priceTickSpacing: Double = 56
    var timeLabelSpacing: Double = 96
}

/// Rectangles for each chart region, in the chart's local coordinates.
struct ChartLayout {
    let plot: CGRect
    let priceAxis: CGRect
    let timeAxis: CGRect
    /// Vertical span used for prices inside the plot.
    let priceBand: ClosedRange<CGFloat>
    /// Vertical span used for volume bars, if shown.
    let volumeBand: ClosedRange<CGFloat>?

    init(size: CGSize, metrics: ChartMetrics, showsVolume: Bool) {
        let plotWidth = max(0, size.width - metrics.priceAxisWidth)
        let plotHeight = max(0, size.height - metrics.timeAxisHeight)
        plot = CGRect(x: 0, y: 0, width: plotWidth, height: plotHeight)
        priceAxis = CGRect(x: plotWidth, y: 0, width: max(0, size.width - plotWidth), height: plotHeight)
        timeAxis = CGRect(x: 0, y: plotHeight, width: plotWidth, height: max(0, size.height - plotHeight))

        let inset = min(12, plotHeight * 0.05)
        if showsVolume {
            volumeBand = (plotHeight * 0.8)...plotHeight
            priceBand = inset...max(inset, plotHeight * 0.78)
        } else {
            volumeBand = nil
            priceBand = inset...max(inset, plotHeight - inset)
        }
    }
}

/// Everything the renderers need for one frame, computed once per render.
struct ChartFrame {
    let candles: [Candle]
    let layout: ChartLayout
    let viewport: Viewport
    let visible: Range<Int>
    let priceScale: LinearScale
    let priceTicks: PriceTicks
    let priceFractionDigits: Int
    let timeTicks: [TimeTick]
    let baseTimeUnit: TimeLabelUnit
    let interval: TimeInterval
    let volumeMax: Double
    /// Indicators computed and colour-resolved for this frame. Only those on the price pane are
    /// drawn today; separate panes arrive with roadmap task 5.3.
    let indicators: [ResolvedIndicator]
    /// Pre-formatted axis labels, parallel to `priceTicks.values` and `timeTicks`.
    ///
    /// Formatting happens once per change in `CandleChartState.makeFrame`, not inside the Canvas
    /// closure. Number and date formatting is expensive, and the renderer runs on every frame of
    /// every scroll while these values usually stay put.
    let priceTickLabels: [String]
    let timeTickLabels: [String]
    /// Label for the last-price tag, or `nil` when there's no data.
    let lastPriceLabel: String?

    var plotWidth: Double { Double(layout.plot.width) }

    /// Visible range plus one candle on each side, so indicator lines run off the edges instead of stopping short.
    var lineRange: Range<Int> {
        guard !visible.isEmpty else { return visible }
        return max(0, visible.lowerBound - 1)..<min(candles.count, visible.upperBound + 1)
    }

    func centerX(ofCandle index: Int) -> CGFloat {
        layout.plot.minX + CGFloat(viewport.centerX(ofCandle: index, width: plotWidth))
    }

    func y(forPrice price: Double) -> CGFloat {
        CGFloat(priceScale.map(price))
    }

    func price(atY y: CGFloat) -> Double {
        priceScale.invert(Double(y))
    }
}

enum ChartFormat {
    static func price(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(max(0, digits))))
    }

    static func signedPrice(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(max(0, digits))).sign(strategy: .always()))
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()))
    }

    static func volume(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func axisTime(_ date: Date, unit: TimeLabelUnit) -> String {
        switch unit {
        case .time: return date.formatted(.dateTime.hour().minute())
        case .day: return date.formatted(.dateTime.month(.abbreviated).day())
        case .month: return date.formatted(.dateTime.month(.abbreviated))
        case .year: return date.formatted(.dateTime.year())
        }
    }

    static func detailedTime(_ date: Date, interval: TimeInterval) -> String {
        if interval < 86_400 {
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }
}

enum ChartText {
    static func label(_ string: String, color: Color, emphasized: Bool = false) -> Text {
        Text(string)
            .font(.caption2.monospacedDigit())
            .fontWeight(emphasized ? .semibold : .regular)
            .foregroundStyle(color)
    }

    /// A filled tag on the price axis, clamped so it never leaves the axis.
    static func drawPriceTag(
        _ string: String,
        y: CGFloat,
        in rect: CGRect,
        background: Color,
        foreground: Color,
        context: inout GraphicsContext
    ) {
        let text = context.resolve(label(string, color: foreground, emphasized: true))
        let size = text.measure(in: CGSize(width: rect.width, height: .greatestFiniteMagnitude))
        let height = size.height + 4
        let centerY = min(max(y, rect.minY + height / 2), rect.maxY - height / 2)
        let tag = CGRect(x: rect.minX + 2, y: centerY - height / 2, width: min(rect.width - 4, size.width + 8), height: height)
        context.fill(Path(roundedRect: tag, cornerRadius: 4), with: .color(background))
        context.draw(text, at: CGPoint(x: tag.minX + 4, y: centerY), anchor: .leading)
    }

    /// A filled tag on the time axis, clamped horizontally.
    static func drawTimeTag(
        _ string: String,
        x: CGFloat,
        in rect: CGRect,
        background: Color,
        foreground: Color,
        context: inout GraphicsContext
    ) {
        let text = context.resolve(label(string, color: foreground, emphasized: true))
        let size = text.measure(in: CGSize(width: rect.width, height: rect.height))
        let width = size.width + 10
        let centerX = min(max(x, rect.minX + width / 2), rect.maxX - width / 2)
        let tag = CGRect(x: centerX - width / 2, y: rect.minY + 2, width: width, height: max(0, rect.height - 4))
        context.fill(Path(roundedRect: tag, cornerRadius: 4), with: .color(background))
        context.draw(text, at: CGPoint(x: centerX, y: tag.midY), anchor: .center)
    }
}

/// Converts between points and device pixels so 1pt lines and candle edges stay crisp.
struct PixelGrid {
    let scale: CGFloat

    init(scale: CGFloat) {
        self.scale = max(scale, 1)
    }

    var hairline: CGFloat { 1 / scale }

    func snap(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    /// Centers a hairline on a physical pixel so it doesn't blur across two.
    func hairlineCenter(_ value: CGFloat) -> CGFloat {
        ((value * scale).rounded(.down) + 0.5) / scale
    }
}
#endif
