import CandleKit
import SwiftUI

struct MarketView: View {
    @State private var feed = MarketFeed()
    @State private var chartState = CandleChartState(candleSpacing: 9)

    @State private var source: DataSourceKind = .coinbase
    @State private var product: Product = .bitcoin
    @State private var timeframe: Timeframe = .fiveMinutes
    @State private var attempt = 0

    @State private var showsSMA = true
    @State private var showsEMA = true
    @State private var showsBollinger = false
    @State private var showsVWAP = false
    @State private var showsRSI = false
    @State private var showsMACD = false
    @State private var showsVolume = true

    // Drawing tools (roadmap 6.1–6.3). `drawings` is the app-owned array CandleKit renders and
    // mutates through `.drawings($drawings)`; `activeDrawingTool` is which tool, if any, a
    // one-finger drag currently creates; `selectedDrawingID` mirrors what's selected in cursor mode
    // (tapping an existing drawing), which `DrawingToolPicker`'s "Delete" button below reads.
    @State private var drawings: [Drawing] = []
    @State private var activeDrawingTool: DrawingTool? = nil
    @State private var selectedDrawingID: UUID? = nil
    // What color the *next* drawing starts as (`.defaultDrawingStyle(...)`); `DrawingToolPicker`'s
    // swatch row also uses this to immediately recolor whatever's currently selected, so picking a
    // color reads the same whether you're about to draw something or already have something picked.
    @State private var drawingColor: DrawingColor = .default

    // Style is app-owned state, not a constant, so Save/Load Layout (roadmap 7.3) has something to
    // capture and restore — see `ChartLayout.StyleSnapshot`.
    @State private var style = CandleChartStyle(priceAxisMaterial: .ultraThinMaterial)
    @State private var layoutAlert: LayoutAlert?

    // Price alert row (roadmap 9.3's `priceCrossings(in:levels:)`) — a demonstration of the
    // primitive, not a real alerting system: no persistence, no notification, just a banner. See
    // `MarketChartSection.checkPriceAlert`.
    @State private var alertLevelText = ""
    @State private var activeAlertLevel: Double?

    var body: some View {
        let configuration = FeedConfiguration(source: source, product: product, timeframe: timeframe, attempt: attempt)

        NavigationStack {
            VStack(spacing: 12) {
                Picker("Timeframe", selection: $timeframe) {
                    ForEach(Timeframe.allCases) { timeframe in
                        Text(timeframe.label).tag(timeframe)
                    }
                }
                .pickerStyle(.segmented)

                DrawingToolPicker(
                    activeTool: $activeDrawingTool,
                    drawings: $drawings,
                    selectedDrawingID: $selectedDrawingID,
                    drawingColor: $drawingColor
                )

                PriceAlertRow(levelText: $alertLevelText, activeLevel: $activeAlertLevel)

                // `feed` streams a new candle (or updates the in-progress one) on every live trade —
                // often several times a second. Isolated into its own `View` (below) so that reading
                // `feed.candles` doesn't taint *this* body's own Observation scope: before this was
                // split out, `feed.candles` was read directly here (via this same chart content and
                // a `.animation(value: feed.candles.isEmpty)`), which meant every trade re-evaluated
                // all of `MarketView.body` — including `optionsMenu` below, even though its own
                // content never reads `feed` at all. That's what looked like "the menu always gets
                // refreshed": the toolbar's `Menu` was being torn down and rebuilt on every tick,
                // since it was inlined as a plain computed property in the same body. See
                // `JumpToLatestButton` further down for the same isolation principle already
                // established elsewhere in this file.
                MarketChartSection(
                    feed: feed,
                    chartState: chartState,
                    product: product,
                    indicators: indicators,
                    showsVolume: showsVolume,
                    style: style,
                    alertLevel: activeAlertLevel,
                    attempt: $attempt,
                    source: $source,
                    drawings: $drawings,
                    activeDrawingTool: $activeDrawingTool,
                    selectedDrawingID: $selectedDrawingID,
                    drawingColor: drawingColor
                )
                .frame(maxHeight: .infinity)

                footer
            }
            .padding()
            .navigationTitle(product.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FeedStatusBadge(status: feed.status, source: source)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ChartOptionsMenu(
                        source: $source,
                        product: $product,
                        showsSMA: $showsSMA,
                        showsEMA: $showsEMA,
                        showsBollinger: $showsBollinger,
                        showsVWAP: $showsVWAP,
                        showsVolume: $showsVolume,
                        showsRSI: $showsRSI,
                        showsMACD: $showsMACD,
                        chartState: chartState,
                        onSaveLayout: saveLayout,
                        onLoadLayout: loadLayout
                    )
                }
            }
        }
        .task(id: configuration) {
            await feed.run(configuration)
        }
        .alert(item: $layoutAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: Save/Load layout (roadmap 7.3)

    /// Captures everything `ChartLayout` knows how to capture — style, the indicators currently
    /// toggled on, drawings, and scroll/zoom position — to the demo's one saved-layout slot.
    private func saveLayout() {
        let layout = ChartLayout(
            style: style.snapshot,
            indicators: indicators.map(\.persisted),
            drawings: drawings,
            viewport: chartState.currentViewport,
            timeframeIdentifier: String(timeframe.rawValue)
        )
        do {
            try DemoLayoutStorage.save(layout)
            layoutAlert = LayoutAlert(title: "Layout Saved", message: "Style, indicators, drawings and scroll position were saved.")
        } catch {
            layoutAlert = LayoutAlert(title: "Couldn't Save Layout", message: error.localizedDescription)
        }
    }

    /// Restores everything `saveLayout()` captured. Indicators are rebuilt as toggles rather than a
    /// freeform list — this demo's indicator picker is a fixed set of on/off switches, not an
    /// arbitrary catalog — by checking which of those six identifiers the saved layout contains; an
    /// app with a real indicator picker would instead rebuild each entry with
    /// `ChartIndicator.init?(_:catalog:)`, exactly as `ChartLayout+CandleKit.swift` documents.
    private func loadLayout() {
        do {
            let layout = try DemoLayoutStorage.load()
            chartState.restoreViewport(layout.viewport)
            style = CandleChartStyle(layout.style)
            drawings = layout.drawings
            applyIndicatorToggles(from: layout.indicators)
            if let identifier = layout.timeframeIdentifier,
               let rawValue = Int(identifier),
               let restored = Timeframe(rawValue: rawValue) {
                timeframe = restored
            }
            layoutAlert = LayoutAlert(title: "Layout Loaded", message: "Restored your saved style, indicators, drawings and scroll position.")
        } catch {
            layoutAlert = LayoutAlert(title: "Couldn't Load Layout", message: error.localizedDescription)
        }
    }

    private func applyIndicatorToggles(from persisted: [PersistedIndicator]) {
        showsSMA = persisted.contains {
            $0.descriptor.identifier == "ma" && $0.descriptor.parameters["method"]?.stringValue == "SMA"
        }
        showsEMA = persisted.contains {
            $0.descriptor.identifier == "ma" && $0.descriptor.parameters["method"]?.stringValue == "EMA"
        }
        showsBollinger = persisted.contains { $0.descriptor.identifier == "bollinger" }
        showsVWAP = persisted.contains { $0.descriptor.identifier == "vwap" }
        showsRSI = persisted.contains { $0.descriptor.identifier == "rsi" }
        showsMACD = persisted.contains { $0.descriptor.identifier == "macd" }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Drag to scroll, pinch to zoom, long-press to inspect, double-tap to reset.")
            Text(source == .coinbase ? "Market data from the Coinbase Exchange public API." : "Simulated prices, not real market data.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    private var indicators: [ChartIndicator] {
        var result: [ChartIndicator] = []
        if showsSMA { result.append(.sma(20)) }
        if showsEMA { result.append(.ema(50, color: .blue)) }
        // Exercises the multi-plot and fill paths, which a plain moving average never touches.
        if showsBollinger { result.append(.bollingerBands()) }
        if showsVWAP { result.append(.vwap()) }
        // These draw in their own panes below the candles.
        if showsRSI { result.append(.rsi(14)) }
        if showsMACD { result.append(.macd()) }
        return result
    }
}

/// Everything that depends on `feed.candles` — which changes on every live trade — lives here, in
/// its own `View`. That scopes the resulting high-frequency re-renders to just this chart, instead
/// of to the whole of `MarketView.body` (and, with it, the toolbar's menu). See the comment where
/// this is used above for the bug this fixes.
private struct MarketChartSection: View {
    let feed: MarketFeed
    let chartState: CandleChartState
    let product: Product
    let indicators: [ChartIndicator]
    let showsVolume: Bool
    let style: CandleChartStyle
    /// The level entered in `PriceAlertRow`, or `nil` when no alert is set.
    let alertLevel: Double?
    @Binding var attempt: Int
    @Binding var source: DataSourceKind
    @Binding var drawings: [Drawing]
    @Binding var activeDrawingTool: DrawingTool?
    @Binding var selectedDrawingID: UUID?
    let drawingColor: DrawingColor

    /// Transient text shown when `alertLevel` fires — cleared a couple of seconds later. Demo-only
    /// UI; a real app would want a system notification instead (see `priceCrossings` doc comment on
    /// why CandleKit doesn't provide one itself).
    @State private var firedAlertText: String?

    var body: some View {
        chart
            .animation(.easeInOut(duration: 0.15), value: feed.candles.isEmpty)
            .overlay(alignment: .top) {
                if let firedAlertText {
                    Text(firedAlertText)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.orange, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            // Re-checked on every update, not just when a new candle is appended — a live tick that
            // updates the in-progress candle in place can cross the level just as well, and
            // `priceCrossings` is written to handle both cases identically (see its doc comment).
            .onChange(of: feed.candles) { _, candles in
                checkPriceAlert(candles)
            }
    }

    /// Roadmap 9.3's `priceCrossings(in:levels:)`, wired to the one level this demo lets you set.
    private func checkPriceAlert(_ candles: [Candle]) {
        guard let alertLevel else { return }
        let crossings = priceCrossings(in: candles, levels: [alertLevel])
        guard let crossing = crossings.first else { return }
        let direction = crossing.direction == .upward ? "up through" : "down through"
        let digits = PriceScale.suggestedFractionDigits(forPrice: alertLevel)
        let level = String(format: "%.\(digits)f", alertLevel)
        withAnimation {
            firedAlertText = "\(product.name) crossed \(direction) \(level)"
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { firedAlertText = nil }
        }
    }

    // When candles.isEmpty flips, the .animation modifier above crossfades between
    // the skeleton and the real chart. Using if/else (not switch) so SwiftUI can track
    // view identity and apply .transition(.opacity) on each branch correctly.
    @ViewBuilder
    private var chart: some View {
        if !feed.candles.isEmpty {
            realChart
                .transition(.opacity)
        } else if let message = failureMessage {
            ContentUnavailableView {
                Label("Couldn't load \(product.id)", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { attempt += 1 }
                    .buttonStyle(.borderedProminent)
                Button("Use simulated data") { source = .simulated }
            }
            .transition(.opacity)
        } else {
            SkeletonChartView()
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var realChart: some View {
        CandlestickChart(feed.candles, state: chartState)
            // Frosted price axis with candles peeking through as they scroll underneath — opted in
            // explicitly here since the library default keeps the classic opaque axis unchanged.
            // App-owned state, not a constant, so Save/Load Layout has something to restore.
            .candleChartStyle(style)
            .indicators(indicators)
            .volumeVisible(showsVolume)
            .drawings($drawings)
            .drawingTool($activeDrawingTool)
            .selectedDrawing($selectedDrawingID)
            .defaultDrawingStyle(DrawingStyle(color: drawingColor))
            .onReachOldestCandle { feed.loadOlder() }
            .overlay(alignment: .bottomTrailing) {
                // Clears the price and time axes.
                JumpToLatestButton(state: chartState)
                    .padding(.trailing, 72)
                    .padding(.bottom, 32)
            }
    }

    private var failureMessage: String? {
        guard feed.candles.isEmpty, case let .failed(message) = feed.status else { return nil }
        return message
    }
}

/// Simple `Identifiable` wrapper so a save/load result can drive `.alert(item:)`.
private struct LayoutAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// A single text field + button that demonstrates roadmap 9.3's `priceCrossings(in:levels:)` — see
/// `MarketChartSection.checkPriceAlert`. Deliberately minimal: one level, no persistence, no real
/// notification, matching CandleKit's own stance of shipping the primitive and not an alerting
/// system.
private struct PriceAlertRow: View {
    @Binding var levelText: String
    @Binding var activeLevel: Double?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell")
                .foregroundStyle(.secondary)
            TextField("Alert price", text: $levelText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            if activeLevel != nil {
                Button("Clear") {
                    activeLevel = nil
                    levelText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Set Alert") {
                    activeLevel = Double(levelText)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(Double(levelText) == nil)
            }
        }
    }
}

/// Picks which drawing tool a one-finger drag creates (see `docs/design/drawing-tools.md` §2), or
/// goes back to the ordinary cursor/pan behavior with `nil`. Text-labeled rather than icon-only, to
/// keep this demo screen free of guessing at SF Symbol names. Its own content never reads `feed`, so
/// — like `ChartOptionsMenu` — it doesn't retrigger on a live trade.
private struct DrawingToolPicker: View {
    @Binding var activeTool: DrawingTool?
    @Binding var drawings: [Drawing]
    @Binding var selectedDrawingID: UUID?
    @Binding var drawingColor: DrawingColor

    // Tier 1, in the order the roadmap lists them. The measure tool isn't here — it isn't
    // implemented yet (see the roadmap's 6.3 entry for why it doesn't fit this same model).
    private static let tools: [(tool: DrawingTool, label: String)] = [
        (.horizontalLine, "H-Line"),
        (.horizontalRay, "H-Ray"),
        (.verticalLine, "V-Line"),
        (.trendLine, "Trend"),
        (.ray, "Ray"),
        (.rectangle, "Rect"),
        (.fibonacciRetracement, "Fib"),
        (.textNote, "Note"),
    ]

    // A trader's usual palette: bullish green and bearish red for marking support/resistance in the
    // direction they mean it, plus a neutral blue (the library default), amber for "watch this," and
    // white/black for a line that has to stay visible on either a light or dark chart background.
    private static let palette: [DrawingColor] = [
        DrawingColor(red: 0.2, green: 0.5, blue: 0.95),   // blue (default)
        DrawingColor(red: 0.16, green: 0.76, blue: 0.44), // bullish green
        DrawingColor(red: 0.93, green: 0.27, blue: 0.29), // bearish red
        DrawingColor(red: 0.98, green: 0.65, blue: 0.12), // amber
        DrawingColor(red: 0.65, green: 0.42, blue: 0.98), // violet
        DrawingColor(red: 0.95, green: 0.95, blue: 0.95), // near-white
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    cursorButton
                    ForEach(Self.tools, id: \.tool) { entry in
                        toolButton(entry.tool, label: entry.label)
                    }
                    if selectedDrawingID != nil {
                        Divider().frame(height: 20)
                        Button("Delete", role: .destructive) {
                            drawings.removeAll { $0.id == selectedDrawingID }
                            selectedDrawingID = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if !drawings.isEmpty {
                        Button("Clear all") {
                            drawings.removeAll()
                            selectedDrawingID = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 2)
            }

            // Sets the color the *next* drawing starts as; when something is already selected, it
            // also recolors that drawing immediately, so the same row does the obvious thing whether
            // you're about to draw or already have something picked — no separate "edit" mode needed.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.palette.indices, id: \.self) { index in
                        swatchButton(Self.palette[index])
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var cursorButton: some View {
        Button("Cursor") { activeTool = nil }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(activeTool == nil ? .accentColor : .secondary)
    }

    private func toolButton(_ tool: DrawingTool, label: String) -> some View {
        Button(label) {
            // Tapping the already-active tool again is the "done drawing" exit back to cursor mode
            // the design note calls for, instead of a separate dedicated button for it.
            activeTool = (activeTool == tool) ? nil : tool
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(activeTool == tool ? .accentColor : .secondary)
    }

    private func swatchButton(_ color: DrawingColor) -> some View {
        Button {
            drawingColor = color
            if let selectedDrawingID, let index = drawings.firstIndex(where: { $0.id == selectedDrawingID }) {
                drawings[index].style.color = color
            }
        } label: {
            Circle()
                .fill(Color(color))
                .frame(width: 22, height: 22)
                .overlay(
                    Circle().strokeBorder(.primary, lineWidth: color == drawingColor ? 2 : 0)
                )
                .overlay(Circle().stroke(.secondary.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

/// The toolbar's "Chart options" menu, as its own `View` rather than a computed property inlined
/// into `MarketView.body`. Its own content never reads `feed`, so on its own this wasn't the source
/// of the "menu keeps refreshing" bug — `MarketView.body` re-evaluating on every trade tick was —
/// but keeping it as a dedicated view (bindings only, no observed model) is what lets SwiftUI treat
/// it as unchanged, and its open `Menu` popover undisturbed, whenever an ancestor's body does still
/// re-run for an unrelated reason.
private struct ChartOptionsMenu: View {
    @Binding var source: DataSourceKind
    @Binding var product: Product
    @Binding var showsSMA: Bool
    @Binding var showsEMA: Bool
    @Binding var showsBollinger: Bool
    @Binding var showsVWAP: Bool
    @Binding var showsVolume: Bool
    @Binding var showsRSI: Bool
    @Binding var showsMACD: Bool
    let chartState: CandleChartState
    let onSaveLayout: () -> Void
    let onLoadLayout: () -> Void

    var body: some View {
        Menu {
            Section("Layout") {
                Button("Save Layout", systemImage: "square.and.arrow.down") { onSaveLayout() }
                Button("Load Layout", systemImage: "square.and.arrow.up") { onLoadLayout() }
                    .disabled(!DemoLayoutStorage.hasSavedLayout)
            }
            Picker("Data", selection: $source) {
                ForEach(DataSourceKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            Picker("Market", selection: $product) {
                ForEach(Product.all) { product in
                    Text("\(product.name) (\(product.id))").tag(product)
                }
            }
            Section("Overlays") {
                Toggle("SMA 20", isOn: $showsSMA)
                Toggle("EMA 50", isOn: $showsEMA)
                Toggle("Bollinger Bands", isOn: $showsBollinger)
                Toggle("VWAP", isOn: $showsVWAP)
                Toggle("Volume", isOn: $showsVolume)
            }
            Section("Panes") {
                Toggle("RSI 14", isOn: $showsRSI)
                Toggle("MACD", isOn: $showsMACD)
            }
            Button("Reset zoom", systemImage: "arrow.counterclockwise") {
                // Same spring as double-tap-to-reset on the chart itself, so the menu action and
                // the gesture that does the same thing feel the same.
                chartState.animatedResetZoom()
            }
        } label: {
            Label("Chart options", systemImage: "slider.horizontal.3")
        }
    }
}

/// Lives in its own view so that only this button, not the whole screen, re-renders while the chart scrolls.
struct JumpToLatestButton: View {
    let state: CandleChartState

    var body: some View {
        if !state.isFollowingLatest {
            Button {
                // Matches the spring double-tap-to-reset already uses, instead of a hard snap —
                // and automatically respects Reduce Motion, since that check lives in CandleKit.
                state.animatedScrollToLatest()
            } label: {
                Label("Latest", systemImage: "arrow.right.to.line")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }
}

struct FeedStatusBadge: View {
    let status: MarketFeed.Status
    let source: DataSourceKind

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch status {
        case .loading: return "Connecting"
        case .streaming: return source == .coinbase ? "Live" : "Simulated"
        case .reconnecting: return "Reconnecting"
        case .failed: return "Offline"
        }
    }

    private var color: Color {
        switch status {
        case .loading, .reconnecting: return .orange
        case .streaming: return source == .coinbase ? .green : .blue
        case .failed: return .red
        }
    }
}

#Preview {
    MarketView()
}
