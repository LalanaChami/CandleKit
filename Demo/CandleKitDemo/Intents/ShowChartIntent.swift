import AppIntents
import Observation

/// Where an intent leaves its request for the UI (roadmap 8.4).
///
/// With `openAppWhenRun`, the system launches the app (cold or warm) and runs `perform()` in the app's
/// process. On a cold launch `perform()` can run before any view exists, so it must not reach into a
/// view directly. It leaves a request here instead; `MarketView` applies it as soon as it appears,
/// and again whenever a new one arrives.
@MainActor @Observable
final class DemoRouter {
    static let shared = DemoRouter()

    struct ChartRequest: Equatable {
        let product: Product
        let timeframe: Timeframe
        /// Distinguishes two identical requests in a row, so asking twice still re-applies.
        let serial: Int
    }

    var selectedTab = 0
    private(set) var pendingChart: ChartRequest?
    private var serial = 0

    func show(product: Product, timeframe: Timeframe) {
        serial += 1
        pendingChart = ChartRequest(product: product, timeframe: timeframe, serial: serial)
        selectedTab = 0
    }

    /// Called by the view once it has applied the request.
    func consume(_ request: ChartRequest) {
        if pendingChart == request { pendingChart = nil }
    }
}

enum AssetOption: String, AppEnum {
    case bitcoin, ether, solana

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Asset"
    static let caseDisplayRepresentations: [AssetOption: DisplayRepresentation] = [
        .bitcoin: "Bitcoin", .ether: "Ether", .solana: "Solana",
    ]

    var product: Product {
        switch self {
        case .bitcoin: return .bitcoin
        case .ether: return .ether
        case .solana: return .solana
        }
    }
}

enum TimeframeOption: String, AppEnum {
    case oneMinute, fiveMinutes, fifteenMinutes, oneHour, sixHours, oneDay

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Timeframe"
    static let caseDisplayRepresentations: [TimeframeOption: DisplayRepresentation] = [
        .oneMinute: "1 minute", .fiveMinutes: "5 minutes", .fifteenMinutes: "15 minutes",
        .oneHour: "1 hour", .sixHours: "6 hours", .oneDay: "1 day",
    ]

    var timeframe: Timeframe {
        switch self {
        case .oneMinute: return .oneMinute
        case .fiveMinutes: return .fiveMinutes
        case .fifteenMinutes: return .fifteenMinutes
        case .oneHour: return .oneHour
        case .sixHours: return .sixHours
        case .oneDay: return .oneDay
        }
    }
}

struct ShowChartIntent: AppIntent {
    static let title: LocalizedStringResource = "Show chart"
    static let description = IntentDescription("Opens the chart for an asset.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Asset")
    var asset: AssetOption

    @Parameter(title: "Timeframe", default: .fiveMinutes)
    var timeframe: TimeframeOption

    @MainActor
    func perform() async throws -> some IntentResult {
        DemoRouter.shared.show(product: asset.product, timeframe: timeframe.timeframe)
        return .result()
    }
}

struct CandleKitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowChartIntent(),
            phrases: [
                "Show \(\.$asset) chart in \(.applicationName)",
                "Open \(\.$asset) in \(.applicationName)",
            ],
            shortTitle: "Show chart",
            systemImageName: "chart.bar.xaxis"
        )
    }
}
