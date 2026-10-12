#if os(iOS)
import SwiftUI

/// Draws the markers for `.eventMarkers(_:onSelect:)` as real SwiftUI buttons sitting just above
/// the time axis, so each is tappable and VoiceOver can read it.
///
/// Reads `state.revision`, like `DrawingsLayer`, so markers follow the candles as the chart pans.
/// Only markers for candles on (or just off) screen are created, and nearby ones are merged first
/// (`EventMarkerLayout.clusters`), so the number of views stays small however many events there are.
struct EventMarkersLayer: View {
    let state: CandleChartState
    let events: [ChartEvent]
    let style: CandleChartStyle
    let onSelect: ((ChartEventCluster) -> Void)?

    private static let diameter: CGFloat = 20

    var body: some View {
        let _ = state.revision
        if let frame = state.currentFrame, !events.isEmpty, !frame.candles.isEmpty {
            let lower = max(0, frame.visible.lowerBound - 2)
            let upper = min(frame.candles.count, frame.visible.upperBound + 2)
            let clusters = EventMarkerLayout.clusters(
                events: events,
                candles: frame.candles,
                visible: lower..<upper,
                interval: frame.interval,
                spacing: frame.viewport.spacing,
                minimumGap: Double(Self.diameter) + 2
            )
            let plot = frame.layout.plot
            // Sits on the bottom edge of the whole pane stack, just above the time axis.
            let y = frame.layout.timeAxis.minY - Self.diameter / 2 - 2
            ZStack(alignment: .topLeading) {
                ForEach(clusters) { cluster in
                    marker(for: cluster)
                        .position(x: frame.centerX(ofCandle: cluster.candleIndex), y: y)
                        // Markers scrolled under the price axis shouldn't poke out over it.
                        .opacity(frame.centerX(ofCandle: cluster.candleIndex) <= plot.maxX ? 1 : 0)
                }
            }
            .frame(width: plot.maxX, height: frame.layout.timeAxis.minY, alignment: .topLeading)
            .clipped()
        }
    }

    @ViewBuilder
    private func marker(for cluster: ChartEventCluster) -> some View {
        let primary = cluster.primary
        Button {
            onSelect?(cluster)
        } label: {
            ZStack {
                Circle().fill(Self.color(for: primary.kind))
                if cluster.events.count > 1 {
                    Text("\(cluster.events.count)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                } else {
                    Text(primary.kind.symbol)
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: Self.diameter, height: Self.diameter)
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            // A larger touch target than the glyph, still centred on it.
            .frame(width: 32, height: 32)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Self.label(for: cluster)))
    }

    static func color(for kind: ChartEvent.Kind) -> Color {
        switch kind {
        case .earnings: return .blue
        case .dividend: return .green
        case .split: return .purple
        case .news: return .orange
        case .custom: return .gray
        }
    }

    static func label(for cluster: ChartEventCluster) -> String {
        if cluster.events.count == 1 {
            return "\(cluster.primary.kind.spokenName): \(cluster.primary.title)"
        }
        return "\(cluster.events.count) events, starting with \(cluster.primary.title)"
    }
}
#endif
