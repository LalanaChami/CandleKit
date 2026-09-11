#if os(iOS)
import Accessibility
import SwiftUI

/// Lets VoiceOver users explore the visible candles with Audio Graphs, which play closing prices as pitch.
struct ChartAccessibility: AXChartDescriptorRepresentable {
    let candles: ArraySlice<Candle>
    let fractionDigits: Int
    let interval: TimeInterval

    init(frame: ChartFrame) {
        candles = frame.candles[frame.visible]
        fractionDigits = frame.priceFractionDigits
        interval = frame.interval
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let firstTime = candles.first?.time.timeIntervalSince1970 ?? 0
        let lastTime = candles.last?.time.timeIntervalSince1970 ?? 0
        let closes = candles.map(\.close)
        let lowest = closes.min() ?? 0
        let highest = closes.max() ?? 0
        let digits = fractionDigits
        let candleInterval = self.interval

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Time",
            range: firstTime...max(lastTime, firstTime + 1),
            gridlinePositions: []
        ) { value in
            ChartFormat.detailedTime(Date(timeIntervalSince1970: value), interval: candleInterval)
        }
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Close",
            range: lowest...max(highest, lowest + 1e-9),
            gridlinePositions: []
        ) { value in
            ChartFormat.price(value, digits: digits)
        }
        let series = AXDataSeriesDescriptor(
            name: "Close",
            isContinuous: true,
            dataPoints: candles.map { AXDataPoint(x: $0.time.timeIntervalSince1970, y: $0.close) }
        )
        return AXChartDescriptor(
            title: "Candlestick chart",
            summary: ChartAccessibility.summary(of: candles, digits: digits, interval: candleInterval),
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }

    static func summary(of candles: ArraySlice<Candle>, digits: Int, interval: TimeInterval) -> String {
        guard let first = candles.first, let last = candles.last else { return "No data" }
        let change = first.open != 0 ? (last.close - first.open) / first.open : 0
        return "\(candles.count) candles from \(ChartFormat.detailedTime(first.time, interval: interval)) "
            + "to \(ChartFormat.detailedTime(last.time, interval: interval)). "
            + "Close \(ChartFormat.price(last.close, digits: digits)), \(ChartFormat.percent(change)) over this range."
    }
}
#endif
