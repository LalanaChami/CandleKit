import ActivityKit
import Foundation

/// Shared by the app (which starts and updates the activity) and the widget extension (which draws it).
///
/// A Live Activity's content state is capped at about 4 KB, so it carries a short list of closes
/// (30 doubles is under 300 bytes) and not candles.
struct PriceActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var price: Double
        /// Percent change over the closes in `closes`.
        var changePercent: Double
        var closes: [Double]
    }

    var symbol: String
}
