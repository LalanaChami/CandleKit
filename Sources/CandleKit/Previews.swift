#if os(iOS) && DEBUG
import SwiftUI

/// Streams fake ticks and loads older history on demand, exercising every data path the chart handles.
private struct LiveChartDemo: View {
    private static let interval: TimeInterval = 300

    @State private var candles = CandleSampleData.randomWalk(count: 400, interval: LiveChartDemo.interval, startPrice: 182, seed: 7)
    @State private var chartState = CandleChartState()
    @State private var isLoadingHistory = false
    @State private var inspected: Candle?

    var body: some View {
        NavigationStack {
            CandlestickChart(candles, state: chartState)
                .indicators([.sma(20), .ema(50, color: .blue)])
                .onReachOldestCandle { loadHistory() }
                .onCrosshairChange { inspected = $0 }
                .padding(.horizontal)
                .navigationTitle("DEMO")
                .toolbar {
                    if !chartState.isFollowingLatest {
                        Button("Jump to latest", systemImage: "arrow.right.to.line") {
                            chartState.scrollToLatest()
                        }
                    }
                }
                .task { await streamTicks() }
        }
    }

    private func streamTicks() async {
        var tick = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(400))
            guard var last = candles.last else { continue }
            tick += 1
            if tick.isMultiple(of: 12) {
                candles.append(Candle(
                    time: last.time.addingTimeInterval(Self.interval),
                    open: last.close,
                    high: last.close,
                    low: last.close,
                    close: last.close
                ))
            } else {
                let close = max(1, last.close * (1 + Double.random(in: -0.002...0.002)))
                last.close = close
                last.high = max(last.high, close)
                last.low = min(last.low, close)
                last.volume += Double.random(in: 50...400)
                candles[candles.count - 1] = last
            }
        }
    }

    private func loadHistory() {
        guard !isLoadingHistory, let first = candles.first else { return }
        isLoadingHistory = true
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            let count = 300
            let older = CandleSampleData.randomWalk(
                count: count,
                start: first.time.addingTimeInterval(-Self.interval * Double(count)),
                interval: Self.interval,
                startPrice: first.open,
                seed: UInt64(candles.count)
            )
            // Rescale so the older series ends where the loaded one begins.
            let factor = first.open / (older.last?.close ?? first.open)
            let scaled = older.map { candle in
                Candle(
                    time: candle.time,
                    open: candle.open * factor,
                    high: candle.high * factor,
                    low: candle.low * factor,
                    close: candle.close * factor,
                    volume: candle.volume
                )
            }
            candles.insert(contentsOf: scaled, at: 0)
            isLoadingHistory = false
        }
    }
}

#Preview("Live data") {
    LiveChartDemo()
}

#Preview("Daily, red-up, hollow") {
    CandlestickChart(CandleSampleData.randomWalk(count: 250, interval: 86_400, startPrice: 3_200, volatility: 0.015, seed: 3))
        .candleChartStyle(CandleChartStyle(upColor: .red, downColor: .green, hollowUpCandles: true))
        .indicators([.sma(50)])
        .frame(height: 320)
        .padding()
}
#endif
