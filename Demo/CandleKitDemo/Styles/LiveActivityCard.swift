import ActivityKit
import CandleKit
import SwiftUI

/// Starts, ticks and ends a Live Activity with simulated prices (roadmap 8.2).
///
/// A real app updates an activity from a push (`pushType: .token`) because the app is usually
/// suspended when prices move. This demo ticks from a foreground `Task` so it needs no server.
@MainActor @Observable
final class DemoLiveActivityController {
    private(set) var isRunning = false
    private(set) var message = "Not running"
    private var activity: Activity<PriceActivityAttributes>?
    private var task: Task<Void, Never>?

    func start() {
        guard !isRunning else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "Live Activities are turned off for this app in Settings."
            return
        }
        var closes = CandleSampleData.randomWalk(count: 30, startPrice: 64_000, volatility: 0.002, seed: 5).map(\.close)
        do {
            activity = try Activity.request(
                attributes: PriceActivityAttributes(symbol: "BTC-USD"),
                content: .init(state: Self.state(closes), staleDate: nil)
            )
        } catch {
            message = "Could not start: \(error.localizedDescription)"
            return
        }
        isRunning = true
        message = "Running: lock the device or go Home to see it"
        task = Task { [weak self] in
            var generator = SystemRandomNumberGenerator()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let self, let activity = self.activity else { return }
                let last = closes.last ?? 64_000
                closes.append(last * (1 + Double.random(in: -0.002...0.002, using: &generator)))
                closes.removeFirst()
                await activity.update(.init(state: Self.state(closes), staleDate: nil))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        let current = activity
        activity = nil
        isRunning = false
        message = "Not running"
        Task { await current?.end(nil, dismissalPolicy: .immediate) }
    }

    private static func state(_ closes: [Double]) -> PriceActivityAttributes.ContentState {
        let first = closes.first ?? 0
        let last = closes.last ?? 0
        let change = first == 0 ? 0 : (last - first) / first * 100
        return .init(price: last, changePercent: change, closes: closes)
    }
}

struct LiveActivityCard: View {
    @State private var controller = DemoLiveActivityController()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Activity").font(.headline)
            Text("A ticking price and sparkline on the Lock Screen and in the Dynamic Island.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button(controller.isRunning ? "Running" : "Start") { controller.start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isRunning)
                Button("End") { controller.stop() }
                    .buttonStyle(.bordered)
                    .disabled(!controller.isRunning)
            }
            Text(controller.message).font(.caption).foregroundStyle(.secondary)
        }
    }
}
