import Foundation
import Testing
@testable import CandleKitCore

@Suite("Indicator parameters")
struct IndicatorParameterTests {
    @Test func clampsIntegersIntoRange() {
        var parameter = IndicatorParameter.period(20, range: 2...100)
        parameter.setValue(.integer(500))
        #expect(parameter.value == .integer(100))
        parameter.setValue(.integer(-5))
        #expect(parameter.value == .integer(2))
    }

    /// A period of zero would divide by zero downstream, so a picker binding must not be able to
    /// produce one no matter what it sends.
    @Test func rejectsWrongTypesRatherThanCrashing() {
        var parameter = IndicatorParameter.period(20)
        parameter.setValue(.choice("nonsense"))
        #expect(parameter.value == .integer(20))
        parameter.setValue(.boolean(true))
        #expect(parameter.value == .integer(20))
    }

    @Test func rejectsChoicesOutsideTheOptionList() {
        var parameter = IndicatorParameter(
            key: "method", name: "Method",
            kind: .choice(options: ["SMA", "EMA"]), value: .choice("SMA")
        )
        parameter.setValue(.choice("WMA"))
        #expect(parameter.value == .choice("SMA"))
        parameter.setValue(.choice("EMA"))
        #expect(parameter.value == .choice("EMA"))
    }

    @Test func clampsNumbersAndRejectsNonFinite() {
        var parameter = IndicatorParameter(
            key: "multiplier", name: "Std. deviations",
            kind: .number(range: 0.1...10), value: .number(2)
        )
        parameter.setValue(.number(99))
        #expect(parameter.value == .number(10))
        parameter.setValue(.number(.nan))
        #expect(parameter.value == .number(10))
    }

    /// A layout saved by a newer version may carry parameters this build doesn't know about.
    @Test func applyingIgnoresUnknownKeys() {
        let parameters = BollingerBandsIndicator().parameters
        let updated = parameters.applying([
            "period": .integer(50),
            "somethingFromTheFuture": .boolean(true),
        ])
        #expect(updated.integer("period", default: 0) == 50)
        #expect(updated.count == parameters.count)
    }
}

@Suite("Indicator catalog")
struct IndicatorCatalogTests {
    @Test func standardCatalogHasUniqueIdentifiers() {
        let identifiers = IndicatorCatalog.standard.entries.map(\.identifier)
        #expect(Set(identifiers).count == identifiers.count, "duplicate identifiers: \(identifiers)")
    }

    @Test func groupingCoversEveryEntry() {
        let grouped = IndicatorCatalog.standard.groupedByCategory()
        let total = grouped.reduce(0) { $0 + $1.entries.count }
        #expect(total == IndicatorCatalog.standard.entries.count)
    }

    @Test func searchMatchesNameAndIdentifier() {
        let catalog = IndicatorCatalog.standard
        #expect(catalog.search("bollinger").contains { $0.identifier == "bollinger" })
        #expect(catalog.search("RELATIVE").contains { $0.identifier == "rsi" })
        #expect(catalog.search("  ").count == catalog.entries.count)
        #expect(catalog.search("no such indicator").isEmpty)
    }

    /// The round trip a saved layout depends on.
    @Test func descriptorRoundTripsThroughTheCatalog() throws {
        var original = RSIIndicator(period: 21)
        original.parameters = original.parameters.applying(["overbought": .number(80)])
        let descriptor = original.descriptor

        let encoded = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(IndicatorDescriptor.self, from: encoded)
        #expect(decoded == descriptor)

        let rebuilt = try #require(IndicatorCatalog.standard.makeIndicator(from: decoded))
        #expect(rebuilt.parameters.integer("period", default: 0) == 21)
        #expect(rebuilt.parameters.number("overbought", default: 0) == 80)
        #expect(rebuilt.shortLabel == "RSI 21")
    }

    /// An app that removed a custom indicator shouldn't fail the whole layout load.
    @Test func unknownIdentifierReturnsNil() {
        let descriptor = IndicatorDescriptor(identifier: "not-registered")
        #expect(IndicatorCatalog.standard.makeIndicator(from: descriptor) == nil)
    }

    /// A hand-edited or corrupted layout must not be able to create a divide-by-zero indicator.
    @Test func outOfRangeStoredValuesAreClamped() throws {
        let descriptor = IndicatorDescriptor(identifier: "ma", parameters: ["period": .integer(0)])
        let indicator = try #require(IndicatorCatalog.standard.makeIndicator(from: descriptor))
        #expect(indicator.parameters.integer("period", default: -1) >= 1)
        // And it still computes without crashing.
        _ = indicator.compute(IndicatorFixtures.candles)
    }

    @Test func appsCanExtendTheCatalog() {
        let extended = IndicatorCatalog.standard.adding(
            IndicatorCatalogEntry(RangeIndicator.self) { RangeIndicator() }
        )
        #expect(extended.entry(for: "range") != nil)
        #expect(extended.removing(identifier: "range").entry(for: "range") == nil)
        #expect(IndicatorCatalog.standard.entry(for: "range") == nil, "standard must be unchanged")
    }
}

@Suite("Standard indicators")
struct StandardIndicatorTests {
    private let candles = IndicatorFixtures.candles

    @Test func everyStandardIndicatorProducesPlots() {
        for entry in IndicatorCatalog.standard.entries {
            let result = entry.makeDefault().compute(candles)
            #expect(!result.plots.isEmpty, "\(entry.identifier) produced no plots")
            for plot in result.plots {
                #expect(
                    plot.values.count == candles.count,
                    "\(entry.identifier).\(plot.key) has \(plot.values.count) values for \(candles.count) candles"
                )
            }
        }
    }

    /// Fills and levels must reference plots that exist, or the renderer has nothing to draw between.
    @Test func fillsReferenceRealPlots() {
        for entry in IndicatorCatalog.standard.entries {
            let result = entry.makeDefault().compute(candles)
            for fill in result.fills {
                #expect(result.plot(fill.lowerPlotKey) != nil, "\(entry.identifier): missing \(fill.lowerPlotKey)")
                #expect(result.plot(fill.upperPlotKey) != nil, "\(entry.identifier): missing \(fill.upperPlotKey)")
            }
        }
    }

    @Test func plotKeysAreUniqueWithinAnIndicator() {
        for entry in IndicatorCatalog.standard.entries {
            let keys = entry.makeDefault().compute(candles).plots.map(\.key)
            #expect(Set(keys).count == keys.count, "\(entry.identifier) has duplicate plot keys")
        }
    }

    /// Empty and single-candle series are the two inputs most likely to crash an indicator.
    @Test func handlesEmptyAndTinySeries() {
        for entry in IndicatorCatalog.standard.entries {
            let indicator = entry.makeDefault()
            #expect(indicator.compute([]).plots.allSatisfy { $0.values.isEmpty })
            let single = Array(candles.prefix(1))
            for plot in indicator.compute(single).plots {
                #expect(plot.values.count == 1, "\(entry.identifier) on a single candle")
            }
        }
    }

    @Test func rsiPinsItsPaneToZeroHundred() {
        let result = RSIIndicator().compute(candles)
        #expect(result.preferredRange == 0...100)
        #expect(result.levels.count == 2)
    }

    @Test func movingAverageMethodChangesTheResult() {
        let simple = MovingAverageIndicator(period: 5, method: .simple).compute(candles)
        let weighted = MovingAverageIndicator(period: 5, method: .weighted).compute(candles)
        #expect(simple.plot("ma")!.values != weighted.plot("ma")!.values)
        #expect(MovingAverageIndicator(period: 5, method: .exponential).shortLabel == "EMA 5")
    }

    @Test func crosshairReadoutSkipsHiddenPlots() {
        let result = IndicatorResult(plots: [
            IndicatorPlot(key: "shown", name: "Shown", values: [1, 2, 3]),
            IndicatorPlot(key: "anchor", name: "Anchor", values: [4, 5, 6], style: .hidden),
        ])
        let readout = result.values(at: 1)
        #expect(readout.count == 1)
        #expect(readout[0].name == "Shown")
        #expect(readout[0].value == 2)
    }
}

/// Stands in for an app-defined indicator, exercising the same extension point third-party code uses.
private struct RangeIndicator: Indicator {
    static let identifier = "range"
    static let displayName = "High − Low"
    static let category = IndicatorCategory.volatility

    var parameters: [IndicatorParameter] = []
    var pane: IndicatorPane { .separate() }
    var shortLabel: String { "Range" }

    func compute(_ candles: [Candle]) -> IndicatorResult {
        IndicatorResult(plots: [
            IndicatorPlot(key: "range", name: "Range", values: candles.map { $0.high - $0.low })
        ])
    }
}
