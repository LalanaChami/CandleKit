#if os(iOS)
import SwiftUI

/// The app's orders and position as labelled horizontal lines. A draggable line moves by its tag;
/// the chart reports the new price and leaves the decision to the app.
///
/// Sits after `ChartGestureView` in the chart's ZStack so a draggable tag receives its touch first.
/// Everything else here lets touches through, so panning is unaffected.
struct OrderLinesLayer: View {
    let state: CandleChartState
    let lines: [ChartOrderLine]
    let style: MarketDataStyle
    let tick: Double?
    let onMove: ((String, Double) -> Void)?

    /// The line being dragged and where it currently is. `nil` when nothing is being dragged.
    @State private var drag: ActiveDrag?

    private struct ActiveDrag {
        var id: String
        var price: Double
    }

    /// How far the tag's centre sits from the right edge of the plot.
    private static let tagInset: CGFloat = 70

    var body: some View {
        let _ = state.revision
        if let frame = state.currentFrame {
            let plot = frame.layout.plot
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    var clipped = context
                    clipped.clip(to: Path(plot))
                    for line in lines {
                        Self.stroke(line, at: displayPrice(of: line), color: color(for: line.kind), frame: frame, in: &clipped)
                    }
                }
                .allowsHitTesting(false)

                ForEach(lines) { line in
                    let price = displayPrice(of: line)
                    let y = frame.y(forPrice: price)
                    if price.isFinite, y >= plot.minY, y <= plot.maxY {
                        tag(for: line, price: price, frame: frame)
                            .position(x: plot.maxX - Self.tagInset, y: y)
                    }
                }
            }
            .frame(width: plot.maxX, height: plot.maxY, alignment: .topLeading)
        }
    }

    private func displayPrice(of line: ChartOrderLine) -> Double {
        if let drag, drag.id == line.id { return drag.price }
        return line.price
    }

    private func color(for kind: ChartOrderLine.Kind) -> Color {
        switch kind {
        case .buy, .takeProfit: return style.bidColor
        case .sell, .stopLoss: return style.askColor
        case .position: return .accentColor
        }
    }

    private static func stroke(
        _ line: ChartOrderLine, at price: Double, color: Color, frame: ChartFrame, in context: inout GraphicsContext
    ) {
        guard price.isFinite else { return }
        let plot = frame.layout.plot
        let y = frame.y(forPrice: price)
        guard y >= plot.minY, y <= plot.maxY else { return }
        var path = Path()
        path.move(to: CGPoint(x: plot.minX, y: y))
        path.addLine(to: CGPoint(x: plot.maxX, y: y))
        // A position is a fact, drawn solid; orders are intentions, drawn dashed.
        let stroke = line.kind == .position
            ? StrokeStyle(lineWidth: 1)
            : StrokeStyle(lineWidth: 1, dash: [6, 3])
        context.stroke(path, with: .color(color.opacity(0.9)), style: stroke)
    }

    private func tag(for line: ChartOrderLine, price: Double, frame: ChartFrame) -> some View {
        let canDrag = line.isDraggable && onMove != nil
        // Measured from where the line rests, not from where the drag has moved it, so the
        // translation isn't applied twice.
        let restingY = frame.y(forPrice: line.price)
        let dragGesture = DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let raw = frame.price(atY: restingY + value.translation.height)
                drag = ActiveDrag(id: line.id, price: OrderLineMath.snapped(raw, tick: tick))
            }
            .onEnded { _ in
                if let drag, drag.id == line.id {
                    onMove?(drag.id, drag.price)
                }
                drag = nil
            }

        return Text("\(line.label)  \(style.priceText(price))")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color(for: line.kind), in: Capsule())
            // A taller touch target than the capsule, still centred on the line.
            .frame(minHeight: 32)
            .contentShape(Rectangle())
            .gesture(dragGesture, including: canDrag ? .all : .none)
            .allowsHitTesting(canDrag)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(line.label) at \(style.priceText(price))"))
            .accessibilityAdjustableAction { direction in
                guard canDrag else { return }
                let step = tick ?? abs(line.price) * 0.001
                switch direction {
                case .increment: onMove?(line.id, OrderLineMath.snapped(line.price + step, tick: tick))
                case .decrement: onMove?(line.id, OrderLineMath.snapped(line.price - step, tick: tick))
                @unknown default: break
                }
            }
    }
}
#endif
