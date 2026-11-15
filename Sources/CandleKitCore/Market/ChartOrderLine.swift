import Foundation

/// A horizontal line the app wants on the chart for one of its orders or its position.
///
/// The chart only draws these. It never places, changes or cancels an order.
public struct ChartOrderLine: Sendable, Hashable, Identifiable {
    /// What the line stands for, which decides its color and stroke.
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        /// A resting buy order.
        case buy
        /// A resting sell order.
        case sell
        /// The entry price of an open position.
        case position
        case stopLoss
        case takeProfit
    }

    /// The app's own identifier (an order id), returned in the move callback.
    public var id: String
    public var price: Double
    public var kind: Kind
    /// Short text for the tag, e.g. "Buy 0.5" or "Stop". The price is appended by the chart.
    public var label: String
    /// Whether the person may drag this line. Default `false`.
    public var isDraggable: Bool

    public init(id: String, price: Double, kind: Kind, label: String, isDraggable: Bool = false) {
        self.id = id
        self.price = price
        self.kind = kind
        self.label = label
        self.isDraggable = isDraggable
    }
}

/// Pure helpers for dragging an order line.
public enum OrderLineMath {
    /// Rounds `price` to the nearest multiple of `tick`. A `tick` that is `nil`, not finite or
    /// `<= 0` returns `price` unchanged.
    public static func snapped(_ price: Double, tick: Double?) -> Double {
        guard let tick, tick.isFinite, tick > 0 else { return price }
        return (price / tick).rounded() * tick
    }

    /// Signed distance from `reference` to `price` as a share of `reference` (0.01 = +1%).
    /// `nil` when `reference` is 0 or either value is not finite.
    public static func percentDistance(of price: Double, from reference: Double) -> Double? {
        guard price.isFinite, reference.isFinite, reference != 0 else { return nil }
        return (price - reference) / reference
    }
}
