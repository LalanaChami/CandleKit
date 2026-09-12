#if os(iOS)
import SwiftUI

/// Price readout above the chart. Shows the latest candle, or the candle under the crosshair.
///
/// It sits above the plot rather than floating over it, so it never hides the candle being inspected.
struct ChartHeader: View {
    let state: CandleChartState
    let candles: [Candle]
    let fractionDigits: Int
    let style: CandleChartStyle

    var body: some View {
        let inspected = state.crosshairIndex.flatMap { candles.indices.contains($0) ? $0 : nil }
        let index = inspected ?? candles.count - 1
        let candle = candles[index]
        let reference = index > 0 ? candles[index - 1].close : candle.open
        let change = candle.close - reference
        let tint = change >= 0 ? style.upColor : style.downColor

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ChartFormat.price(candle.close, digits: fractionDigits))
                    .font(.title3.weight(.semibold).monospacedDigit())
                HStack(spacing: 6) {
                    Text(ChartFormat.signedPrice(change, digits: fractionDigits))
                    if reference != 0 {
                        Text(ChartFormat.percent(change / reference))
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(tint)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(ChartFormat.detailedTime(candle.time, interval: state.cachedInterval))
                    .foregroundStyle(inspected == nil ? Color.secondary : Color.primary)
                HStack(spacing: 8) {
                    field("O", candle.open)
                    field("H", candle.high)
                    field("L", candle.low)
                }
                if candle.volume > 0 {
                    HStack(spacing: 2) {
                        Text("Vol").foregroundStyle(.secondary)
                        Text(ChartFormat.volume(candle.volume))
                    }
                }
            }
            .font(.caption2.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private func field(_ name: String, _ value: Double) -> some View {
        HStack(spacing: 2) {
            Text(name).foregroundStyle(.secondary)
            Text(ChartFormat.price(value, digits: fractionDigits))
        }
    }
}
#endif
