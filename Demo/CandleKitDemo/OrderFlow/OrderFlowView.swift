import CandleKit
import SwiftUI

/// The market data tools (roadmap phase 12) on one screen: depth chart, order book ladder, time
/// and sales, and the three chart overlays. Uses only CandleKit's public API.
struct OrderFlowView: View {
    @State private var feed = OrderFlowFeed()
    @State private var live = false
    @State private var grouping: Double?
    @State private var selectedPrice: Double?
    @State private var orders: [ChartOrderLine] = [
        ChartOrderLine(id: "buy-1", price: 99.75, kind: .buy, label: "Buy 1", isDraggable: true),
        ChartOrderLine(id: "stop-1", price: 99.5, kind: .stopLoss, label: "Stop", isDraggable: true),
    ]

    /// Quiet candles that end at 100, so they sit under the simulated book (which is centred on 100).
    private static let sampleCandles: [Candle] = {
        let walk = CandleSampleData.randomWalk(count: 200, interval: 60, startPrice: 100, volatility: 0.001)
        let shift = SimulatedOrderFlow.midPrice - (walk.last?.close ?? SimulatedOrderFlow.midPrice)
        return walk.map { candle in
            Candle(
                time: candle.time, open: candle.open + shift, high: candle.high + shift,
                low: candle.low + shift, close: candle.close + shift, volume: candle.volume
            )
        }
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                section("Depth") {
                    DepthChartView(feed.store.book)
                        .depthWindow(live ? 0.001 : 0.02)
                        .frame(height: 160)
                }
                section("Order book") {
                    ladder
                }
                section("Time and sales") {
                    TimeAndSalesView(feed.tape.trades)
                        .maximumRows(30)
                        .largeTradeSize(live ? 0.5 : 2.5)
                        .frame(height: 320)
                }
                if !live {
                    section("On the chart") {
                        overlayChart
                    }
                }
            }
            .padding()
        }
        .task(id: live) {
            grouping = nil
            selectedPrice = nil
            await feed.run(live: live, productID: "BTC-USD")
        }
    }

    // MARK: Sections

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Live (Coinbase BTC-USD)", isOn: $live)
            HStack {
                Text(feed.status.rawValue)
                Spacer()
                Text(imbalanceText)
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var imbalanceText: String {
        guard let imbalance = OrderBookMath.imbalance(of: feed.store.book, depth: 10) else {
            return "Imbalance —"
        }
        let percent = imbalance.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))
        return "Imbalance (top 10) \(percent)"
    }

    private var groupingOptions: [Double] {
        live ? [0.5, 1, 5, 10] : [0.1, 0.5]
    }

    private var ladder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Grouping", selection: $grouping) {
                Text("None").tag(Double?.none)
                ForEach(groupingOptions, id: \.self) { option in
                    Text(option.formatted()).tag(Double?.some(option))
                }
            }
            .pickerStyle(.segmented)

            OrderBookView(feed.store.book)
                .rowsPerSide(10)
                .priceGrouping(grouping)
                .onSelectPrice { price in selectedPrice = price }

            Text(selectedText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedText: String {
        guard let selectedPrice else { return "Tap a row to pick its price." }
        return "Selected price: \(selectedPrice.formatted())"
    }

    private var overlayChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            CandlestickChart(Self.sampleCandles)
                .volumeVisible(false)
                .quoteLines(bid: feed.store.book.bestBid?.price, ask: feed.store.book.bestAsk?.price)
                .depthOverlay(feed.store.book)
                .orderLines(orders, tick: SimulatedOrderFlow.tick) { id, newPrice in
                    // The app decides what a drag means. Here it just moves the line.
                    if let index = orders.firstIndex(where: { $0.id == id }) {
                        orders[index].price = newPrice
                    }
                }
                .frame(height: 280)

            Text("Dashed lines mark the bid and ask, bars on the left show book depth, and the order tags can be dragged.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    OrderFlowView()
}
