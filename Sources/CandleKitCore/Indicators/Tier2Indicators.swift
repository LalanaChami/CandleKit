import Foundation

// Tier 2: the long tail. See `docs/ROADMAP.md` 5.6/5.7 — these exist so traders who want something
// beyond the Tier 1 set have it, without every one of them needing the same scrutiny Tier 1 got.
// Each still documents its convention and is cross-checked in `Tier2IndicatorTests.swift`, per the
// project's stated policy that this isn't optional polish — but see 5.9 in the roadmap: none of
// CandleKit's indicators, Tier 1 or 2, are yet validated against a published authoritative source,
// only internally cross-checked against an independently written reference implementation.

// MARK: - Trend overlays

/// Donchian Channels: the highest high and lowest low over a rolling window, with their midpoint.
public struct DonchianChannelsIndicator: Indicator {
    public static let identifier = "donchian"
    public static let displayName = "Donchian Channels"
    public static let category = IndicatorCategory.trend

    public var parameters: [IndicatorParameter]

    public init(period: Int = 20) {
        parameters = [.period(period, range: 2...500)]
    }

    public var period: Int { parameters.integer("period", default: 20) }
    public var pane: IndicatorPane { .price }
    public var shortLabel: String { "Donchian \(period)" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        let bands = IndicatorMath.donchianChannels(
            highs: candles.map(\.high), lows: candles.map(\.low), period: period
        )
        return IndicatorResult(
            plots: [
                IndicatorPlot(key: "upper", name: "Upper", values: bands.upper, colorRole: .series(0)),
                IndicatorPlot(key: "middle", name: "Basis", values: bands.middle,
                              style: .line(width: 1.5, dash: [4, 3]), colorRole: .series(1)),
                IndicatorPlot(key: "lower", name: "Lower", values: bands.lower, colorRole: .series(0)),
            ],
            fills: [IndicatorFill(lowerPlotKey: "lower", upperPlotKey: "upper", colorRole: .series(0))]
        )
    }
}

/// Keltner Channels: an EMA middle line with ATR-multiple bands.
public struct KeltnerChannelsIndicator: Indicator {
    public static let identifier = "keltner"
    public static let displayName = "Keltner Channels"
    public static let category = IndicatorCategory.trend

    public var parameters: [IndicatorParameter]

    public init(period: Int = 20, atrPeriod: Int = 10, multiplier: Double = 2) {
        parameters = [
            .period(period, range: 2...500),
            .period(atrPeriod, key: "atrPeriod", name: "ATR length", range: 1...500),
            IndicatorParameter(key: "multiplier", name: "ATR multiplier",
                               kind: .number(range: 0.1...10, step: 0.1), value: .number(multiplier)),
        ]
    }

    public var period: Int { parameters.integer("period", default: 20) }
    public var atrPeriod: Int { parameters.integer("atrPeriod", default: 10) }
    public var multiplier: Double { parameters.number("multiplier", default: 2) }
    public var pane: IndicatorPane { .price }
    public var shortLabel: String { "Keltner \(period)" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        let bands = IndicatorMath.keltnerChannels(
            highs: candles.map(\.high), lows: candles.map(\.low), closes: candles.map(\.close),
            period: period, atrPeriod: atrPeriod, multiplier: multiplier
        )
        return IndicatorResult(
            plots: [
                IndicatorPlot(key: "upper", name: "Upper", values: bands.upper, colorRole: .series(0)),
                IndicatorPlot(key: "middle", name: "Basis", values: bands.middle,
                              style: .line(width: 1.5, dash: [4, 3]), colorRole: .series(1)),
                IndicatorPlot(key: "lower", name: "Lower", values: bands.lower, colorRole: .series(0)),
            ],
            fills: [IndicatorFill(lowerPlotKey: "lower", upperPlotKey: "upper", colorRole: .series(0))]
        )
    }
}

/// SuperTrend: an ATR-band trend-follower that hugs price from below in an uptrend and above in a
/// downtrend, flipping sides when price crosses it.
public struct SuperTrendIndicator: Indicator {
    public static let identifier = "supertrend"
    public static let displayName = "SuperTrend"
    public static let category = IndicatorCategory.trend

    public var parameters: [IndicatorParameter]

    public init(period: Int = 10, multiplier: Double = 3) {
        parameters = [
            .period(period, range: 1...500),
            IndicatorParameter(key: "multiplier", name: "ATR multiplier",
                               kind: .number(range: 0.1...20, step: 0.1), value: .number(multiplier)),
        ]
    }

    public var period: Int { parameters.integer("period", default: 10) }
    public var multiplier: Double { parameters.number("multiplier", default: 3) }
    public var pane: IndicatorPane { .price }
    public var shortLabel: String { "SuperTrend \(period)" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        let result = IndicatorMath.superTrend(
            highs: candles.map(\.high), lows: candles.map(\.low), closes: candles.map(\.close),
            period: period, multiplier: multiplier
        )
        return IndicatorResult(plots: [
            IndicatorPlot(key: "up", name: "Uptrend", values: result.uptrend,
                          style: .steppedLine(width: 1.5), colorRole: .bullish),
            IndicatorPlot(key: "down", name: "Downtrend", values: result.downtrend,
                          style: .steppedLine(width: 1.5), colorRole: .bearish),
        ])
    }
}

/// Parabolic SAR: dots that trail price and flip sides when price crosses them, commonly read as a
/// trailing stop level.
public struct ParabolicSARIndicator: Indicator {
    public static let identifier = "psar"
    public static let displayName = "Parabolic SAR"
    public static let category = IndicatorCategory.trend

    public var parameters: [IndicatorParameter]

    public init(step: Double = 0.02, maximum: Double = 0.2) {
        parameters = [
            IndicatorParameter(key: "step", name: "Step",
                               kind: .number(range: 0.001...0.5, step: 0.001), value: .number(step)),
            IndicatorParameter(key: "maximum", name: "Maximum",
                               kind: .number(range: 0.01...1, step: 0.01), value: .number(maximum)),
        ]
    }

    public var step: Double { parameters.number("step", default: 0.02) }
    public var maximum: Double { parameters.number("maximum", default: 0.2) }
    public var pane: IndicatorPane { .price }
    public var shortLabel: String { "PSAR" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        let result = IndicatorMath.parabolicSAR(
            highs: candles.map(\.high), lows: candles.map(\.low),
            accelerationStep: step, accelerationMax: maximum
        )
        return IndicatorResult(plots: [
            IndicatorPlot(key: "bullish", name: "SAR (up)", values: result.bullish,
                          style: .points(radius: 1.5), colorRole: .bullish),
            IndicatorPlot(key: "bearish", name: "SAR (down)", values: result.bearish,
                          style: .points(radius: 1.5), colorRole: .bearish),
        ])
    }
}

/// Ichimoku Kinko Hyo: conversion and base lines, a forward-shifted cloud between two spans, and a
/// backward-shifted lagging close. See `IndicatorMath.ichimoku` for the one known gap (the cloud
/// doesn't yet project past the last candle into blank future space).
public struct IchimokuCloudIndicator: Indicator {
    public static let identifier = "ichimoku"
    public static let displayName = "Ichimoku Cloud"
    public static let category = IndicatorCategory.trend

    public var parameters: [IndicatorParameter]

    public init(conversionPeriod: Int = 9, basePeriod: Int = 26, spanBPeriod: Int = 52, displacement: Int = 26) {
        parameters = [
            .period(conversionPeriod, key: "conversion", name: "Conversion length", range: 1...200),
            .period(basePeriod, key: "base", name: "Base length", range: 1...300),
            .period(spanBPeriod, key: "spanB", name: "Leading span B length", range: 1...400),
            .period(displacement, key: "displacement", name: "Displacement", range: 0...300),
        ]
    }

    public var pane: IndicatorPane { .price }
    public var shortLabel: String { "Ichimoku" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        let result = IndicatorMath.ichimoku(
            highs: candles.map(\.high), lows: candles.map(\.low), closes: candles.map(\.close),
            conversionPeriod: parameters.integer("conversion", default: 9),
            basePeriod: parameters.integer("base", default: 26),
            spanBPeriod: parameters.integer("spanB", default: 52),
            displacement: parameters.integer("displacement", default: 26)
        )
        return IndicatorResult(
            plots: [
                IndicatorPlot(key: "spanA", name: "Leading Span A", values: result.spanA,
                              style: .line(width: 1), colorRole: .bullish),
                IndicatorPlot(key: "spanB", name: "Leading Span B", values: result.spanB,
                              style: .line(width: 1), colorRole: .bearish),
                IndicatorPlot(key: "conversion", name: "Conversion", values: result.conversion,
                              colorRole: .series(0)),
                IndicatorPlot(key: "base", name: "Base", values: result.base, colorRole: .series(1)),
                IndicatorPlot(key: "lagging", name: "Lagging Span", values: result.laggingSpan,
                              style: .line(width: 1, dash: [2, 2]), colorRole: .series(2)),
            ],
            fills: [
                IndicatorFill(lowerPlotKey: "spanB", upperPlotKey: "spanA",
                              colorRole: .bullish, opacity: 0.12, colorFollowsCrossover: true),
            ]
        )
    }
}

/// Classic, Fibonacci or Camarilla pivot points: a stepped set of support/resistance levels held
/// constant for each session, derived from the previous session's high/low/close.
public struct PivotPointsIndicator: Indicator {
    public static let identifier = "pivots"
    public static let displayName = "Pivot Points"
    public static let category = IndicatorCategory.trend

    public var parameters: [IndicatorParameter]
    /// Calendar used to find session boundaries. Not a picker parameter — comes from the host app,
    /// same as `VWAPIndicator.calendar`.
    public var calendar: Calendar

    public init(method: IndicatorMath.PivotMethod = .classic, calendar: Calendar = .current) {
        self.calendar = calendar
        parameters = [
            IndicatorParameter(key: "method", name: "Method",
                               kind: .choice(options: IndicatorMath.PivotMethod.allCases.map(\.rawValue)),
                               value: .choice(method.rawValue)),
        ]
    }

    public var method: IndicatorMath.PivotMethod {
        IndicatorMath.PivotMethod(rawValue: parameters.choice("method", default: IndicatorMath.PivotMethod.classic.rawValue)) ?? .classic
    }

    public var pane: IndicatorPane { .price }
    public var shortLabel: String { "Pivots (\(method.rawValue))" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        let sessions = IndicatorMath.dailySessionIDs(for: candles, calendar: calendar)
        let levels = IndicatorMath.pivotPoints(
            highs: candles.map(\.high), lows: candles.map(\.low), closes: candles.map(\.close),
            sessionIDs: sessions, method: method
        )
        let stepped = IndicatorPlotStyle.steppedLine(width: 1)
        return IndicatorResult(plots: [
            IndicatorPlot(key: "pivot", name: "P", values: levels.pivot, style: stepped, colorRole: .neutral),
            IndicatorPlot(key: "r1", name: "R1", values: levels.r1, style: stepped, colorRole: .bearish),
            IndicatorPlot(key: "r2", name: "R2", values: levels.r2, style: stepped, colorRole: .bearish),
            IndicatorPlot(key: "r3", name: "R3", values: levels.r3, style: stepped, colorRole: .bearish),
            IndicatorPlot(key: "s1", name: "S1", values: levels.s1, style: stepped, colorRole: .bullish),
            IndicatorPlot(key: "s2", name: "S2", values: levels.s2, style: stepped, colorRole: .bullish),
            IndicatorPlot(key: "s3", name: "S3", values: levels.s3, style: stepped, colorRole: .bullish),
        ])
    }
}

// MARK: - Oscillators

/// Wilder's ADX/DMI: `+DI`/`-DI` show which side is in control, `ADX` shows how strongly — high
/// ADX means a strong trend in *either* direction, not a bullish one specifically.
public struct ADXIndicator: Indicator {
    public static let identifier = "adx"
    public static let displayName = "ADX / DMI"
    public static let category = IndicatorCategory.oscillator

    public var parameters: [IndicatorParameter]

    public init(period: Int = 14) {
        parameters = [.period(period, range: 2...200)]
    }

    public var period: Int { parameters.integer("period", default: 14) }
    public var pane: IndicatorPane { .separate(preferredHeight: 90) }
    public var shortLabel: String { "ADX \(period)" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        let result = IndicatorMath.adx(
            highs: candles.map(\.high), lows: candles.map(\.low), closes: candles.map(\.close), period: period
        )
        return IndicatorResult(
            plots: [
                IndicatorPlot(key: "adx", name: "ADX", values: result.adx, colorRole: .series(0)),
                IndicatorPlot(key: "plusDI", name: "+DI", values: result.plusDI,
                              style: .line(width: 1.25, dash: [3, 2]), colorRole: .bullish),
                IndicatorPlot(key: "minusDI", name: "-DI", values: result.minusDI,
                              style: .line(width: 1.25, dash: [3, 2]), colorRole: .bearish),
            ],
            levels: [IndicatorLevel(value: 25, label: "25")],
            preferredRange: 0...100
        )
    }
}

/// Commodity Channel Index, with the conventional ±100 overbought/oversold levels.
public struct CCIIndicator: Indicator {
    public static let identifier = "cci"
    public static let displayName = "Commodity Channel Index"
    public static let category = IndicatorCategory.oscillator

    public var parameters: [IndicatorParameter]

    public init(period: Int = 20) {
        parameters = [.period(period, range: 2...500)]
    }

    public var period: Int { parameters.integer("period", default: 20) }
    public var pane: IndicatorPane { .separate(preferredHeight: 90) }
    public var shortLabel: String { "CCI \(period)" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        IndicatorResult(
            plots: [
                IndicatorPlot(key: "cci", name: shortLabel,
                              values: IndicatorMath.cci(highs: candles.map(\.high), lows: candles.map(\.low),
                                                         closes: candles.map(\.close), period: period),
                              colorRole: .series(0))
            ],
            levels: [
                IndicatorLevel(value: 100, label: "100"),
                IndicatorLevel(value: -100, label: "-100"),
            ]
        )
    }
}

/// Money Flow Index — RSI's formula applied to volume-weighted price — pinned to 0–100 with the
/// conventional 20/80 levels.
public struct MFIIndicator: Indicator {
    public static let identifier = "mfi"
    public static let displayName = "Money Flow Index"
    public static let category = IndicatorCategory.volume

    public var parameters: [IndicatorParameter]

    public init(period: Int = 14) {
        parameters = [.period(period, range: 2...200)]
    }

    public var period: Int { parameters.integer("period", default: 14) }
    public var pane: IndicatorPane { .separate(preferredHeight: 90) }
    public var shortLabel: String { "MFI \(period)" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        IndicatorResult(
            plots: [
                IndicatorPlot(key: "mfi", name: shortLabel,
                              values: IndicatorMath.mfi(highs: candles.map(\.high), lows: candles.map(\.low),
                                                         closes: candles.map(\.close), volumes: candles.map(\.volume),
                                                         period: period),
                              colorRole: .series(0))
            ],
            levels: [IndicatorLevel(value: 80, label: "80"), IndicatorLevel(value: 20, label: "20")],
            preferredRange: 0...100
        )
    }
}

/// Williams %R, on its native −100…0 scale.
public struct WilliamsRIndicator: Indicator {
    public static let identifier = "williamsR"
    public static let displayName = "Williams %R"
    public static let category = IndicatorCategory.oscillator

    public var parameters: [IndicatorParameter]

    public init(period: Int = 14) {
        parameters = [.period(period, range: 2...500)]
    }

    public var period: Int { parameters.integer("period", default: 14) }
    public var pane: IndicatorPane { .separate(preferredHeight: 90) }
    public var shortLabel: String { "Williams %R \(period)" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        IndicatorResult(
            plots: [
                IndicatorPlot(key: "williamsR", name: "%R",
                              values: IndicatorMath.williamsR(highs: candles.map(\.high), lows: candles.map(\.low),
                                                               closes: candles.map(\.close), period: period),
                              colorRole: .series(0))
            ],
            levels: [IndicatorLevel(value: -20, label: "-20"), IndicatorLevel(value: -80, label: "-80")],
            preferredRange: -100...0
        )
    }
}

/// Rate of Change (percentage) or Momentum (raw difference) from `period` bars ago — the same
/// comparison in two different units.
public struct ROCIndicator: Indicator {
    public static let identifier = "roc"
    public static let displayName = "Rate of Change"
    public static let category = IndicatorCategory.oscillator

    public enum Mode: String, CaseIterable, Sendable {
        case percentage = "Percent"
        case absolute = "Absolute"
    }

    public var parameters: [IndicatorParameter]

    public init(period: Int = 12, mode: Mode = .percentage) {
        parameters = [
            .period(period, range: 1...500),
            IndicatorParameter(key: "mode", name: "Mode",
                               kind: .choice(options: Mode.allCases.map(\.rawValue)),
                               value: .choice(mode.rawValue)),
        ]
    }

    public var period: Int { parameters.integer("period", default: 12) }
    public var mode: Mode { Mode(rawValue: parameters.choice("mode", default: Mode.percentage.rawValue)) ?? .percentage }
    public var pane: IndicatorPane { .separate(preferredHeight: 80) }
    public var shortLabel: String { mode == .percentage ? "ROC \(period)" : "Momentum \(period)" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        let closes = candles.map(\.close)
        let values = mode == .percentage
            ? IndicatorMath.rateOfChange(closes, period: period)
            : IndicatorMath.momentum(closes, period: period)
        return IndicatorResult(
            plots: [IndicatorPlot(key: "roc", name: shortLabel, values: values, colorRole: .series(0))],
            levels: [IndicatorLevel(value: 0, dash: nil)]
        )
    }
}

/// Chaikin Money Flow: a volume-weighted read on buying vs. selling pressure, oscillating (loosely
/// — it isn't range-bound the way RSI is) around zero.
public struct ChaikinMoneyFlowIndicator: Indicator {
    public static let identifier = "cmf"
    public static let displayName = "Chaikin Money Flow"
    public static let category = IndicatorCategory.volume

    public var parameters: [IndicatorParameter]

    public init(period: Int = 20) {
        parameters = [.period(period, range: 2...500)]
    }

    public var period: Int { parameters.integer("period", default: 20) }
    public var pane: IndicatorPane { .separate(preferredHeight: 80) }
    public var shortLabel: String { "CMF \(period)" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        IndicatorResult(
            plots: [
                IndicatorPlot(key: "cmf", name: shortLabel, values: IndicatorMath.chaikinMoneyFlow(
                    highs: candles.map(\.high), lows: candles.map(\.low),
                    closes: candles.map(\.close), volumes: candles.map(\.volume), period: period
                ), style: .histogram(),
                              colorRole: .signed)
            ],
            levels: [IndicatorLevel(value: 0, dash: nil)]
        )
    }
}

// MARK: - Catalog

extension IndicatorCatalog {
    /// `IndicatorCatalog.standard` plus every Tier 2 indicator. Pass this instead of `.standard` to
    /// offer the full built-in set; build on it with ``IndicatorCatalog/adding(_:)`` for your own.
    public static let full = IndicatorCatalog(entries: standard.entries + [
        IndicatorCatalogEntry(DonchianChannelsIndicator.self) { DonchianChannelsIndicator() },
        IndicatorCatalogEntry(KeltnerChannelsIndicator.self) { KeltnerChannelsIndicator() },
        IndicatorCatalogEntry(SuperTrendIndicator.self) { SuperTrendIndicator() },
        IndicatorCatalogEntry(ParabolicSARIndicator.self) { ParabolicSARIndicator() },
        IndicatorCatalogEntry(IchimokuCloudIndicator.self) { IchimokuCloudIndicator() },
        IndicatorCatalogEntry(PivotPointsIndicator.self) { PivotPointsIndicator() },
        IndicatorCatalogEntry(ADXIndicator.self) { ADXIndicator() },
        IndicatorCatalogEntry(CCIIndicator.self) { CCIIndicator() },
        IndicatorCatalogEntry(MFIIndicator.self) { MFIIndicator() },
        IndicatorCatalogEntry(WilliamsRIndicator.self) { WilliamsRIndicator() },
        IndicatorCatalogEntry(ROCIndicator.self) { ROCIndicator() },
        IndicatorCatalogEntry(ChaikinMoneyFlowIndicator.self) { ChaikinMoneyFlowIndicator() },
    ])
}
