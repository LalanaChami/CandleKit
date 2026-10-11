#if canImport(SwiftUI)
import SwiftUI
import CandleKitCore

/// A small, non-interactive chart for WidgetKit, Live Activities and other places where the full
/// `CandlestickChart` doesn't fit.
///
/// It depends only on `CandleKitCore` and SwiftUI shapes (no `Canvas`, no gestures, no state object),
/// so it renders in widget snapshots and costs a fixed amount to draw: the series is reduced to at
/// most `maxCandles` candles with `CandleAggregator.downsample` first. There are no axes or crosshair.
public struct WidgetCandleChart: View {
    public enum Mode: Sendable, Equatable {
        /// Wicks and bodies.
        case candles
        /// Close-price line with a soft fill underneath.
        case line
    }

    private let candles: [Candle]
    private let mode: Mode
    private let upColor: Color
    private let downColor: Color
    private let showsLastPrice: Bool
    private let priceFormat: FloatingPointFormatStyle<Double>

    /// - Parameters:
    ///   - candles: Ascending by time. Any length; long series are reduced to `maxCandles`.
    ///   - maxCandles: Upper bound on drawn candles (at least 2). Around 40 reads well in a small widget.
    ///   - showsLastPrice: Draws the last close in the top-trailing corner.
    public init(
        _ candles: [Candle],
        mode: Mode = .candles,
        maxCandles: Int = 40,
        upColor: Color = .green,
        downColor: Color = .red,
        showsLastPrice: Bool = false,
        priceFormat: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(2))
    ) {
        self.candles = CandleAggregator.downsample(candles, maxCount: Swift.max(2, maxCandles))
        self.mode = mode
        self.upColor = upColor
        self.downColor = downColor
        self.showsLastPrice = showsLastPrice
        self.priceFormat = priceFormat
    }

    private var range: ClosedRange<Double>? {
        PriceScale.autoRange(for: candles, in: 0..<candles.count)
    }

    private var trendColor: Color {
        guard let first = candles.first, let last = candles.last else { return upColor }
        return last.close >= first.open ? upColor : downColor
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            if let range, !candles.isEmpty {
                switch mode {
                case .candles:
                    WidgetCandleShape(candles: candles, range: range, bullish: false)
                        .fill(downColor)
                    WidgetCandleShape(candles: candles, range: range, bullish: true)
                        .fill(upColor)
                    WidgetWickShape(candles: candles, range: range, bullish: false)
                        .stroke(downColor, lineWidth: 1)
                    WidgetWickShape(candles: candles, range: range, bullish: true)
                        .stroke(upColor, lineWidth: 1)
                case .line:
                    WidgetLineShape(candles: candles, range: range, closed: true)
                        .fill(LinearGradient(colors: [trendColor.opacity(0.35), trendColor.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                    WidgetLineShape(candles: candles, range: range, closed: false)
                        .stroke(trendColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                if showsLastPrice, let last = candles.last {
                    Text(last.close, format: priceFormat)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(trendColor)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let first = candles.first, let last = candles.last else { return "No chart data" }
        let change = first.open == 0 ? 0 : (last.close - first.open) / first.open * 100
        return "Price chart, last \(last.close.formatted(priceFormat)), "
            + "\(change >= 0 ? "up" : "down") \(abs(change).formatted(.number.precision(.fractionLength(1)))) percent"
    }
}

// MARK: - Shapes (each batches every candle of one direction into a single path)

private struct WidgetGeometry {
    let candles: [Candle]
    let rect: CGRect
    let scale: LinearScale

    init(candles: [Candle], range: ClosedRange<Double>, rect: CGRect) {
        self.candles = candles
        self.rect = rect
        self.scale = LinearScale(domain: range, rangeStart: rect.maxY, rangeEnd: rect.minY)
    }

    var step: CGFloat { rect.width / CGFloat(Swift.max(candles.count, 1)) }
    func x(_ index: Int) -> CGFloat { rect.minX + step * (CGFloat(index) + 0.5) }
    func y(_ price: Double) -> CGFloat { CGFloat(scale.map(price)) }
}

private struct WidgetCandleShape: Shape {
    let candles: [Candle]
    let range: ClosedRange<Double>
    let bullish: Bool

    func path(in rect: CGRect) -> Path {
        let g = WidgetGeometry(candles: candles, range: range, rect: rect)
        let bodyWidth = Swift.max(1, g.step * 0.7)
        var path = Path()
        for (index, candle) in candles.enumerated() where candle.isBullish == bullish {
            let top = g.y(Swift.max(candle.open, candle.close))
            let bottom = g.y(Swift.min(candle.open, candle.close))
            path.addRect(CGRect(x: g.x(index) - bodyWidth / 2, y: top,
                                width: bodyWidth, height: Swift.max(1, bottom - top)))
        }
        return path
    }
}

private struct WidgetWickShape: Shape {
    let candles: [Candle]
    let range: ClosedRange<Double>
    let bullish: Bool

    func path(in rect: CGRect) -> Path {
        let g = WidgetGeometry(candles: candles, range: range, rect: rect)
        var path = Path()
        for (index, candle) in candles.enumerated() where candle.isBullish == bullish {
            path.move(to: CGPoint(x: g.x(index), y: g.y(candle.high)))
            path.addLine(to: CGPoint(x: g.x(index), y: g.y(candle.low)))
        }
        return path
    }
}

private struct WidgetLineShape: Shape {
    let candles: [Candle]
    let range: ClosedRange<Double>
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        let g = WidgetGeometry(candles: candles, range: range, rect: rect)
        var path = Path()
        for (index, candle) in candles.enumerated() {
            let point = CGPoint(x: g.x(index), y: g.y(candle.close))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        if closed, !candles.isEmpty {
            path.addLine(to: CGPoint(x: g.x(candles.count - 1), y: rect.maxY))
            path.addLine(to: CGPoint(x: g.x(0), y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
#endif
