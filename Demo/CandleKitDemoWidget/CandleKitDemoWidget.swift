import SwiftUI
import WidgetKit
import CandleKitCore
import CandleKitWidgets

/// One snapshot of what the widget shows. A real app builds this from its own data layer.
struct ChartEntry: TimelineEntry {
    let date: Date
    let symbol: String
    let candles: [Candle]
}

/// Feeds the widget simulated BTC candles so the demo needs no network or App Group.
///
/// In a real app the host app (or a background refresh) writes recent candles somewhere the extension
/// can read, usually a file in an App Group container, and `timeline(in:completion:)` loads them.
/// WidgetKit gives the extension a small memory budget, so store and load a few hundred candles at most.
struct ChartProvider: TimelineProvider {
    private func entry(at date: Date) -> ChartEntry {
        // Seed changes every 15 minutes so a reload visibly moves the chart.
        let seed = UInt64(date.timeIntervalSince1970 / 900)
        let candles = CandleSampleData.randomWalk(count: 240, startPrice: 64_000, volatility: 0.004, seed: seed)
        return ChartEntry(date: date, symbol: "BTC-USD", candles: candles)
    }

    func placeholder(in context: Context) -> ChartEntry { entry(at: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (ChartEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChartEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [entry(at: now)], policy: .after(now.addingTimeInterval(900))))
    }
}

struct ChartWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ChartEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.symbol).font(.caption.weight(.semibold))
                Spacer()
                if let last = entry.candles.last {
                    Text(last.close, format: .number.precision(.fractionLength(2)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            WidgetCandleChart(
                entry.candles,
                mode: family == .systemSmall ? .line : .candles,
                maxCandles: family == .systemLarge ? 60 : 36
            )
        }
        .padding(2)
    }
}

struct CandleKitDemoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CandleKitDemoWidget", provider: ChartProvider()) { entry in
            ChartWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Price chart")
        .description("A small candlestick or line chart.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct CandleKitDemoWidgetBundle: WidgetBundle {
    var body: some Widget {
        CandleKitDemoWidget()
        PriceLiveActivity()
    }
}
