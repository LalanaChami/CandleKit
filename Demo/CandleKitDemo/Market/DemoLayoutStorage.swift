import CandleKit
import Foundation

/// Where the demo persists the one layout a trader can save (see `MarketView`'s Save/Load toolbar
/// items): a single well-known file in the app's Documents directory. This is deliberately the
/// simplest thing that exercises `ChartLayout` end to end — a real app would more likely offer
/// named presets (roadmap 7.5) or a `SwiftData`-backed store (7.4), both natural follow-ups once
/// 7.3 (this) has landed.
enum DemoLayoutStorage {
    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("candlekit-demo-layout.json")
    }

    static func save(_ layout: ChartLayout) throws {
        let data = try JSONEncoder().encode(layout)
        try data.write(to: fileURL, options: .atomic)
    }

    /// `nil` when nothing has been saved yet — not an error, so the Load button can disable itself.
    static var hasSavedLayout: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func load() throws -> ChartLayout {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ChartLayout.self, from: data)
    }
}
