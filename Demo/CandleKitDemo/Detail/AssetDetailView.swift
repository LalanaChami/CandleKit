import CandleKit
import SwiftUI

/// A typical asset page. The chart sits inside a vertical ScrollView: horizontal drags move the chart,
/// vertical drags scroll the page.
struct AssetDetailView: View {
    private static let candles = CandleSampleData.randomWalk(
        count: 365,
        interval: 86_400,
        startPrice: 48,
        volatility: 0.018,
        seed: 21
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    CandlestickChart(Self.candles)
                        .indicators([.sma(50)])
                        .frame(height: 340)

                    statistics

                    VStack(alignment: .leading, spacing: 8) {
                        Text("About this screen")
                            .font(.title3.weight(.semibold))
                        Text("Try scrolling this page up and down while your finger starts on the chart. CandleKit only claims mostly-horizontal drags, so the page still scrolls normally. Pinch and long-press work as usual.")
                        Text("The company and prices here are fictional.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profile")
                            .font(.title3.weight(.semibold))
                        Text("Northwind Energy develops grid-scale battery storage and sells capacity to utilities across North America. It operates twelve storage sites and is building four more.")
                        Text("Revenue comes mainly from long-term capacity contracts, with a growing share from short-term balancing services.")
                    }
                }
                .padding()
            }
            .navigationTitle("Northwind Energy")
        }
    }

    private var statistics: some View {
        let candles = Self.candles
        let first = candles.first?.open ?? 0
        let last = candles.last?.close ?? 0
        let change = first != 0 ? (last - first) / first : 0
        let high = candles.map(\.high).max() ?? 0
        let low = candles.map(\.low).min() ?? 0
        let averageVolume = candles.isEmpty ? 0 : candles.map(\.volume).reduce(0, +) / Double(candles.count)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Past year")
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 16) {
                StatisticView(title: "Change", value: change.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))
                StatisticView(title: "Last close", value: last.formatted(.currency(code: "USD")))
                StatisticView(title: "High", value: high.formatted(.currency(code: "USD")))
                StatisticView(title: "Low", value: low.formatted(.currency(code: "USD")))
                StatisticView(title: "Average volume", value: averageVolume.formatted(.number.notation(.compactName)))
                StatisticView(title: "Days", value: candles.count.formatted())
            }
        }
    }
}

private struct StatisticView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit().weight(.medium))
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    AssetDetailView()
}
