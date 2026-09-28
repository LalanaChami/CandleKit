import CandleKit
import SwiftUI
import UIKit

/// Centralizes the demo's haptic vocabulary so every interactive control speaks the same language:
/// a light tap for picking/toggling something, a slightly firmer one for a committing action
/// (saving, deleting), and the two system notification feels for "this succeeded" / "this fired."
/// Real trading apps lean on this kind of consistent tactile feedback heavily — it's what makes a
/// dense, information-first screen still feel responsive rather than just busy.
private enum Haptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func commit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func alertFired() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

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

    // Named, multi-slot layouts (roadmap 7.3 + the obvious follow-up: more than one saved preset).
    // `savedLayouts` mirrors `DemoLayoutStorage`'s file and is only ever refreshed by re-reading it
    // after a write, so the sheet's list and the toolbar's badge can't drift from what's on disk.
    @State private var savedLayouts: [SavedLayout] = DemoLayoutStorage.loadAll()
    @State private var showingLayoutsSheet = false
    @State private var showingChartOptions = false
    @State private var pendingSaveName = ""
    @State private var showingSaveNamePrompt = false
    @State private var toast: Toast?

    // Price alert row (roadmap 9.3's `priceCrossings(in:levels:)`) — a demonstration of the
    // primitive, not a real alerting system: no persistence, no notification, just a banner. See
    // `MarketChartSection.checkPriceAlert`.
    @State private var alertLevelText = ""
    @State private var activeAlertLevel: Double?

    var body: some View {
        let configuration = FeedConfiguration(source: source, product: product, timeframe: timeframe, attempt: attempt)

        NavigationStack {
            // The chart is the base layer, edge to edge — every other control here is a floating
            // overlay on top of it rather than a permanent row that pushes it down. That's the
            // difference between "a chart with a toolbar above it" and "a screen that's mostly
            // chart," which is what a trader actually wants most of their time in this tab.
            ZStack {
                // See the comment on this type below for why `feed.candles` (which changes on every
                // live trade) is isolated to its own `View` instead of read directly here.
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
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    HStack {
                        TimeframeStrip(timeframe: $timeframe)
                        Spacer(minLength: 0)
                    }
                    // CandleKit draws its own latest-value header (a large last-price line, then a
                    // date + OHLC + volume line) across the top of the chart itself; this clears
                    // that whole band instead of sitting on top of it.
                    .padding(.top, 58)

                    Spacer(minLength: 0)

                    FloatingToolDock(
                        activeTool: $activeDrawingTool,
                        drawings: $drawings,
                        selectedDrawingID: $selectedDrawingID,
                        drawingColor: $drawingColor,
                        alertLevelText: $alertLevelText,
                        activeAlertLevel: $activeAlertLevel
                    )
                    .padding(.bottom, 10)
                }
            }
            .padding(.horizontal, 12)
            .navigationTitle(product.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FeedStatusBadge(status: feed.status, source: source)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showingChartOptions = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(.thinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Chart options")
                }
            }
            .overlay(alignment: .top) {
                if let toast {
                    ToastView(toast: toast)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toast)
        }
        .task(id: configuration) {
            await feed.run(configuration)
        }
        .sheet(isPresented: $showingLayoutsSheet) {
            LayoutsSheet(
                layouts: savedLayouts,
                onLoad: { loadLayout($0) },
                onOverwrite: { overwriteLayout($0) },
                onRename: { id, name in
                    savedLayouts = (try? DemoLayoutStorage.rename(id: id, to: name)) ?? savedLayouts
                },
                onDelete: { id in
                    savedLayouts = (try? DemoLayoutStorage.delete(id: id)) ?? savedLayouts
                    Haptics.tap()
                },
                onSaveCurrentAsNew: {
                    showingLayoutsSheet = false
                    pendingSaveName = defaultLayoutName()
                    showingSaveNamePrompt = true
                }
            )
        }
        .sheet(isPresented: $showingChartOptions) {
            ChartOptionsSheet(
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
                savedLayoutCount: savedLayouts.count,
                onOpenLayouts: { showingLayoutsSheet = true }
            )
        }
        .alert("Save Layout", isPresented: $showingSaveNamePrompt) {
            TextField("Layout name", text: $pendingSaveName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveNewLayout(named: pendingSaveName) }
        } message: {
            Text("Style, indicators, drawings and scroll position will be saved under this name.")
        }
    }

    // MARK: Save/Load layout (roadmap 7.3), now as named, multi-slot presets

    private func defaultLayoutName() -> String {
        "\(product.name) \(timeframe.label)"
    }

    private func currentLayout() -> ChartLayout {
        ChartLayout(
            style: style.snapshot,
            indicators: indicators.map(\.persisted),
            drawings: drawings,
            viewport: chartState.currentViewport,
            timeframeIdentifier: String(timeframe.rawValue)
        )
    }

    private func saveNewLayout(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            savedLayouts = try DemoLayoutStorage.add(name: name, layout: currentLayout())
            Haptics.success()
            showToast(.success(title: "Layout Saved", message: "\u{201C}\(name)\u{201D} is ready to load anytime."))
        } catch {
            showToast(.failure(title: "Couldn't Save Layout", message: error.localizedDescription))
        }
    }

    /// Re-captures the current chart into a preset that already exists — the "update this one"
    /// gesture a trader reaches for after tweaking a layout they already saved, rather than piling
    /// up near-duplicate entries every time they adjust a color or add a line.
    private func overwriteLayout(_ existing: SavedLayout) {
        do {
            savedLayouts = try DemoLayoutStorage.overwrite(id: existing.id, layout: currentLayout())
            Haptics.success()
            showToast(.success(title: "Layout Updated", message: "\u{201C}\(existing.name)\u{201D} now matches the current chart."))
        } catch {
            showToast(.failure(title: "Couldn't Update Layout", message: error.localizedDescription))
        }
    }

    /// Restores everything `saveNewLayout(named:)` captured. Indicators are rebuilt as toggles
    /// rather than a freeform list — this demo's indicator picker is a fixed set of on/off switches,
    /// not an arbitrary catalog — by checking which of those six identifiers the saved layout
    /// contains; an app with a real indicator picker would instead rebuild each entry with
    /// `ChartIndicator.init?(_:catalog:)`, exactly as `ChartLayout+CandleKit.swift` documents.
    private func loadLayout(_ saved: SavedLayout) {
        showingLayoutsSheet = false
        let layout = saved.layout
        withAnimation(.easeInOut(duration: 0.2)) {
            chartState.restoreViewport(layout.viewport)
            style = CandleChartStyle(layout.style)
            drawings = layout.drawings
            applyIndicatorToggles(from: layout.indicators)
        }
        if let identifier = layout.timeframeIdentifier,
           let rawValue = Int(identifier),
           let restored = Timeframe(rawValue: rawValue) {
            timeframe = restored
        }
        Haptics.success()
        showToast(.success(title: "Layout Loaded", message: "Restored \u{201C}\(saved.name)\u{201D}."))
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

    private func showToast(_ toast: Toast) {
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if self.toast?.id == toast.id {
                self.toast = nil
            }
        }
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
/// of to the whole of `MarketView.body` (and, with it, the toolbar's options button). See the
/// comment where this is used above for the bug this fixes.
private struct MarketChartSection: View {
    let feed: MarketFeed
    let chartState: CandleChartState
    let product: Product
    let indicators: [ChartIndicator]
    let showsVolume: Bool
    let style: CandleChartStyle
    /// The level entered in the floating alert control, or `nil` when no alert is set.
    let alertLevel: Double?
    @Binding var attempt: Int
    @Binding var source: DataSourceKind
    @Binding var drawings: [Drawing]
    @Binding var activeDrawingTool: DrawingTool?
    @Binding var selectedDrawingID: UUID?
    let drawingColor: DrawingColor

    /// The alert banner's content, or `nil` when nothing has fired recently. Carries direction so
    /// the banner can color and haptic itself accordingly, instead of always reading as a flat
    /// warning regardless of whether price broke up through the level or down through it.
    @State private var firedAlert: FiredAlert?

    var body: some View {
        // Refreshed on every body evaluation — cheap, and keeps the closure's captured `alertLevel`
        // current whenever the parent passes a new one. Deliberately not a SwiftUI
        // `.onChange(of: feed.candles)`: `MarketFeed.liveTrades` can deliver a burst of several
        // trades within one runloop turn, each mutating `candles` in turn, which fires `.onChange`'s
        // action more than once before SwiftUI renders a frame in between — the "action tried to
        // update multiple times per frame" diagnostic. Hooking the model's own mutation point via
        // `setOnLiveTick` instead has no such frame dependency; see its doc comment in
        // `MarketFeed.swift`. `priceCrossings` handles a newly appended candle and an in-place tick
        // update identically (see its own doc comment), so this needs no case-by-case logic here.
        let _ = feed.setOnLiveTick { candles in checkPriceAlert(candles) }
        chart
            .animation(.easeInOut(duration: 0.15), value: feed.candles.isEmpty)
            .overlay(alignment: .top) {
                if let firedAlert {
                    AlertFiredBanner(alert: firedAlert)
                        // Clears both CandleKit's own header band and the floating timeframe strip.
                        .padding(.top, 108)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: firedAlert)
    }

    /// Roadmap 9.3's `priceCrossings(in:levels:)`, wired to the one level this demo lets you set.
    private func checkPriceAlert(_ candles: [Candle]) {
        guard let alertLevel else { return }
        let crossings = priceCrossings(in: candles, levels: [alertLevel])
        guard let crossing = crossings.first else { return }
        let digits = PriceScale.suggestedFractionDigits(forPrice: alertLevel)
        let level = String(format: "%.\(digits)f", alertLevel)
        firedAlert = FiredAlert(direction: crossing.direction, text: "\(product.name) crossed \(level)")
        Haptics.alertFired()
        Task {
            try? await Task.sleep(for: .seconds(4))
            firedAlert = nil
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
                // Clears the price axis and the floating tool dock pinned to the bottom of the chart.
                JumpToLatestButton(state: chartState)
                    .padding(.trailing, 16)
                    .padding(.bottom, 118)
            }
    }

    private var failureMessage: String? {
        guard feed.candles.isEmpty, case let .failed(message) = feed.status else { return nil }
        return message
    }
}

/// A crossing the price alert just fired, with enough to color and word the banner. `Equatable` so
/// the `.animation(value:)` above only replays when the content actually changes.
private struct FiredAlert: Equatable {
    let direction: PriceCrossDirection
    let text: String
}

private struct AlertFiredBanner: View {
    let alert: FiredAlert

    var body: some View {
        Label {
            Text(alert.text).font(.callout.weight(.semibold))
        } icon: {
            Image(systemName: alert.direction == .upward ? "arrow.up.right" : "arrow.down.right")
                .font(.callout.weight(.bold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(tint.gradient, in: Capsule())
        .shadow(color: tint.opacity(0.35), radius: 10, y: 4)
    }

    private var tint: Color { alert.direction == .upward ? .green : .red }
}

/// A single, transient toast for non-blocking feedback (layout saved/loaded/failed) — replaces the
/// old modal `.alert(item:)`, which stopped a trader mid-flow to acknowledge routine confirmations
/// that don't need a decision. Errors still get a title distinct enough (red, exclamation mark) to
/// register as more than a passing confirmation, without blocking interaction with the chart.
private struct Toast: Identifiable, Equatable {
    enum Kind: Equatable { case success, failure }
    let id = UUID()
    let kind: Kind
    let title: String
    let message: String

    static func success(title: String, message: String) -> Toast { Toast(kind: .success, title: title, message: message) }
    static func failure(title: String, message: String) -> Toast { Toast(kind: .failure, title: title, message: message) }
}

private struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toast.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(toast.kind == .success ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.subheadline.weight(.semibold))
                Text(toast.message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        .padding(.horizontal)
    }
}

/// The timeframe control, redrawn as a floating strip of pill buttons over the top of the chart
/// instead of a permanent `.segmented` `Picker` row above it. Scrolls horizontally so adding more
/// timeframes later doesn't force a redesign, and — like the rest of the floating chrome here —
/// costs the chart no reserved vertical space at all.
private struct TimeframeStrip: View {
    @Binding var timeframe: Timeframe

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Timeframe.allCases) { entry in
                    pill(entry)
                }
            }
            .padding(4)
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.4)))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func pill(_ entry: Timeframe) -> some View {
        let isSelected = entry == timeframe
        return Button {
            guard !isSelected else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                timeframe = entry
            }
        } label: {
            Text(entry.label)
                .font(.footnote.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        Capsule().fill(Color.accentColor.gradient)
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
}

/// The bottom floating dock: drawing tools on the left, the price-alert control on the right,
/// sharing one frosted-glass surface instead of two separate rows competing for space above the
/// chart. Together with `TimeframeStrip` above, this is the whole of what used to be four
/// permanently-stacked rows (timeframe, drawing tools, alert row, footer) — now zero of them
/// reserve layout space, so the chart itself gets the screen back.
private struct FloatingToolDock: View {
    @Binding var activeTool: DrawingTool?
    @Binding var drawings: [Drawing]
    @Binding var selectedDrawingID: UUID?
    @Binding var drawingColor: DrawingColor
    @Binding var alertLevelText: String
    @Binding var activeAlertLevel: Double?

    var body: some View {
        HStack(spacing: 8) {
            DrawingToolPicker(
                activeTool: $activeTool,
                drawings: $drawings,
                selectedDrawingID: $selectedDrawingID,
                drawingColor: $drawingColor
            )

            Divider().frame(height: 26)

            PriceAlertControl(levelText: $alertLevelText, activeLevel: $activeAlertLevel)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.separator.opacity(0.4)))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
    }
}

/// A single bell control that expands in place into a compact price field + action, instead of a
/// permanently-open text row competing for space. Collapsed, it's just an icon with a dot when an
/// alert is armed; tapping it reveals a fixed-width field with a spring, so it slots into
/// `FloatingToolDock` without the dock's width jumping around unpredictably.
private struct PriceAlertControl: View {
    @Binding var levelText: String
    @Binding var activeLevel: Double?
    @FocusState private var fieldFocused: Bool
    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                if isExpanded { fieldFocused = true }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: activeLevel != nil ? "bell.fill" : "bell")
                        .font(.body.weight(.medium))
                        .foregroundStyle(activeLevel != nil ? .orange : .secondary)
                        .frame(width: 34, height: 34)
                        .background(.thinMaterial, in: Circle())
                    if activeLevel != nil {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(activeLevel != nil ? "Price alert armed" : "Set a price alert")

            if isExpanded || activeLevel != nil {
                TextField("Price", text: $levelText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 84)
                    .focused($fieldFocused)
                    .transition(.move(edge: .trailing).combined(with: .opacity))

                if activeLevel != nil {
                    Button {
                        Haptics.tap()
                        withAnimation(.easeOut(duration: 0.2)) {
                            activeLevel = nil
                            levelText = ""
                            isExpanded = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                } else {
                    Button {
                        Haptics.commit()
                        activeLevel = Double(levelText)
                        fieldFocused = false
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Double(levelText) == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor.gradient), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(Double(levelText) == nil)
                    .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: activeLevel)
    }
}

/// Picks which drawing tool a one-finger drag creates (see `docs/design/drawing-tools.md` §2), or
/// goes back to the ordinary cursor/pan behavior with `nil`. Icon-first, the way every real charting
/// app (TradingView, Bloomberg) presents this — a trader recognizes the shapes faster than reading
/// eight short labels, and it lets the whole strip stay one comfortable row of 36pt targets instead
/// of variable-width text pills. The color row only appears while it's relevant (a tool is active,
/// or something's selected), so cursor mode — the common case — doesn't pay for it in vertical space.
/// Its own content never reads `feed`, so — like `ChartOptionsSheet` — it doesn't retrigger on a
/// live trade.
private struct DrawingToolPicker: View {
    @Binding var activeTool: DrawingTool?
    @Binding var drawings: [Drawing]
    @Binding var selectedDrawingID: UUID?
    @Binding var drawingColor: DrawingColor

    // Tier 1, in the order the roadmap lists them, paired with an SF Symbol that reads as its shape
    // at a glance. `rotation` reuses a single "short line" glyph for both line tools rather than
    // hunting for two separate symbols that don't visually match each other.
    private static let tools: [(tool: DrawingTool, label: String, systemImage: String, rotation: Angle)] = [
        (.horizontalLine, "H-Line", "minus", .degrees(0)),
        (.horizontalRay, "H-Ray", "arrow.right", .degrees(0)),
        (.verticalLine, "V-Line", "minus", .degrees(90)),
        (.trendLine, "Trend", "chart.line.uptrend.xyaxis", .degrees(0)),
        (.ray, "Ray", "arrow.up.right", .degrees(0)),
        (.rectangle, "Rect", "rectangle", .degrees(0)),
        (.fibonacciRetracement, "Fib", "percent", .degrees(0)),
        (.textNote, "Note", "text.bubble", .degrees(0)),
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

    private var showsColorRow: Bool { activeTool != nil || selectedDrawingID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    cursorButton
                    ForEach(Self.tools, id: \.tool) { entry in
                        toolButton(entry)
                    }
                    if selectedDrawingID != nil {
                        Divider().frame(height: 20).padding(.horizontal, 2)
                        iconButton(systemImage: "trash", tint: .red) {
                            Haptics.commit()
                            drawings.removeAll { $0.id == selectedDrawingID }
                            selectedDrawingID = nil
                        }
                    }
                    if !drawings.isEmpty {
                        iconButton(systemImage: "xmark.circle", tint: .secondary) {
                            Haptics.commit()
                            drawings.removeAll()
                            selectedDrawingID = nil
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(width: 210, alignment: .leading)
            .clipped()

            // Sets the color the *next* drawing starts as; when something is already selected, it
            // also recolors that drawing immediately, so the same row does the obvious thing whether
            // you're about to draw or already have something picked — no separate "edit" mode needed.
            if showsColorRow {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Self.palette.indices, id: \.self) { index in
                            swatchButton(Self.palette[index])
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(width: 210, alignment: .leading)
                .clipped()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: showsColorRow)
    }

    private var cursorButton: some View {
        iconButton(systemImage: "cursorarrow", tint: activeTool == nil ? .accentColor : .secondary, filled: activeTool == nil) {
            Haptics.selection()
            activeTool = nil
        }
    }

    private func toolButton(_ entry: (tool: DrawingTool, label: String, systemImage: String, rotation: Angle)) -> some View {
        let isActive = activeTool == entry.tool
        return iconButton(systemImage: entry.systemImage, tint: isActive ? .accentColor : .secondary, filled: isActive, rotation: entry.rotation) {
            Haptics.selection()
            // Tapping the already-active tool again is the "done drawing" exit back to cursor mode
            // the design note calls for, instead of a separate dedicated button for it.
            activeTool = isActive ? nil : entry.tool
        }
        .accessibilityLabel(entry.label)
    }

    /// One consistent 34pt tappable circle for every tool/action in this strip — filled and tinted
    /// when it's the active selection, a light material button otherwise, with a small spring "pop"
    /// on selection so picking a tool has the same tactile snap as the color swatches below it.
    private func iconButton(
        systemImage: String,
        tint: Color,
        filled: Bool = false,
        rotation: Angle = .degrees(0),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .rotationEffect(rotation)
                .foregroundStyle(filled ? .white : tint)
                .frame(width: 32, height: 32)
                .background {
                    if filled {
                        Circle().fill(tint.gradient)
                    } else {
                        Circle().fill(.thinMaterial)
                    }
                }
                .scaleEffect(filled ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: filled)
    }

    private func swatchButton(_ color: DrawingColor) -> some View {
        let isSelected = color == drawingColor
        return Button {
            Haptics.selection()
            drawingColor = color
            if let selectedDrawingID, let index = drawings.firstIndex(where: { $0.id == selectedDrawingID }) {
                drawings[index].style.color = color
            }
        } label: {
            Circle()
                .fill(Color(color))
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.white, lineWidth: isSelected ? 2.5 : 0))
                .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 0.5))
                .scaleEffect(isSelected ? 1.15 : 1.0)
                .shadow(color: isSelected ? Color(color).opacity(0.5) : .clear, radius: 4)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
}

/// The chart-options surface, redesigned as a modern grouped sheet — icon tiles you tap to toggle,
/// cards for the compound rows — instead of the plain system `Menu` dropdown this replaces. A `Menu`
/// reads as a list of text rows no matter how it's labeled; this reads the way a modern settings
/// surface does, with room to breathe and glanceable icons, and it doesn't disappear the instant a
/// finger slips off a row.
private struct ChartOptionsSheet: View {
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
    let savedLayoutCount: Int
    let onOpenLayouts: () -> Void

    @Environment(\.dismiss) private var dismiss

    private struct Chip: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let binding: Binding<Bool>
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    layoutsCard
                    marketCard

                    sectionLabel("Overlays")
                    chipGrid(overlayChips)

                    sectionLabel("Panes")
                    chipGrid(paneChips)

                    resetZoomButton
                }
                .padding()
            }
            .navigationTitle("Chart Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var overlayChips: [Chip] {
        [
            Chip(id: "sma", title: "SMA 20", systemImage: "chart.line.uptrend.xyaxis", binding: $showsSMA),
            Chip(id: "ema", title: "EMA 50", systemImage: "chart.line.uptrend.xyaxis", binding: $showsEMA),
            Chip(id: "bollinger", title: "Bollinger", systemImage: "water.waves", binding: $showsBollinger),
            Chip(id: "vwap", title: "VWAP", systemImage: "chart.xyaxis.line", binding: $showsVWAP),
            Chip(id: "volume", title: "Volume", systemImage: "chart.bar.fill", binding: $showsVolume),
        ]
    }

    private var paneChips: [Chip] {
        [
            Chip(id: "rsi", title: "RSI 14", systemImage: "gauge.with.dots.needle.50percent", binding: $showsRSI),
            Chip(id: "macd", title: "MACD", systemImage: "waveform", binding: $showsMACD),
        ]
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var layoutsCard: some View {
        Button {
            dismiss()
            // Chains into the Layouts sheet once this one has finished dismissing — presenting both
            // at once races the two `.sheet` transitions against each other.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onOpenLayouts()
            }
        } label: {
            HStack(spacing: 12) {
                iconBadge("square.stack.3d.up", tint: .indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Layouts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(savedLayoutCount == 0 ? "No saved layouts yet" : "\(savedLayoutCount) saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var marketCard: some View {
        VStack(spacing: 0) {
            marketRow(icon: "antenna.radiowaves.left.and.right", tint: .blue) {
                Picker("Data", selection: $source) {
                    ForEach(DataSourceKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
            }
            Divider().padding(.leading, 50)
            marketRow(icon: "bitcoinsign.circle", tint: .orange) {
                Picker("Symbol", selection: $product) {
                    ForEach(Product.all) { product in
                        Text("\(product.name) (\(product.id))").tag(product)
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func marketRow<Content: View>(icon: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            iconBadge(icon, tint: tint)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func iconBadge(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func chipGrid(_ chips: [Chip]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(chips) { chip in
                chipButton(chip)
            }
        }
    }

    private func chipButton(_ chip: Chip) -> some View {
        let isOn = chip.binding.wrappedValue
        return Button {
            Haptics.selection()
            chip.binding.wrappedValue.toggle()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: chip.systemImage)
                    .font(.title3)
                Text(chip.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.thinMaterial))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.separator.opacity(isOn ? 0 : 0.5))
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
    }

    private var resetZoomButton: some View {
        Button {
            Haptics.tap()
            // Same spring as double-tap-to-reset on the chart itself, so the sheet action and the
            // gesture that does the same thing feel the same.
            chartState.animatedResetZoom()
            dismiss()
        } label: {
            Label("Reset Zoom", systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
    }
}

/// The named-layouts picker: every preset a trader has saved, newest first, with load-on-tap,
/// swipe-to-delete, a rename via context menu, and a "+" to capture the current chart as a new
/// entry. Replaces the single-slot Save/Load pair the first cut of this feature shipped with — the
/// obvious next step once there's more than one layout worth keeping around.
private struct LayoutsSheet: View {
    let layouts: [SavedLayout]
    let onLoad: (SavedLayout) -> Void
    let onOverwrite: (SavedLayout) -> Void
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void
    let onSaveCurrentAsNew: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: SavedLayout?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if layouts.isEmpty {
                    ContentUnavailableView {
                        Label("No Saved Layouts", systemImage: "square.stack.3d.up.slash")
                    } description: {
                        Text("Save the current style, indicators, drawings and scroll position so you can jump back to it later.")
                    } actions: {
                        Button("Save Current Chart", action: onSaveCurrentAsNew)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(layouts) { saved in
                            Button {
                                Haptics.tap()
                                onLoad(saved)
                            } label: {
                                row(for: saved)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    withAnimation { onDelete(saved.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    renameText = saved.name
                                    renaming = saved
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button {
                                    onOverwrite(saved)
                                } label: {
                                    Label("Update with Current Chart", systemImage: "arrow.triangle.2.circlepath")
                                }
                                Button {
                                    renameText = saved.name
                                    renaming = saved
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    withAnimation { onDelete(saved.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: layouts)
                }
            }
            .navigationTitle("Layouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSaveCurrentAsNew()
                    } label: {
                        Label("Save Current", systemImage: "plus.circle.fill")
                    }
                }
            }
            .alert("Rename Layout", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Layout name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let renaming {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { onRename(renaming.id, trimmed) }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(for saved: SavedLayout) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(saved.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(saved.savedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
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
            .transition(.scale.combined(with: .opacity))
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
                .shadow(color: color.opacity(0.6), radius: status == .streaming ? 3 : 0)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .animation(.easeInOut(duration: 0.2), value: status)
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
