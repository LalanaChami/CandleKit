#if os(iOS)
import SwiftUI

/// Another instrument to plot against the chart's own series. See
/// ``CandlestickChart/comparing(_:normalization:)``.
public struct ComparisonSeries {
    /// Shown in the legend, for example a ticker symbol.
    public var name: String
    /// The series to compare, oldest first. It does not need the same candle times as the chart's
    /// series: each chart candle shows the most recent close at or before it.
    public var candles: [Candle]
    /// The line color. When `nil`, one is taken from the style's indicator palette.
    public var color: Color?
    public var lineWidth: CGFloat

    public init(name: String, candles: [Candle], color: Color? = nil, lineWidth: CGFloat = 1.5) {
        self.name = name
        self.candles = candles
        self.color = color
        self.lineWidth = lineWidth
    }
}

/// A cheap fingerprint of a comparison series, so `makeFrame` can tell whether to realign without
/// comparing whole candle arrays on every frame.
struct ComparisonKey: Equatable {
    let name: String
    let count: Int
    let firstTime: Date?
    let lastTime: Date?
    let lastClose: Double?

    init(_ series: ComparisonSeries) {
        name = series.name
        count = series.candles.count
        firstTime = series.candles.first?.time
        lastTime = series.candles.last?.time
        lastClose = series.candles.last?.close
    }
}

/// One comparison line as drawn: the aligned raw closes and the constant that puts them on the
/// primary series' price scale.
struct ComparisonLine {
    let name: String
    let color: Color
    let lineWidth: CGFloat
    let values: [Double?]
    let factor: Double

    /// The line's value at `index` on the primary price scale, or `nil` where it has none.
    func scaledValue(at index: Int) -> Double? {
        guard index >= 0, index < values.count, let value = values[index], value.isFinite else { return nil }
        return value * factor
    }
}

struct ComparisonFrame {
    let scaling: ComparisonScaling
    let lines: [ComparisonLine]
}

enum ComparisonFormat {
    /// An axis number as text: `+2.50%` for percent change, `102.50` for an index.
    static func string(_ value: Double, normalization: ComparisonNormalization, digits: Int) -> String {
        switch normalization {
        case .percentChange:
            return value.formatted(.number.precision(.fractionLength(max(0, digits))).sign(strategy: .always())) + "%"
        case .indexed100:
            return ChartFormat.price(value, digits: digits)
        }
    }
}

extension ChartFrame {
    /// What the price axis shows for a primary-scale price: the plain price, or in comparison mode
    /// the percent change or index it stands for.
    func axisLabel(forPrice price: Double) -> String {
        guard let scaling = comparison?.scaling else {
            return ChartFormat.price(price, digits: priceFractionDigits)
        }
        return ComparisonFormat.string(
            scaling.axisValue(forPrice: price),
            normalization: scaling.normalization,
            digits: 2
        )
    }
}

/// The names, colors and current values of the comparison lines, shown under the header.
///
/// Reads `revision` (like `LastPriceBadge`) so the values follow the crosshair and the live edge.
struct ComparisonLegend: View {
    let state: CandleChartState
    let style: CandleChartStyle

    var body: some View {
        let _ = state.revision
        if let frame = state.currentFrame, let comparison = frame.comparison, !comparison.lines.isEmpty {
            let index = min(max(state.crosshairIndex ?? (frame.candles.count - 1), 0), max(0, frame.candles.count - 1))
            HStack(spacing: 12) {
                ForEach(Array(comparison.lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 4) {
                        Capsule().fill(line.color).frame(width: 10, height: 3)
                        Text(line.name).foregroundStyle(.secondary)
                        Text(valueText(for: line, at: index, scaling: comparison.scaling))
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .accessibilityElement(children: .combine)
        }
    }

    private func valueText(for line: ComparisonLine, at index: Int, scaling: ComparisonScaling) -> String {
        guard let price = line.scaledValue(at: index) else { return "–" }
        return ComparisonFormat.string(
            scaling.axisValue(forPrice: price),
            normalization: scaling.normalization,
            digits: 2
        )
    }
}
#endif
