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
    /// Only the id is kept. `Activity` isn't `Sendable`, so each ActivityKit call below looks the activity
    /// up again inside its own function instead of passing one across isolation boundaries.
    private var activityID: String?
    private var task: Task<Void, Never>?

    func start() {
        guard !isRunning else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "Live Activities are turned off for this app in Settings."
            return
        }
        let initial = CandleSampleData.randomWalk(count: 30, startPrice: 64_000, volatility: 0.002, seed: 5).map(\.close)
        do {
            let started = try Activity.request(
                attributes: PriceActivityAttributes(symbol: "BTC-USD"),
                content: .init(state: Self.state(initial), staleDate: nil)
            )
            activityID = started.id
        } catch {
            message = "Could not start: \(error.localizedDescription)"
            return
        }
        isRunning = true
        message = "Running: lock the device or go Home to see it"
        guard let id = activityID else { return }
        task = Task {
            var closes = initial
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                let last = closes.last ?? 64_000
                closes.append(last * (1 + Double.random(in: -0.002...0.002)))
                closes.removeFirst()
                await Self.push(Self.state(closes), to: id)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        let id = activityID
        activityID = nil
        isRunning = false
        message = "Not running"
        if let id {
            Task { await Self.finish(id: id) }
        }
    }

    private nonisolated static func push(_ state: PriceActivityAttributes.ContentState, to id: String) async {
        guard let activity = Activity<PriceActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(.init(state: state, staleDate: nil))
    }

    private nonisolated static func finish(id: String) async {
        guard let activity = Activity<PriceActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private nonisolated static func state(_ closes: [Double]) -> PriceActivityAttributes.ContentState {
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
