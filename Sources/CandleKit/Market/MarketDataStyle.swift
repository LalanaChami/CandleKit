#if os(iOS)
import SwiftUI

/// Colors and number formatting shared by the order book, depth chart and time-and-sales views,
/// and by the market overlays on the chart.
public struct MarketDataStyle: Sendable {
    /// Bids and buys. Green by default, like the chart's rising candles.
    public var bidColor: Color
    /// Asks and sells. Red by default, like the chart's falling candles.
    public var askColor: Color
    /// Opacity of the size bars drawn behind ladder rows.
    public var depthBarOpacity: Double
    /// Decimal places for prices. `nil` picks a value from the price, like the chart does.
    public var priceFractionDigits: Int?
    /// Decimal places for sizes.
    public var sizeFractionDigits: Int
    /// Height of one ladder or tape row, in points, before Dynamic Type scaling.
    public var rowHeight: CGFloat

    public init(
        bidColor: Color = .green,
        askColor: Color = .red,
        depthBarOpacity: Double = 0.18,
        priceFractionDigits: Int? = nil,
        sizeFractionDigits: Int = 4,
        rowHeight: CGFloat = 22
    ) {
        self.bidColor = bidColor
        self.askColor = askColor
        self.depthBarOpacity = min(max(depthBarOpacity, 0), 1)
        self.priceFractionDigits = priceFractionDigits
        self.sizeFractionDigits = max(0, sizeFractionDigits)
        self.rowHeight = max(12, rowHeight)
    }

    /// The default look.
    public static let standard = MarketDataStyle()
}

extension MarketDataStyle {
    func priceText(_ price: Double) -> String {
        ChartFormat.price(price, digits: priceFractionDigits ?? PriceScale.suggestedFractionDigits(forPrice: price))
    }

    func sizeText(_ size: Double) -> String {
        ChartFormat.price(size, digits: sizeFractionDigits)
    }

    func color(for side: OrderBookSide) -> Color {
        side == .bid ? bidColor : askColor
    }
}
#endif
