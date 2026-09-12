import Foundation

/// Something that computes drawable series from a candle array.
///
/// Conform your own type to add an indicator CandleKit doesn't ship. Register it in an
/// ``IndicatorCatalog`` and it appears in the picker, gets a generated settings form from its
/// ``parameters``, and round-trips through saved layouts — no changes to CandleKit required.
///
/// ```swift
/// struct RangeIndicator: Indicator {
///     static let identifier = "range"
///     static let displayName = "High − Low"
///     static let category = IndicatorCategory.volatility
///     var parameters: [IndicatorParameter] = []
///     var pane: IndicatorPane { .separate() }
///     var shortLabel: String { "Range" }
///
///     func compute(_ candles: [Candle]) -> IndicatorResult {
///         IndicatorResult(plots: [
///             IndicatorPlot(key: "range", name: "Range", values: candles.map { $0.high - $0.low })
///         ])
///     }
/// }
/// ```
public protocol Indicator: Sendable {
    /// Stable across releases — it's what saved layouts store. Changing it orphans existing layouts.
    static var identifier: String { get }
    /// Shown in the picker, for example `"Relative Strength Index"`.
    static var displayName: String { get }
    static var category: IndicatorCategory { get }

    /// Configurable inputs. Settable so a picker can write edited values back.
    var parameters: [IndicatorParameter] { get set }
    /// Where this indicator draws.
    var pane: IndicatorPane { get }
    /// Compact label for the chart legend, usually name plus key parameters — `"RSI 14"`.
    var shortLabel: String { get }

    /// Computes every plot, fill and level for `candles`.
    ///
    /// Called when the data changes, not on every frame, but it should still be O(n) in one pass
    /// where the maths allows — a naive O(n·period) implementation is noticeably slow on a long
    /// series with a long period.
    func compute(_ candles: [Candle]) -> IndicatorResult
}

extension Indicator {
    public var identifier: String { Self.identifier }
    public var displayName: String { Self.displayName }
    public var category: IndicatorCategory { Self.category }

    /// This indicator's current configuration, ready to store in a layout.
    public var descriptor: IndicatorDescriptor {
        IndicatorDescriptor(identifier: Self.identifier, parameters: parameters.storedValues)
    }
}

/// A serialisable reference to a configured indicator: which one, and with what settings.
///
/// This is what a saved chart layout stores. Rehydrate it with ``IndicatorCatalog/makeIndicator(from:)``.
public struct IndicatorDescriptor: Hashable, Sendable, Codable, Identifiable {
    public var identifier: String
    public var parameters: [String: IndicatorParameterValue]

    public init(identifier: String, parameters: [String: IndicatorParameterValue] = [:]) {
        self.identifier = identifier
        self.parameters = parameters
    }

    /// Stable within a layout, so two RSIs with different periods are distinct entries.
    public var id: String {
        let settings = parameters.keys.sorted().map { key in
            "\(key)=\(String(describing: parameters[key]!))"
        }
        return ([identifier] + settings).joined(separator: "|")
    }
}

/// One indicator type the picker can offer.
public struct IndicatorCatalogEntry: Sendable, Identifiable {
    public let identifier: String
    public let displayName: String
    public let category: IndicatorCategory
    /// Parameters with their defaults, for showing a preview of the settings form.
    public let defaultParameters: [IndicatorParameter]
    private let factory: @Sendable ([IndicatorParameter]) -> any Indicator

    public var id: String { identifier }

    public init<T: Indicator>(_ type: T.Type, default makeDefault: @Sendable @escaping () -> T) {
        let prototype = makeDefault()
        identifier = T.identifier
        displayName = T.displayName
        category = T.category
        defaultParameters = prototype.parameters
        factory = { parameters in
            var indicator = makeDefault()
            indicator.parameters = parameters
            return indicator
        }
    }

    /// An instance with default settings.
    public func makeDefault() -> any Indicator {
        factory(defaultParameters)
    }

    /// An instance with `stored` applied over the defaults. Out-of-range and wrong-typed values are
    /// clamped or ignored rather than accepted, so a hand-edited or corrupted layout can't produce
    /// an indicator that divides by zero.
    public func makeIndicator(parameters stored: [String: IndicatorParameterValue]) -> any Indicator {
        factory(defaultParameters.applying(stored))
    }
}

/// The set of indicators available to a chart — what the picker lists, and what saved layouts can
/// resolve against.
///
/// Immutable by design. Apps that add their own indicators build a new catalog with ``adding(_:)``
/// rather than mutating shared global state, which keeps this `Sendable` with no locking and means
/// two charts in one app can genuinely offer different sets.
public struct IndicatorCatalog: Sendable {
    public let entries: [IndicatorCatalogEntry]

    public init(entries: [IndicatorCatalogEntry]) {
        self.entries = entries
    }

    public func entry(for identifier: String) -> IndicatorCatalogEntry? {
        entries.first { $0.identifier == identifier }
    }

    /// Rebuilds a configured indicator from a saved descriptor. `nil` when the identifier isn't in
    /// this catalog — an app that removed a custom indicator should expect this and drop that entry
    /// from the layout rather than failing the whole load.
    public func makeIndicator(from descriptor: IndicatorDescriptor) -> (any Indicator)? {
        entry(for: descriptor.identifier)?.makeIndicator(parameters: descriptor.parameters)
    }

    /// Entries grouped for a sectioned picker, in `IndicatorCategory.allCases` order.
    public func groupedByCategory() -> [(category: IndicatorCategory, entries: [IndicatorCatalogEntry])] {
        IndicatorCategory.allCases.compactMap { category in
            let matching = entries.filter { $0.category == category }
            return matching.isEmpty ? nil : (category, matching)
        }
    }

    /// Case- and diacritic-insensitive search over display names and identifiers, for the picker's
    /// search field.
    public func search(_ query: String) -> [IndicatorCatalogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { entry in
            entry.displayName.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || entry.identifier.range(of: trimmed, options: .caseInsensitive) != nil
        }
    }

    public func adding(_ entry: IndicatorCatalogEntry) -> IndicatorCatalog {
        IndicatorCatalog(entries: entries + [entry])
    }

    public func removing(identifier: String) -> IndicatorCatalog {
        IndicatorCatalog(entries: entries.filter { $0.identifier != identifier })
    }
}
