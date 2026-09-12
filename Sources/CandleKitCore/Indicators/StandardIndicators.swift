import Foundation

// The Tier 1 catalog: the indicators that actually get used constantly. Each is deliberately small,
// because all the real work lives in `IndicatorMath` — these types exist to describe *how the
// result is drawn* and *what a picker can configure*, not to do arithmetic.

// MARK: - Moving averages

/// Simple, exponential or weighted moving average of the close, overlaid on the price.
public struct MovingAverageIndicator: Indicator {
    public static let identifier = "ma"
    public static let displayName = "Moving Average"
    public static let category = IndicatorCategory.movingAverage

    public enum Method: String, CaseIterable, Sendable {
        case simple = "SMA"
        case exponential = "EMA"
        case weighted = "WMA"
    }

    public var parameters: [IndicatorParameter]

    public init(period: Int = 20, method: Method = .simple) {
        parameters = [
            .period(period),
            IndicatorParameter(
                key: "method",
                name: "Method",
                kind: .choice(options: Method.allCases.map(\.rawValue)),
                value: .choice(method.rawValue)
            ),
        ]
    }

    public var period: Int { parameters.integer("period", default: 20) }
    public var method: Method {
        Method(rawValue: parameters.choice("method", default: Method.simple.rawValue)) ?? .simple
    }

    public var pane: IndicatorPane { .price }
    public var shortLabel: String { "\(method.rawValue) \(period)" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        let closes = candles.map(\.close)
        let values: [Double?]
        switch method {
        case .simple: values = IndicatorMath.sma(closes, period: period)
        case .exponential: values = IndicatorMath.ema(closes, period: period)
        case .weighted: values = IndicatorMath.wma(closes, period: period)
        }
        return IndicatorResult(plots: [
            IndicatorPlot(key: "ma", name: shortLabel, values: values, colorRole: .series(0))
        ])
    }
}

// MARK: - Volatility

/// Bollinger Bands: an SMA with bands a number of standard deviations away, and a shaded channel.
public struct BollingerBandsIndicator: Indicator {
    public static let identifier = "bollinger"
    public static let displayName = "Bollinger Bands"
    public static let category = IndicatorCategory.volatility

    public var parameters: [IndicatorParameter]

    public init(period: Int = 20, multiplier: Double = 2) {
        parameters = [
            .period(period, range: 2...500),
            IndicatorParameter(
                key: "multiplier",
                name: "Std. deviations",
                kind: .number(range: 0.1...10, step: 0.1),
                value: .number(multiplier)
            ),
        ]
    }

    public var period: Int { parameters.integer("period", default: 20) }
    public var multiplier: Double { parameters.number("multiplier", default: 2) }

    public var pane: IndicatorPane { .price }
    public var shortLabel: String { "BB \(period), \(multiplier.formatted(.number.precision(.fractionLength(0...2))))" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        let bands = IndicatorMath.bollingerBands(candles.map(\.close), period: period, multiplier: multiplier)
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

/// Average True Range, in its own pane.
public struct ATRIndicator: Indicator {
    public static let identifier = "atr"
    public static let displayName = "Average True Range"
    public static let category = IndicatorCategory.volatility

    public var parameters: [IndicatorParameter]

    public init(period: Int = 14) {
        parameters = [.period(period)]
    }

    public var period: Int { parameters.integer("period", default: 14) }
    public var pane: IndicatorPane { .separate(preferredHeight: 80) }
    public var shortLabel: String { "ATR \(period)" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        let values = IndicatorMath.atr(
            highs: candles.map(\.high),
            lows: candles.map(\.low),
            closes: candles.map(\.close),
            period: period
        )
        return IndicatorResult(plots: [
            IndicatorPlot(key: "atr", name: shortLabel, values: values, colorRole: .series(0))
        ])
    }
}

// MARK: - Oscillators

/// Wilder's RSI, pinned to a 0–100 pane with overbought and oversold levels.
public struct RSIIndicator: Indicator {
    public static let identifier = "rsi"
    public static let displayName = "Relative Strength Index"
    public static let category = IndicatorCategory.oscillator

    public var parameters: [IndicatorParameter]

    public init(period: Int = 14, overbought: Double = 70, oversold: Double = 30) {
        parameters = [
            .period(period),
            IndicatorParameter(key: "overbought", name: "Overbought",
                               kind: .number(range: 50...100, step: 1), value: .number(overbought)),
            IndicatorParameter(key: "oversold", name: "Oversold",
                               kind: .number(range: 0...50, step: 1), value: .number(oversold)),
        ]
    }

    public var period: Int { parameters.integer("period", default: 14) }
    public var pane: IndicatorPane { .separate(preferredHeight: 90) }
    public var shortLabel: String { "RSI \(period)" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        IndicatorResult(
            plots: [
                IndicatorPlot(key: "rsi", name: shortLabel,
                              values: IndicatorMath.rsi(candles.map(\.close), period: period),
                              colorRole: .series(0))
            ],
            levels: [
                IndicatorLevel(value: parameters.number("overbought", default: 70), label: "70"),
                IndicatorLevel(value: parameters.number("oversold", default: 30), label: "30"),
            ],
            // Pinned so the 30/70 lines stay meaningful even when the values never reach them.
            preferredRange: 0...100
        )
    }
}

/// MACD: two lines plus a signed histogram, in its own pane.
public struct MACDIndicator: Indicator {
    public static let identifier = "macd"
    public static let displayName = "MACD"
    public static let category = IndicatorCategory.oscillator

    public var parameters: [IndicatorParameter]

    public init(fastPeriod: Int = 12, slowPeriod: Int = 26, signalPeriod: Int = 9) {
        parameters = [
            .period(fastPeriod, key: "fast", name: "Fast length"),
            .period(slowPeriod, key: "slow", name: "Slow length"),
            .period(signalPeriod, key: "signal", name: "Signal length"),
        ]
    }

    public var pane: IndicatorPane { .separate(preferredHeight: 90) }
    public var shortLabel: String {
        "MACD \(parameters.integer("fast", default: 12)), \(parameters.integer("slow", default: 26)), \(parameters.integer("signal", default: 9))"
    }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        let result = IndicatorMath.macd(
            candles.map(\.close),
            fastPeriod: parameters.integer("fast", default: 12),
            slowPeriod: parameters.integer("slow", default: 26),
            signalPeriod: parameters.integer("signal", default: 9)
        )
        return IndicatorResult(
            plots: [
                IndicatorPlot(key: "histogram", name: "Histogram", values: result.histogram,
                              style: .histogram(), colorRole: .signed),
                IndicatorPlot(key: "macd", name: "MACD", values: result.line, colorRole: .series(0)),
                IndicatorPlot(key: "signal", name: "Signal", values: result.signal, colorRole: .series(1)),
            ],
            levels: [IndicatorLevel(value: 0, dash: nil)]
        )
    }
}

/// Stochastic oscillator, %K and %D on a 0–100 pane.
public struct StochasticIndicator: Indicator {
    public static let identifier = "stochastic"
    public static let displayName = "Stochastic"
    public static let category = IndicatorCategory.oscillator

    public var parameters: [IndicatorParameter]

    public init(period: Int = 14, smoothK: Int = 3, smoothD: Int = 3) {
        parameters = [
            .period(period, name: "%K length"),
            .period(smoothK, key: "smoothK", name: "%K smoothing", range: 1...100),
            .period(smoothD, key: "smoothD", name: "%D smoothing", range: 1...100),
        ]
    }

    public var pane: IndicatorPane { .separate(preferredHeight: 90) }
    public var shortLabel: String {
        "Stoch \(parameters.integer("period", default: 14)), \(parameters.integer("smoothK", default: 3)), \(parameters.integer("smoothD", default: 3))"
    }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        let result = IndicatorMath.stochastic(
            highs: candles.map(\.high),
            lows: candles.map(\.low),
            closes: candles.map(\.close),
            period: parameters.integer("period", default: 14),
            smoothK: parameters.integer("smoothK", default: 3),
            smoothD: parameters.integer("smoothD", default: 3)
        )
        return IndicatorResult(
            plots: [
                IndicatorPlot(key: "k", name: "%K", values: result.k, colorRole: .series(0)),
                IndicatorPlot(key: "d", name: "%D", values: result.d,
                              style: .line(width: 1.5, dash: [4, 3]), colorRole: .series(1)),
            ],
            levels: [IndicatorLevel(value: 80, label: "80"), IndicatorLevel(value: 20, label: "20")],
            preferredRange: 0...100
        )
    }
}

// MARK: - Volume

/// On-Balance Volume, in its own pane.
public struct OBVIndicator: Indicator {
    public static let identifier = "obv"
    public static let displayName = "On-Balance Volume"
    public static let category = IndicatorCategory.volume

    public var parameters: [IndicatorParameter] = []

    public init() {}

    public var pane: IndicatorPane { .separate(preferredHeight: 80) }
    public var shortLabel: String { "OBV" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        IndicatorResult(plots: [
            IndicatorPlot(key: "obv", name: "OBV",
                          values: IndicatorMath.obv(closes: candles.map(\.close), volumes: candles.map(\.volume)),
                          colorRole: .series(0))
        ])
    }
}

/// Session-anchored VWAP, overlaid on the price.
///
/// Anchors to each calendar day by default. On a daily-or-longer chart every candle is its own
/// session, which makes VWAP degenerate to the typical price — the `anchor` parameter exists so a
/// caller can switch to a single session spanning the whole series instead.
public struct VWAPIndicator: Indicator {
    public static let identifier = "vwap"
    public static let displayName = "VWAP"
    public static let category = IndicatorCategory.volume

    public enum Anchor: String, CaseIterable, Sendable {
        case session = "Session"
        case wholeSeries = "Whole series"
    }

    public var parameters: [IndicatorParameter]
    /// Calendar used to find day boundaries. Not a picker parameter — it comes from the host app.
    public var calendar: Calendar

    public init(anchor: Anchor = .session, calendar: Calendar = .current) {
        self.calendar = calendar
        parameters = [
            IndicatorParameter(key: "anchor", name: "Anchor",
                               kind: .choice(options: Anchor.allCases.map(\.rawValue)),
                               value: .choice(anchor.rawValue))
        ]
    }

    public var anchor: Anchor {
        Anchor(rawValue: parameters.choice("anchor", default: Anchor.session.rawValue)) ?? .session
    }

    public var pane: IndicatorPane { .price }
    public var shortLabel: String { "VWAP" }

    public func compute(_ candles: [Candle]) -> IndicatorResult {
        let sessions: [Int]
        switch anchor {
        case .session: sessions = IndicatorMath.dailySessionIDs(for: candles, calendar: calendar)
        case .wholeSeries: sessions = [Int](repeating: 0, count: candles.count)
        }
        let values = IndicatorMath.vwap(
            highs: candles.map(\.high),
            lows: candles.map(\.low),
            closes: candles.map(\.close),
            volumes: candles.map(\.volume),
            sessionIDs: sessions
        )
        return IndicatorResult(plots: [
            IndicatorPlot(key: "vwap", name: "VWAP", values: values, colorRole: .series(2))
        ])
    }
}

// MARK: - Catalog

extension IndicatorCatalog {
    /// The indicators CandleKit ships. Pass this to the picker, or build on it with
    /// ``IndicatorCatalog/adding(_:)`` to include your own.
    public static let standard = IndicatorCatalog(entries: [
        IndicatorCatalogEntry(MovingAverageIndicator.self) { MovingAverageIndicator() },
        IndicatorCatalogEntry(BollingerBandsIndicator.self) { BollingerBandsIndicator() },
        IndicatorCatalogEntry(VWAPIndicator.self) { VWAPIndicator() },
        IndicatorCatalogEntry(RSIIndicator.self) { RSIIndicator() },
        IndicatorCatalogEntry(MACDIndicator.self) { MACDIndicator() },
        IndicatorCatalogEntry(StochasticIndicator.self) { StochasticIndicator() },
        IndicatorCatalogEntry(ATRIndicator.self) { ATRIndicator() },
        IndicatorCatalogEntry(OBVIndicator.self) { OBVIndicator() },
    ])
}
