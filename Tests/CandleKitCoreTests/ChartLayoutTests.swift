import Foundation
import Testing
@testable import CandleKitCore

@Suite("Viewport codable")
struct ViewportCodableTests {
    @Test func roundTrips() throws {
        let original = Viewport(rightEdge: 123.5, spacing: 9.25)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Viewport.self, from: encoded)
        #expect(decoded == original)
    }
}

@Suite("Chart layout")
struct ChartLayoutTests {
    private func sampleStyle() -> ChartLayout.StyleSnapshot {
        ChartLayout.StyleSnapshot(
            upColor: DrawingColor(red: 0, green: 0.8, blue: 0.2),
            downColor: DrawingColor(red: 0.9, green: 0.1, blue: 0.1),
            hollowUpCandles: true,
            bodyWidthRatio: 0.65,
            volumeOpacity: 0.3,
            gridColor: DrawingColor(red: 0.5, green: 0.5, blue: 0.5, opacity: 0.14),
            axisLabelColor: DrawingColor(red: 0.4, green: 0.4, blue: 0.4),
            crosshairColor: DrawingColor(red: 0.1, green: 0.1, blue: 0.1, opacity: 0.55),
            indicatorPalette: [DrawingColor(red: 1, green: 0.5, blue: 0)],
            crosshairDimOpacity: 0.28
        )
    }

    private func sampleLayout() -> ChartLayout {
        var rsi = RSIIndicator(period: 21)
        rsi.parameters = rsi.parameters.applying(["overbought": .number(80)])

        let drawing = Drawing(
            kind: .trendLine,
            anchors: [
                DrawingAnchor(time: Date(timeIntervalSince1970: 1_700_000_000), price: 101.5),
                DrawingAnchor(time: Date(timeIntervalSince1970: 1_700_086_400), price: 98.25),
            ],
            style: DrawingStyle(color: DrawingColor(red: 0.2, green: 0.5, blue: 0.95))
        )

        return ChartLayout(
            style: sampleStyle(),
            indicators: [
                PersistedIndicator(
                    descriptor: rsi.descriptor,
                    colors: [DrawingColor(red: 0.6, green: 0.2, blue: 0.9)],
                    lineWidth: 2,
                    isVisible: true
                ),
            ],
            drawings: [drawing],
            viewport: Viewport(rightEdge: 512, spacing: 12),
            timeframeIdentifier: "1H"
        )
    }

    @Test func roundTripsEverything() throws {
        let original = sampleLayout()
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChartLayout.self, from: encoded)
        #expect(decoded == original)

        // And the indicator descriptor it carries still resolves against the real catalog.
        let rebuilt = try #require(IndicatorCatalog.standard.makeIndicator(from: decoded.indicators[0].descriptor))
        #expect(rebuilt.parameters.integer("period", default: 0) == 21)
        #expect(rebuilt.parameters.number("overbought", default: 0) == 80)
    }

    @Test func newSchemaVersionIsRejected() throws {
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(sampleLayout())
        ) as! [String: Any]
        json["schemaVersion"] = ChartLayout.currentSchemaVersion + 1
        let data = try JSONSerialization.data(withJSONObject: json)

        #expect(throws: ChartLayoutError.self) {
            _ = try JSONDecoder().decode(ChartLayout.self, from: data)
        }
        do {
            _ = try JSONDecoder().decode(ChartLayout.self, from: data)
            Issue.record("expected unsupportedSchemaVersion to be thrown")
        } catch ChartLayoutError.unsupportedSchemaVersion(let version) {
            #expect(version == ChartLayout.currentSchemaVersion + 1)
        }
    }

    /// A layout encoded by a hypothetical future version that added fields this one doesn't send
    /// yet must still decode — `indicators`/`drawings` default to empty rather than failing.
    @Test func missingOptionalArraysDefaultToEmpty() throws {
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(sampleLayout())
        ) as! [String: Any]
        json.removeValue(forKey: "indicators")
        json.removeValue(forKey: "drawings")
        json.removeValue(forKey: "timeframeIdentifier")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(ChartLayout.self, from: data)
        #expect(decoded.indicators.isEmpty)
        #expect(decoded.drawings.isEmpty)
        #expect(decoded.timeframeIdentifier == nil)
    }

    @Test func initialSchemaVersionIsCurrent() {
        #expect(sampleLayout().schemaVersion == ChartLayout.currentSchemaVersion)
    }
}
