import ActivityKit
import SwiftUI
import WidgetKit
import CandleKitWidgets

/// Lock Screen banner and Dynamic Island for a watched symbol (roadmap 8.2).
///
/// Everything drawn here is a few text views plus one `SparklineView`, because an activity has a small
/// update budget and a short-lived process. There is no `CandlestickChart` and no state object.
struct PriceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PriceActivityAttributes.self) { context in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.symbol).font(.caption.weight(.semibold))
                    PriceText(state: context.state, font: .title2.weight(.semibold))
                }
                SparklineView(context.state.closes, color: tint(context.state))
                    .frame(height: 40)
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.4))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.symbol).font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PriceText(state: context.state, font: .headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SparklineView(context.state.closes, color: tint(context.state))
                        .frame(height: 36)
                }
            } compactLeading: {
                Text(context.attributes.symbol.prefix(3)).font(.caption2.weight(.semibold))
            } compactTrailing: {
                Text(context.state.price, format: .number.precision(.fractionLength(0)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(tint(context.state))
            } minimal: {
                Image(systemName: context.state.changePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .foregroundStyle(tint(context.state))
            }
        }
    }

    private func tint(_ state: PriceActivityAttributes.ContentState) -> Color {
        state.changePercent >= 0 ? .green : .red
    }
}

private struct PriceText: View {
    let state: PriceActivityAttributes.ContentState
    let font: Font

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(state.price, format: .number.precision(.fractionLength(2)))
                .font(font.monospacedDigit())
            Text("\(state.changePercent >= 0 ? "+" : "")\(state.changePercent.formatted(.number.precision(.fractionLength(2))))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(state.changePercent >= 0 ? .green : .red)
        }
    }
}
