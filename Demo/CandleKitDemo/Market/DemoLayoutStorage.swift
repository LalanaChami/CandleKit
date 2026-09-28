import CandleKit
import Foundation

/// A named, timestamped `ChartLayout` — what `MarketView`'s Layouts sheet lists, saves, renames and
/// deletes. `id` is stable across renames/overwrites so the sheet can diff and animate by identity.
struct SavedLayout: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var savedAt: Date
    var layout: ChartLayout

    init(id: UUID = UUID(), name: String, savedAt: Date = Date(), layout: ChartLayout) {
        self.id = id
        self.name = name
        self.savedAt = savedAt
        self.layout = layout
    }
}

/// Where the demo persists as many layouts as a trader wants to keep around — one JSON array in the
/// app's Documents directory, replacing the single well-known file the first cut of this feature
/// used. Still deliberately simple: a real app would more likely reach for a `SwiftData`-backed store
/// (roadmap 7.4), a natural follow-up once multiple layouts are worth indexing and querying.
enum DemoLayoutStorage {
    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("candlekit-demo-layouts.json")
    }

    /// Empty (never throws) when nothing has been saved yet, or the file is unreadable — a fresh
    /// install and a corrupted file look the same to the Layouts sheet: an empty list to save into.
    static func loadAll() -> [SavedLayout] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let layouts = try? decoder.decode([SavedLayout].self, from: data) else { return [] }
        return layouts.sorted { $0.savedAt > $1.savedAt }
    }

    /// Appends a new named layout and returns the full, freshly-sorted list.
    @discardableResult
    static func add(name: String, layout: ChartLayout) throws -> [SavedLayout] {
        var all = loadAll()
        all.append(SavedLayout(name: name, layout: layout))
        try write(all)
        return loadAll()
    }

    /// Re-captures `layout` into an existing entry (a trader re-saving over a preset they already
    /// made) without disturbing its name or position in "most recent" order beyond the new timestamp.
    @discardableResult
    static func overwrite(id: UUID, layout: ChartLayout) throws -> [SavedLayout] {
        var all = loadAll()
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        all[index].layout = layout
        all[index].savedAt = Date()
        try write(all)
        return loadAll()
    }

    @discardableResult
    static func rename(id: UUID, to name: String) throws -> [SavedLayout] {
        var all = loadAll()
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        all[index].name = name
        try write(all)
        return loadAll()
    }

    @discardableResult
    static func delete(id: UUID) throws -> [SavedLayout] {
        var all = loadAll()
        all.removeAll { $0.id == id }
        try write(all)
        return loadAll()
    }

    private static func write(_ layouts: [SavedLayout]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(layouts)
        try data.write(to: fileURL, options: .atomic)
    }
}
