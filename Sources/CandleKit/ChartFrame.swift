#if os(iOS)
import SwiftUI

struct ChartMetrics {
    var priceAxisWidth: CGFloat
    var timeAxisHeight: CGFloat
    var priceTickSpacing: Double = 56
    var timeLabelSpacing: Double = 96
    /// Gap between stacked panes, where the separator is drawn.
    var paneSpacing: CGFloat = 8
    /// Indicator panes never take more than this share of the content height, however many are
    /// added or however tall each asks to be. Without a cap, four indicators squeeze the candles
    /// into a sliver — the one thing the user is actually looking at.
    var maximumIndicatorPaneShare: CGFloat = 0.6
    /// Vertical spacing between value labels inside an indicator pane. Larger than the price axis's
    /// because panes are short and two or three labels is plenty.
    var paneTickSpacing: Double = 40
    /// How far candles extend underneath the price axis, letting them show (blurred, if the style
    /// sets a material there) through it as they scroll toward the edge. `0` reproduces the classic
    /// non-overlapping layout exactly. `CandlestickChart` sets this only when
    /// `CandleChartStyle.priceAxisMaterial` is non-nil — with no material there's nothing to keep
    /// the tick labels legible against candles moving underneath, so the two are always paired.
    var priceAxisOverlap: CGFloat = 0
}

/// One horizontal band of the chart with its own vertical scale — the candles, or an indicator
/// pane beneath them.
struct ChartPaneLayout: Identifiable {
    /// `"price"` for the main pane, otherwise the indicator's id.
    let id: String
    /// Drawing area, excluding the value axis.
    let plot: CGRect
    /// Value axis to the right of `plot`.
    let valueAxis: CGRect
    /// Vertical span values map into, inset from `plot` so lines don't touch the pane edges.
    let valueBand: ClosedRange<CGFloat>
}

/// Rectangles for each chart region, in the chart's local coordinates.
struct ChartLayout {
    let pricePane: ChartPaneLayout
    /// One pane per indicator that asked for its own, stacked top to bottom under the price.
    let indicatorPanes: [ChartPaneLayout]
    let timeAxis: CGRect
    /// Vertical span used for volume bars inside the price pane, if shown.
    let volumeBand: ClosedRange<CGFloat>?
    /// Y positions of the dividing lines between panes.
    let separators: [CGFloat]

    // Convenience accessors so the large amount of existing code that only knows about the price
    // pane keeps reading naturally.
    var plot: CGRect { pricePane.plot }
    var priceAxis: CGRect { pricePane.valueAxis }
    var priceBand: ClosedRange<CGFloat> { pricePane.valueBand }

    /// The full interactive area: every pane stacked, excluding the axes. Gestures cover this, so a
    /// drag that starts on an indicator pane still pans the chart.
    ///
    /// Depends only on the size and metrics, never on which indicators are present, so the gesture
    /// view can be positioned without waiting for indicators to be computed.
    static func contentRect(size: CGSize, metrics: ChartMetrics) -> CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: max(0, size.width - metrics.priceAxisWidth + metrics.priceAxisOverlap),
            height: max(0, size.height - metrics.timeAxisHeight)
        )
    }

    /// - Parameter indicatorPaneHeights: requested height per pane, in order. Heights are scaled
    ///   down proportionally if they'd exceed `metrics.maximumIndicatorPaneShare`.
    init(
        size: CGSize,
        metrics: ChartMetrics,
        showsVolume: Bool,
        indicatorPaneHeights: [(id: String, height: CGFloat)] = []
    ) {
        let content = ChartLayout.contentRect(size: size, metrics: metrics)
        let plotWidth = content.width
        let axisWidth = metrics.priceAxisWidth
        // The axis column's own left edge doesn't move when overlap is nonzero — only the plot
        // widens to slide underneath it. That's what lets candles peek through a glass axis without
        // the axis itself sliding around or changing width.
        let axisX = max(0, plotWidth - metrics.priceAxisOverlap)
        let contentHeight = content.height

        timeAxis = CGRect(
            x: 0,
            y: contentHeight,
            // Deliberately not `plotWidth`: the time axis stops at the same boundary it always has,
            // so the bottom-right corner doesn't get an odd sliver of time axis under the glass.
            width: axisX,
            height: max(0, size.height - contentHeight)
        )

        // Work out how much vertical space the indicator panes actually get.
        let spacing = indicatorPaneHeights.isEmpty
            ? 0
            : metrics.paneSpacing * CGFloat(indicatorPaneHeights.count)
        let requested = indicatorPaneHeights.reduce(0) { $0 + $1.height } + spacing
        let allowed = contentHeight * metrics.maximumIndicatorPaneShare
        let scale = requested > allowed && requested > 0 ? allowed / requested : 1
        let paneSpacing = metrics.paneSpacing * scale

        var panes: [ChartPaneLayout] = []
        var separatorPositions: [CGFloat] = []

        // Lay the indicator panes out from the bottom up, so the price pane keeps whatever's left
        // at the top — the arrangement every trading chart uses.
        var bottom = contentHeight
        for entry in indicatorPaneHeights.reversed() {
            let height = max(0, entry.height * scale)
            let top = bottom - height
            let paneRect = CGRect(x: 0, y: top, width: plotWidth, height: height)
            let inset = min(6, height * 0.12)
            panes.append(ChartPaneLayout(
                id: entry.id,
                plot: paneRect,
                valueAxis: CGRect(x: axisX, y: top, width: axisWidth, height: height),
                valueBand: (top + inset)...max(top + inset, paneRect.maxY - inset)
            ))
            separatorPositions.append(top)
            bottom = top - paneSpacing
        }
        indicatorPanes = panes.reversed()
        separators = separatorPositions.sorted()

        let priceHeight = max(0, bottom)
        let priceRect = CGRect(x: 0, y: 0, width: plotWidth, height: priceHeight)
        let inset = min(12, priceHeight * 0.05)
        let band: ClosedRange<CGFloat>
        if showsVolume {
            volumeBand = (priceHeight * 0.8)...priceHeight
            band = inset...max(inset, priceHeight * 0.78)
        } else {
            volumeBand = nil
            band = inset...max(inset, priceHeight - inset)
        }
        pricePane = ChartPaneLayout(
            id: "price",
            plot: priceRect,
            valueAxis: CGRect(x: axisX, y: 0, width: axisWidth, height: priceHeight),
            valueBand: band
        )
    }
}

/// An indicator pane's computed contents: which indicators it holds, and the scale they map into.
struct ResolvedPane: Identifiable {
    let layout: ChartPaneLayout
    let indicators: [ResolvedIndicator]
    let scale: LinearScale
    let ticks: PriceTicks
    let tickLabels: [String]

    var id: String { layout.id }

    func y(forValue value: Double) -> CGFloat {
        CGFloat(scale.map(value))
    }

    func value(atY y: CGFloat) -> Double {
        scale.invert(Double(y))
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
    /// Indicators drawn over the candles, sharing the price scale.
    let indicators: [ResolvedIndicator]
    /// Indicators drawn in their own panes beneath the price, each with its own vertical scale.
    let panes: [ResolvedPane]
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
