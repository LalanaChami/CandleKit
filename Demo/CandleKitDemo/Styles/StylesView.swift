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

    /// Five US trading days of 15-minute candles, 04:00 to 20:00 New York time each day (64 candles
    /// a day), so the "Session shading" card has pre-market, regular and after-hours stretches to
    /// show. Re-timed from a random walk: the overnight and weekend gaps a real feed has simply
    /// don't exist on the chart's index-based x-axis, so only the candle times need to be right.
    private static let intradayCandles: [Candle] = {
        // 2026-01-05, a Monday, at 04:00 in New York (09:00 UTC; winter, so no daylight saving).
        let firstOpen = 1_767_603_600.0
        let candlesPerDay = 64
        let walk = CandleSampleData.randomWalk(
            count: candlesPerDay * 5,
            interval: 900,
            startPrice: 182,
            volatility: 0.004,
            seed: 29
        )
        return walk.enumerated().map { index, candle in
            var retimed = candle
            let day = index / candlesPerDay
            let slot = index % candlesPerDay
            retimed.time = Date(timeIntervalSince1970: firstOpen + Double(day) * 86_400 + Double(slot) * 900)
            return retimed
        }
    }()

    /// Two other instruments for the "Comparison" card. The second starts 40 days into the chart, so
    /// the card also shows a series that begins part-way through.
    private static let comparisonSeries: [ComparisonSeries] = [
        ComparisonSeries(
            name: "IDX",
            candles: CandleSampleData.randomWalk(count: 160, interval: 86_400, startPrice: 4_800, volatility: 0.012, seed: 3)
        ),
        ComparisonSeries(
            name: "ALT",
            candles: CandleSampleData.randomWalk(
                count: 120,
                start: Date(timeIntervalSince1970: 1_767_225_600 + 40 * 86_400),
                interval: 86_400,
                startPrice: 60,
                volatility: 0.025,
                seed: 17
            )
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 32) {
                    ForEach(StyleExample.all) { example in
                        StyleExampleCard(
                            example: example,
                            candles: example.intraday ? Self.intradayCandles : Self.candles,
                            comparison: example.compares ? Self.comparisonSeries : []
                        )
                    }
                    ReplayCard(candles: Self.candles)
                    LiveActivityCard()
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
    /// Uses the 15-minute US-equities series instead of the daily one.
    var intraday = false
    var sessions: [TradingSession] = []
    /// Plots the demo's two other instruments over the chart.
    var compares = false

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
                id: "Glass price axis",
                summary: "Candles peek through the price axis, softly blurred, as they scroll underneath — best seen while panning, not in this static preview.",
                code: "CandlestickChart(candles)\n    .candleChartStyle(CandleChartStyle(priceAxisMaterial: .ultraThinMaterial))",
                style: CandleChartStyle(priceAxisMaterial: .ultraThinMaterial)
            ),
            StyleExample(
                id: "Session shading",
                summary: "Pre-market and after-hours are tinted so extended-hours candles read differently from the regular session. Describe your market's sessions; US equities are built in.",
                code: "CandlestickChart(candles)\n    .tradingSessions(TradingSession.usEquities)",
                intraday: true,
                sessions: TradingSession.usEquities
            ),
            StyleExample(
                id: "Comparison",
                summary: "Other instruments plotted over the chart. The axis switches to percent change from the first visible candle, so scrolling and zooming re-bases it. ALT starts part-way through.",
                code: "CandlestickChart(candles)\n    .comparing([\n        ComparisonSeries(name: \"IDX\", candles: index),\n        ComparisonSeries(name: \"ALT\", candles: alt),\n    ])",
                compares: true
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
    var comparison: [ComparisonSeries] = []

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
                .tradingSessions(example.sessions)
                .comparing(comparison)
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

/// Plays the daily series back one candle at a time with `ReplayController` (roadmap 9.4).
private struct ReplayCard: View {
    let candles: [Candle]
    @State private var replay = ReplayController()
    @State private var speed = 2.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Replay")
                .font(.headline)
            Text("Reveal the series one candle at a time, as if it were happening now. Start, then play, pause or step.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            CandlestickChart(candles)
                .headerVisible(false)
                .replay(replay)
                .frame(height: 260)

            HStack(spacing: 8) {
                Button(replay.isActive ? "Restart" : "Start") {
                    replay.begin(at: 60)
                    replay.play()
                }
                .buttonStyle(.borderedProminent)
                Button(replay.isPlaying ? "Pause" : "Play") {
                    if replay.isPlaying { replay.pause() } else { replay.play() }
                }
                .disabled(!replay.isActive || replay.isAtEnd)
                Button("Step") { replay.step() }
                    .disabled(!replay.isActive || replay.isAtEnd)
                Button("End") { replay.end() }
                    .disabled(!replay.isActive)
            }
            .buttonStyle(.bordered)

            HStack {
                Picker("Speed", selection: $speed) {
                    Text("1/s").tag(1.0)
                    Text("2/s").tag(2.0)
                    Text("5/s").tag(5.0)
                    Text("10/s").tag(10.0)
                }
                .pickerStyle(.segmented)
                .onChange(of: speed) { _, newValue in replay.candlesPerSecond = newValue }
            }

            Text(replay.isActive ? "Candle \(min(replay.position, candles.count)) of \(candles.count)" : "Not replaying")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text("let replay = ReplayController()\n\nCandlestickChart(candles)\n    .replay(replay)\n\nreplay.begin(at: 60)\nreplay.play()")
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
