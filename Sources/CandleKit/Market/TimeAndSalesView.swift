#if os(iOS)
import SwiftUI

/// A time-and-sales tape: the latest trades, newest at the top, colored by who was the aggressor.
///
/// ```swift
/// TimeAndSalesView(tape.trades)
///     .largeTradeSize(5)
/// ```
///
/// Pass trades oldest first (the order `TradeTape.trades` uses). Only the newest `maximumRows`
/// are drawn. The view needs no chart and can be placed anywhere.
public struct TimeAndSalesView: View {
    private let trades: [MarketTrade]
    private var rowLimit = 50
    private var smallestSize = 0.0
    private var largeSize: Double?
    private var style = MarketDataStyle.standard
    private var showsHeader = true

    public init(_ trades: [MarketTrade]) {
        self.trades = trades
    }

    public var body: some View {
        Group {
            if trades.isEmpty {
                ContentUnavailableView("No trades yet", systemImage: "clock")
            } else {
                tape
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var tape: some View {
        // Newest first. Lazy, so this touches only the rows drawn plus any filtered out before them.
        let minimum = smallestSize
        let rows = Array(trades.reversed().lazy.filter { $0.size >= minimum }.prefix(rowLimit))
        return VStack(spacing: 0) {
            if showsHeader {
                TradeHeader()
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { trade in
                        TradeRow(trade: trade, style: style, isLarge: isLarge(trade))
                    }
                }
            }
        }
    }

    private func isLarge(_ trade: MarketTrade) -> Bool {
        guard let largeSize else { return false }
        return trade.size >= largeSize
    }
}

// MARK: - Modifiers

extension TimeAndSalesView {
    /// Rows drawn. Default 50. Values below 1 are treated as 1.
    public func maximumRows(_ count: Int) -> TimeAndSalesView {
        var copy = self
        copy.rowLimit = max(1, count)
        return copy
    }

    /// Hides trades smaller than this. Default 0 (show everything).
    public func minimumSize(_ size: Double) -> TimeAndSalesView {
        var copy = self
        copy.smallestSize = size
        return copy
    }

    /// Trades at least this large get a highlighted row. `nil` (default) highlights nothing.
    public func largeTradeSize(_ size: Double?) -> TimeAndSalesView {
        var copy = self
        copy.largeSize = size
        return copy
    }

    /// Colors and number formatting.
    public func marketDataStyle(_ style: MarketDataStyle) -> TimeAndSalesView {
        var copy = self
        copy.style = style
        return copy
    }

    /// Shows or hides the column headers ("Time", "Price", "Size"). Shown by default.
    public func headerVisible(_ visible: Bool) -> TimeAndSalesView {
        var copy = self
        copy.showsHeader = visible
        return copy
    }
}

// MARK: - Rows

private struct TradeHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Time").frame(maxWidth: .infinity, alignment: .leading)
            Text("Price").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Size").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }
}

private struct TradeRow: View {
    let trade: MarketTrade
    let style: MarketDataStyle
    let isLarge: Bool
    @ScaledMetric private var rowHeight: CGFloat

    init(trade: MarketTrade, style: MarketDataStyle, isLarge: Bool) {
        self.trade = trade
        self.style = style
        self.isLarge = isLarge
        _rowHeight = ScaledMetric(wrappedValue: style.rowHeight, relativeTo: .caption)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(timeText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(style.priceText(trade.price))
                .foregroundStyle(sideColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(style.sizeText(trade.size))
                .fontWeight(isLarge ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: rowHeight)
        .background(isLarge ? sideColor.opacity(0.15) : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
    }

    private var timeText: String {
        trade.time.formatted(date: .omitted, time: .standard)
    }

    private var sideColor: Color {
        switch trade.side {
        case .buy: return style.bidColor
        case .sell: return style.askColor
        case .unknown: return .primary
        }
    }

    private var label: String {
        let side: String
        switch trade.side {
        case .buy: side = "Buy"
        case .sell: side = "Sell"
        case .unknown: side = "Trade"
        }
        return "\(side) \(style.sizeText(trade.size)) at \(style.priceText(trade.price)), \(timeText)"
    }
}

#Preview {
    TimeAndSalesView(MarketSampleData.trades(count: 60))
        .largeTradeSize(1.8)
        .padding()
}
#endif
