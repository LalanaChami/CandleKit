import CandleKit
import QuartzCore
import SwiftUI

enum DatasetSize: Int, CaseIterable, Identifiable {
    case oneThousand = 1_000
    case tenThousand = 10_000
    case oneHundredThousand = 100_000

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .oneThousand: return "1K"
        case .tenThousand: return "10K"
        case .oneHundredThousand: return "100K"
        }
    }
}

struct PerformanceView: View {
    @State private var size: DatasetSize = .tenThousand
    @State private var candles: [Candle] = []
    @State private var chartState = CandleChartState(
        candleSpacing: 3,
        zoomLimits: ZoomLimits(minimumSpacing: 1, maximumSpacing: 48)
    )

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Candles", selection: $size) {
                    ForEach(DatasetSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    if candles.count == size.rawValue {
                        CandlestickChart(candles, state: chartState)
                            .indicators([.sma(50), .ema(200, color: .blue)])
                            .overlay(alignment: .bottomLeading) {
                                RefreshRateMeter()
                                    .padding(.leading, 8)
                                    .padding(.bottom, 32)
                            }
                    } else {
                        ProgressView("Generating \(size.label) candles")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)

                PerformanceCaptureBar(scenario: "Performance tab", candleCount: candles.count)

                Text("Fling the chart and pinch all the way out. The meter counts display refreshes, which is a quick signal only. Use Capture to record a phase-by-phase breakdown you can paste into docs/PERFORMANCE.md, and Instruments' Animation Hitches template on a Release build for the full picture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Performance")
        }
        .task(id: size) {
            let count = size.rawValue
            let generated = await Task.detached(priority: .userInitiated) {
                CandleSampleData.randomWalk(count: count, interval: 60, startPrice: 100, volatility: 0.002, seed: UInt64(count))
            }.value
            guard !Task.isCancelled else { return }
            candles = generated
        }
    }
}

/// Shows how many frames the display drew over the last half second.
private struct RefreshRateMeter: View {
    @State private var counter = RefreshRateCounter()

    var body: some View {
        Text("\(counter.framesPerSecond) fps")
            .font(.caption.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .onAppear { counter.start() }
            .onDisappear { counter.stop() }
    }
}

@MainActor
@Observable
private final class RefreshRateCounter {
    private(set) var framesPerSecond = 0

    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var target: DisplayLinkTarget?
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var windowStart: CFTimeInterval = 0

    func start() {
        guard displayLink == nil else { return }
        let target = DisplayLinkTarget { [weak self] link in
            self?.tick(link)
        }
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.target = target
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        target = nil
        frames = 0
        windowStart = 0
    }

    private func tick(_ link: CADisplayLink) {
        if windowStart == 0 {
            windowStart = link.timestamp
        }
        frames += 1
        let elapsed = link.timestamp - windowStart
        if elapsed >= 0.5 {
            framesPerSecond = Int((Double(frames) / elapsed).rounded())
            frames = 0
            windowStart = link.timestamp
        }
    }
}

/// CADisplayLink needs an Objective-C target; this forwards to a closure.
@MainActor
private final class DisplayLinkTarget: NSObject {
    private let onFrame: @MainActor (CADisplayLink) -> Void

    init(onFrame: @escaping @MainActor (CADisplayLink) -> Void) {
        self.onFrame = onFrame
    }

    @objc func step(_ link: CADisplayLink) {
        onFrame(link)
    }
}

#Preview {
    PerformanceView()
}
