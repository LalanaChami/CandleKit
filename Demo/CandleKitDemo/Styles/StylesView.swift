import CandleKit
import SwiftUI
import UIKit

struct StylesView: View {
    private static let candles = CandleSampleData.randomWalk(
        count: 160,
        interval: 86_400,
        startPrice: 240,
        volatility: 0.02,
        seed: 11
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 32) {
                    ForEach(StyleExample.all) { example in
                        StyleExampleCard(example: example, candles: Self.candles)
                    }
                }
                .padding()
            }
            .navigationTitle("Styles")
        }
    }
}

struct StyleExample: Identifiable {
    let id: String
    let summary: String
    let code: String
    var style: CandleChartStyle = .standard
    var indicators: [ChartIndicator] = []
    var showsHeader = true
    var showsVolume = true
    var height: CGFloat = 260

    // Computed rather than stored: `CandleChartStyle` holds colors and isn't declared `Sendable`.
    static var all: [StyleExample] {
        [
            StyleExample(
                id: "Standard",
                summary: "Semantic system colors that adapt to light mode, dark mode and increased contrast.",
                code: "CandlestickChart(candles)"
            ),
            StyleExample(
                id: "Red up",
                summary: "Red for rising prices, the convention in markets such as mainland China, Taiwan and South Korea.",
                code: "CandlestickChart(candles)\n    .candleChartStyle(.redUp)",
                style: .redUp
            ),
            StyleExample(
                id: "Color-blind safe",
                summary: "Blue and orange stay distinguishable for the most common forms of color blindness.",
                code: "CandlestickChart(candles)\n    .candleChartStyle(.colorBlindSafe)",
                style: .colorBlindSafe
            ),
            StyleExample(
                id: "Hollow candles",
                summary: "Rising candles are drawn as outlines.",
                code: "CandlestickChart(candles)\n    .candleChartStyle(CandleChartStyle(hollowUpCandles: true))",
                style: CandleChartStyle(hollowUpCandles: true)
            ),
            StyleExample(
                id: "Your brand",
                summary: "Any colors, a narrower body and moving-average overlays.",
                code: """
                CandlestickChart(candles)
                    .candleChartStyle(CandleChartStyle(
                        upColor: .mint, downColor: .pink, bodyWidthRatio: 0.5))
                    .indicators([.sma(20, color: .yellow), .ema(50, color: .indigo)])
                """,
                style: CandleChartStyle(upColor: .mint, downColor: .pink, bodyWidthRatio: 0.5),
                indicators: [.sma(20, color: .yellow), .ema(50, color: .indigo)]
            ),
            StyleExample(
                id: "Compact",
                summary: "No header or volume, for cards and lists.",
                code: "CandlestickChart(candles)\n    .headerVisible(false)\n    .volumeVisible(false)",
                showsHeader: false,
                showsVolume: false,
                height: 160
            ),
        ]
    }
}

private struct StyleExampleCard: View {
    let example: StyleExample
    let candles: [Candle]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(example.id)
                .font(.headline)
            Text(example.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            CandlestickChart(candles)
                .candleChartStyle(example.style)
                .indicators(example.indicators)
                .headerVisible(example.showsHeader)
                .volumeVisible(example.showsVolume)
                .frame(height: example.height)

            Text(example.code)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

#Preview {
    StylesView()
}
