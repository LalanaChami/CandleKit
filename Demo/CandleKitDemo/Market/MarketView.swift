import CandleKit
import SwiftUI

struct MarketView: View {
    @State private var feed = MarketFeed()
    @State private var chartState = CandleChartState(candleSpacing: 9)

    @State private var source: DataSourceKind = .coinbase
    @State private var product: Product = .bitcoin
    @State private var timeframe: Timeframe = .fiveMinutes
    @State private var attempt = 0

    @State private var showsSMA = true
    @State private var showsEMA = true
    @State private var showsVolume = true

    var body: some View {
        let configuration = FeedConfiguration(source: source, product: product, timeframe: timeframe, attempt: attempt)

        NavigationStack {
            VStack(spacing: 12) {
                Picker("Timeframe", selection: $timeframe) {
                    ForEach(Timeframe.allCases) { timeframe in
                        Text(timeframe.label).tag(timeframe)
                    }
                }
                .pickerStyle(.segmented)

                chart
                    .frame(maxHeight: .infinity)

                footer
            }
            .padding()
            .navigationTitle(product.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FeedStatusBadge(status: feed.status, source: source)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    optionsMenu
                }
            }
        }
        .task(id: configuration) {
            await feed.run(configuration)
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch feed.status {
        case let .failed(message) where feed.candles.isEmpty:
            ContentUnavailableView {
                Label("Couldn't load \(product.id)", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { attempt += 1 }
                    .buttonStyle(.borderedProminent)
                Button("Use simulated data") { source = .simulated }
            }
        case .loading where feed.candles.isEmpty:
            ProgressView("Loading \(product.id)")
        default:
            CandlestickChart(feed.candles, state: chartState)
                .indicators(indicators)
                .volumeVisible(showsVolume)
                .onReachOldestCandle { feed.loadOlder() }
                .overlay(alignment: .leading) {
                    if feed.isLoadingHistory {
                        ProgressView()
                            .padding(10)
                            .background(.regularMaterial, in: Circle())
                            .padding(.leading, 8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // Clears the price and time axes.
                    JumpToLatestButton(state: chartState)
                        .padding(.trailing, 72)
                        .padding(.bottom, 32)
                }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Drag to scroll, pinch to zoom, long-press to inspect, double-tap to reset.")
            Text(source == .coinbase ? "Market data from the Coinbase Exchange public API." : "Simulated prices, not real market data.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Data", selection: $source) {
                ForEach(DataSourceKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            Picker("Market", selection: $product) {
                ForEach(Product.all) { product in
                    Text("\(product.name) (\(product.id))").tag(product)
                }
            }
            Section("Overlays") {
                Toggle("SMA 20", isOn: $showsSMA)
                Toggle("EMA 50", isOn: $showsEMA)
                Toggle("Volume", isOn: $showsVolume)
            }
            Button("Reset zoom", systemImage: "arrow.counterclockwise") {
                chartState.resetZoom()
            }
        } label: {
            Label("Chart options", systemImage: "slider.horizontal.3")
        }
    }

    private var indicators: [ChartIndicator] {
        var result: [ChartIndicator] = []
        if showsSMA { result.append(.sma(20)) }
        if showsEMA { result.append(.ema(50, color: .blue)) }
        return result
    }
}

/// Lives in its own view so that only this button, not the whole screen, re-renders while the chart scrolls.
struct JumpToLatestButton: View {
    let state: CandleChartState

    var body: some View {
        if !state.isFollowingLatest {
            Button {
                state.scrollToLatest()
            } label: {
                Label("Latest", systemImage: "arrow.right.to.line")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }
}

struct FeedStatusBadge: View {
    let status: MarketFeed.Status
    let source: DataSourceKind

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch status {
        case .loading: return "Connecting"
        case .streaming: return source == .coinbase ? "Live" : "Simulated"
        case .reconnecting: return "Reconnecting"
        case .failed: return "Offline"
        }
    }

    private var color: Color {
        switch status {
        case .loading, .reconnecting: return .orange
        case .streaming: return source == .coinbase ? .green : .blue
        case .failed: return .red
        }
    }
}

#Preview {
    MarketView()
}
