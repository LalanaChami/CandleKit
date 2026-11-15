#if os(iOS)
import SwiftUI

/// A level 2 order book ladder: asks above, the spread in the middle, bids below.
///
/// ```swift
/// OrderBookView(book)
///     .rowsPerSide(10)
///     .priceGrouping(0.5)
///     .onSelectPrice { price in orderPrice = price }
/// ```
///
/// Each row shows price, size and the running total, with a bar whose length is the running total
/// relative to the deepest row shown. Rows are a fixed count, so a very deep book costs no more
/// to draw than a shallow one. The view needs no chart and can be placed anywhere.
public struct OrderBookView: View {
    private let book: OrderBook
    private var rows = 10
    private var tick: Double?
    private var style = MarketDataStyle.standard
    private var showsHeader = true
    private var selectionHandler: ((Double) -> Void)?

    public init(_ book: OrderBook) {
        self.book = book
    }

    public var body: some View {
        Group {
            if book.isEmpty {
                ContentUnavailableView("No order book", systemImage: "list.bullet.rectangle")
            } else {
                ladderRows
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var ladderRows: some View {
        let ladder = OrderBookLadder(book: book, rowsPerSide: rows, tick: tick)
        // Best ask sits directly above the spread, so asks are listed farthest first.
        let asks = Array(ladder.asks.reversed())
        return VStack(spacing: 0) {
            if showsHeader {
                OrderBookHeader()
            }
            ForEach(asks) { row in
                rowView(row)
            }
            OrderBookSpreadRow(book: book, style: style)
            ForEach(ladder.bids) { row in
                rowView(row)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: OrderBookLadder.Row) -> some View {
        if let selectionHandler {
            Button {
                selectionHandler(row.price)
            } label: {
                OrderBookRow(row: row, style: style)
            }
            .buttonStyle(.plain)
        } else {
            OrderBookRow(row: row, style: style)
        }
    }
}

// MARK: - Modifiers

extension OrderBookView {
    /// Rows shown on each side. Default 10. Values below 1 are treated as 1.
    public func rowsPerSide(_ count: Int) -> OrderBookView {
        var copy = self
        copy.rows = max(1, count)
        return copy
    }

    /// Merges prices into buckets this wide. `nil` (the default) shows every level.
    public func priceGrouping(_ tick: Double?) -> OrderBookView {
        var copy = self
        copy.tick = tick
        return copy
    }

    /// Colors and number formatting.
    public func marketDataStyle(_ style: MarketDataStyle) -> OrderBookView {
        var copy = self
        copy.style = style
        return copy
    }

    /// Shows or hides the column headers ("Price", "Size", "Total"). Shown by default.
    public func headerVisible(_ visible: Bool) -> OrderBookView {
        var copy = self
        copy.showsHeader = visible
        return copy
    }

    /// Called with a row's price when the person taps it, for example to prefill an order ticket.
    public func onSelectPrice(_ action: @escaping (Double) -> Void) -> OrderBookView {
        var copy = self
        copy.selectionHandler = action
        return copy
    }
}

// MARK: - Rows

private struct OrderBookHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Price").frame(maxWidth: .infinity, alignment: .leading)
            Text("Size").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Total").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }
}

private struct OrderBookRow: View {
    let row: OrderBookLadder.Row
    let style: MarketDataStyle
    @ScaledMetric private var rowHeight: CGFloat

    init(row: OrderBookLadder.Row, style: MarketDataStyle) {
        self.row = row
        self.style = style
        _rowHeight = ScaledMetric(wrappedValue: style.rowHeight, relativeTo: .caption)
    }

    var body: some View {
        let color = style.color(for: row.side)
        HStack(spacing: 8) {
            Text(style.priceText(row.price))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(style.sizeText(row.size))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(style.sizeText(row.cumulativeSize))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: rowHeight)
        .background(alignment: .trailing) {
            Rectangle()
                .fill(color.opacity(style.depthBarOpacity))
                .scaleEffect(x: CGFloat(row.depthFraction), y: 1, anchor: .trailing)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
    }

    private var label: String {
        let side = row.side == .bid ? "Bid" : "Ask"
        return "\(side) \(style.priceText(row.price)), size \(style.sizeText(row.size)), total \(style.sizeText(row.cumulativeSize))"
    }
}

private struct OrderBookSpreadRow: View {
    let book: OrderBook
    let style: MarketDataStyle

    var body: some View {
        HStack(spacing: 8) {
            Text(book.isCrossed ? "Crossed" : "Spread")
            Text(spreadText)
            Spacer(minLength: 8)
            Text(midText)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(book.isCrossed ? Color.orange : Color.secondary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var spreadText: String {
        guard let spread = book.spread, let points = book.spreadBasisPoints else { return "—" }
        let digits = style.priceFractionDigits ?? PriceScale.suggestedFractionDigits(forPrice: book.midPrice ?? spread)
        return "\(ChartFormat.price(spread, digits: digits)) (\(ChartFormat.price(points, digits: 2)) bps)"
    }

    private var midText: String {
        guard let mid = book.midPrice else { return "" }
        return "Mid \(style.priceText(mid))"
    }
}

#Preview {
    OrderBookView(MarketSampleData.orderBook())
        .rowsPerSide(8)
        .padding()
}
#endif
