#if os(iOS)
import SwiftUI

/// An interactive candlestick chart.
///
/// ```swift
/// CandlestickChart(candles)
///     .indicators([.sma(20), .ema(50)])
///     .onReachOldestCandle { Task { await loadHistory() } }
/// ```
///
/// Drag to scroll (with momentum), pinch to zoom around your fingers, long-press to inspect a candle,
/// and double-tap to reset. Candles must be sorted by time, oldest first. Update the array freely:
/// appended candles scroll into view when the newest candle is on screen, and prepended history keeps
/// the visible candles in place.
public struct CandlestickChart: View {
    private let candles: [Candle]
    private let externalState: CandleChartState?
    @State private var internalState = CandleChartState()
    @ScaledMetric(relativeTo: .caption2) private var priceAxisWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .caption2) private var timeAxisHeight: CGFloat = 24

    private var style = CandleChartStyle.standard
    private var indicators: [ChartIndicator] = []
    private var showsVolume = true
    private var showsHeader = true
    private var fractionDigits: Int?
    private var crosshairHandler: ((Candle?) -> Void)?
    private var oldestCandleHandler: (() -> Void)?

    /// - Parameters:
    ///   - candles: The series to draw, oldest first.
    ///   - state: Pass your own state to control scrolling from outside the chart.
    public init(_ candles: [Candle], state: CandleChartState? = nil) {
        self.candles = candles
        self.externalState = state
    }

    public var body: some View {
        let state = externalState ?? internalState
        // Reading `revision` subscribes this view to viewport changes. Crosshair state is deliberately
        // not read here, so the candle layer doesn't redraw while a finger moves.
        let _ = state.revision
        let _ = state.setHandlers(crosshair: crosshairHandler, oldestCandle: oldestCandleHandler)
        let headerDigits = fractionDigits ?? PriceScale.suggestedFractionDigits(forPrice: candles.last?.close ?? 0)

        VStack(alignment: .leading, spacing: 8) {
            if showsHeader && !candles.isEmpty {
                ChartHeader(state: state, candles: candles, fractionDigits: headerDigits, style: style)
            }

            GeometryReader { proxy in
                let frame = state.makeFrame(
                    candles: candles,
                    indicators: indicators,
                    size: proxy.size,
                    metrics: ChartMetrics(priceAxisWidth: priceAxisWidth, timeAxisHeight: timeAxisHeight),
                    showsVolume: showsVolume,
                    fractionDigits: fractionDigits
                )

                ZStack(alignment: .topLeading) {
                    ChartBaseLayer(frame: frame, style: style, appearPhase: state.appearPhase)
                    CrosshairLayer(state: state, frame: frame, style: style)
                    ChartGestureView(state: state)
                        .frame(width: frame.layout.plot.width, height: frame.layout.plot.height)
                        .position(x: frame.layout.plot.midX, y: frame.layout.plot.midY)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Candlestick chart"))
                .accessibilityValue(Text(ChartAccessibility.summary(
                    of: frame.candles[frame.visible],
                    digits: frame.priceFractionDigits,
                    interval: frame.interval
                )))
                .accessibilityChartDescriptor(ChartAccessibility(frame: frame))
                .accessibilityAdjustableAction { direction in
                    let page = max(1, frame.visible.count / 2)
                    switch direction {
                    case .increment:
                        state.scroll(byCandles: page)
                    case .decrement:
                        state.scroll(byCandles: -page)
                    @unknown default:
                        break
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        // Stops any in-flight appear or spring animation the moment this chart leaves the view
        // hierarchy — a `List` row scrolling away mid-animation, a sheet being dismissed, a
        // NavigationStack pop — so its CADisplayLink isn't left running in the background.
        .onDisappear { state.stopAnimations() }
    }
}

// MARK: - Modifiers

extension CandlestickChart {
    /// Colors and candle appearance. See ``CandleChartStyle`` for presets.
    public func candleChartStyle(_ style: CandleChartStyle) -> CandlestickChart {
        var copy = self
        copy.style = style
        return copy
    }

    /// Line overlays such as moving averages. Values are cached and only recomputed when the data changes.
    public func indicators(_ indicators: [ChartIndicator]) -> CandlestickChart {
        var copy = self
        copy.indicators = indicators
        return copy
    }

    /// Shows volume bars beneath the candles. On by default.
    public func volumeVisible(_ visible: Bool = true) -> CandlestickChart {
        var copy = self
        copy.showsVolume = visible
        return copy
    }

    /// Shows the price readout above the chart. On by default.
    public func headerVisible(_ visible: Bool = true) -> CandlestickChart {
        var copy = self
        copy.showsHeader = visible
        return copy
    }

    /// Decimal places for prices. By default this is inferred from the latest close.
    public func priceFractionDigits(_ digits: Int?) -> CandlestickChart {
        var copy = self
        copy.fractionDigits = digits
        return copy
    }

    /// Called when the long-pressed candle changes, and with `nil` when the finger lifts.
    public func onCrosshairChange(_ action: @escaping (Candle?) -> Void) -> CandlestickChart {
        var copy = self
        copy.crosshairHandler = action
        return copy
    }

    /// Called when the user scrolls near the oldest loaded candle. Prepend older candles to your array in response.
    ///
    /// The handler runs once per data size, so it won't fire repeatedly while a request is in flight.
    public func onReachOldestCandle(_ action: @escaping () -> Void) -> CandlestickChart {
        var copy = self
        copy.oldestCandleHandler = action
        return copy
    }
}
#endif
