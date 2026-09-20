# Changelog

All notable changes to CandleKit are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Nothing has been tagged yet; entries
below describe what has landed on `main` since the initial commit.

## Unreleased

### Added — layout persistence, price-crossing primitive, manual price scaling (roadmap 7.3, 9.3, 4.3)

The gap between "cool demo" and "a tool someone actually tracks a position with across days": nothing
persisted before this — every drawing, indicator, and style choice lived only in `@State` and was
lost on relaunch. This closes that gap, plus the two other most-requested trader-facing primitives.

- **`ChartLayout: Codable` (7.3).** New `CandleKitCore.ChartLayout` — style, active indicators
  (with colors, line width, visibility), drawings, and viewport, in one versioned `Codable` value.
  Reuses the existing `Codable` `Drawing` and `IndicatorDescriptor` infrastructure rather than
  inventing new serialization. `schemaVersion` is checked on decode (`ChartLayoutError
  .unsupportedSchemaVersion` on a newer, unrecognized version); `indicators`/`drawings` default to
  `[]` when absent, so a payload from a future version that added a field still loads. `Viewport` is
  now `Codable`. A new `CandleKit`-layer file, `ChartLayout+CandleKit.swift`, bridges
  `CandleChartStyle`/`ChartIndicator` (which use `SwiftUI.Color`) to and from the portable snapshot —
  the same UI-boundary pattern `DrawingColor+SwiftUI.swift` already established, which itself gained
  the reverse `DrawingColor.init(_ color: Color)` conversion needed here. `CandleChartStyle
  .priceAxisMaterial` deliberately isn't captured: `Material` has no public API to read an arbitrary
  value back into a named case, so the save direction has no possible implementation — restoring a
  layout always sets it back to `nil`, and an app using the glass axis re-applies that setting
  itself. `CandleChartState` gained `currentViewport` and `restoreViewport(_:)` so a saved viewport
  can be read back and re-applied, clamped to whatever data is currently loaded.
- **Price-crossing primitive (9.3).** New `priceCrossings(in:levels:)` (`CandleKitCore
  /PriceCrossing.swift`) — pure Foundation, no dependency on `CandlestickChart` or any chart state.
  Answers "did the price cross this level," comparing closes between the two most recent candles;
  works the same for a newly appended candle and a live tick updating the last candle in place.
  Deliberately not an alerting system — no notification scheduling, no persisted watchlist — per the
  roadmap's "what CandleKit will not become": an app wires its own notification and persistence to
  this primitive, as the Demo app now does.
- **Manual price-axis scaling (4.3).** `CandleChartState.PriceScaleMode` (`.automatic` /
  `.manual(ClosedRange<Double>)`), `setManualPriceRange(_:)`, `resetPriceScale()`, and
  `currentPriceRange`. `makeFrame` now skips autoscaling entirely while in manual mode — the range
  stays put until reset, even as new candles arrive, matching every real trading app's behavior.
  `CandlestickChart` gained a `PriceAxisScaleGesture` overlay, scoped to just the price-axis column
  (mirroring the existing glass-axis panel's positioning): drag to rescale around the range's center,
  double-tap to return to autoscale. Plain SwiftUI gestures on a new, previously-untouched region —
  not routed through the existing UIKit pan/pinch/long-press coordinator — so it can't affect
  ScrollView-embedded charts or the existing gesture set.
- **Renamed an internal type to avoid a naming collision:** `ChartFrame.swift`'s internal
  screen-layout struct (pane/axis rects) is now `ChartRegions`, freeing up the `ChartLayout` name for
  the new public persistence type above. Not part of the public API — nothing outside this package
  could have referenced the old internal name.
- **Demo app:** a "Layout" section in the chart-options menu (Save Layout / Load Layout), a price
  alert row (enter a level, get a banner when it's crossed), and the chart's style is now app-owned
  `@State` instead of a constant, so there's something for Save/Load to actually round-trip. Dragging
  the price axis works with no Demo-specific code, once the library change landed.

#### Verification

No Swift toolchain is available in the environment this was written in (`swift`/`swiftc` not found,
and `download.swift.org` was blocked), so **none of this was compiled or run** — not even the
Linux-buildable `CandleKitCore` parts, which would ordinarily be the one thing checkable from the
command line. Reviewed carefully by hand against the existing code's own patterns. Before relying on
this, at minimum: `swift build && swift test` (covers `ChartLayout`, `PriceCrossing`, and `Viewport
: Codable`, including their new test files); an iOS build (`Sources/CandleKit` and the Demo app are
untouched by any Linux-side verification); Save → relaunch → Load actually restores drawings,
indicators, and style; dragging the price axis rescales and double-tapping resets, without breaking
panning/pinching on the chart itself or scrolling on a ScrollView-embedded chart tab; and a price
alert fires on a live tick crossing the entered level.

### Added — drawing tools trader-UX pass (color, live price/time readout, haptics)

Direct feedback: drawing tools worked, but didn't yet feel like something a trader would reach for —
no way to tell what price a line sits at, no color choice, and single-anchor tools committed on a
plain tap with no chance to nudge them into place first. This pass is aimed squarely at that gap.

- **Drag-to-position for single-anchor tools.** `DrawingController.beginPrimaryGesture` no longer
  requires `anchorCount > 1` to start a live preview — a horizontal line, vertical line, or text
  note can now be pressed and dragged into place, with the same live preview multi-anchor tools
  already had, instead of only committing wherever a tap happened to land. A quick, no-drag tap
  (`handleTap`) still works exactly as before for a fast placement.
- **Live and permanent price/time axis tags.** Every horizontal line/ray shows its price on the price
  axis, and every vertical line shows its time on the time axis — both while being dragged into place
  and once committed — reusing the same `ChartText.drawPriceTag`/`drawTimeTag` primitives the chart's
  own last-price badge already draws with, so the styling matches. This is the answer to "the user
  should... know the price in which the horizontal line is drawn."
- **Live measurement badge for two-anchor tools.** While a trend line, ray, rectangle, or Fibonacci
  retracement is being dragged, a floating badge near the live anchor shows the signed price delta and
  percent change from the first anchor, colored green/red by direction — gone once the drawing is
  committed, so it doesn't clutter the chart permanently.
- **Per-drawing color.** New `CandlestickChart.defaultDrawingStyle(_:)` modifier sets what a newly
  created drawing's `style` starts as (color, line width, dash, fill opacity); `Drawing.style` was
  already per-drawing (not chart-wide), so recoloring an existing drawing — including the selected
  one — is just mutating `style.color` on the app's own `.drawings(...)` array, the same "app owns the
  array" pattern already used for deletion. `Color(_ drawingColor: DrawingColor)` is now `public` so an
  app's own color-swatch UI can render a swatch that matches exactly.
- **Haptics while drawing.** `ChartGestureCoordinator` now fires a light tap when a drawing gesture
  begins (an active tool, not a selection drag), a medium tap when it commits, and a medium tap on a
  successful quick-tap placement — reusing the existing `impactLight`/`impactMedium` generators, no
  new haptic feedback objects. The existing light tap on a new snap target is unchanged. This directly
  answers "use haptics when user is drawing the horizontal lines," generalized to every tool rather
  than special-cased to just one.
- **Demo app:** `DrawingToolPicker` gained a row of color swatches beneath the tool row. Tapping one
  sets the color the next drawing will use and, when a drawing is already selected, recolors it
  immediately — the same tap does the obvious thing in either context.

### Verification

Reviewed carefully by hand; not compiled or run on a device, same caveat as every drawing-tools change
so far in this project. The parts most worth a real-device pass: whether dragging a single-anchor
tool actually reads as "drag to position" rather than "the tap moved unexpectedly" (a UX judgment call
that needs a finger on glass, not just code review); whether the axis tags' positions stay legible
when multiple horizontal lines sit close together in price (they'll currently stack without avoiding
each other); and the haptic timing/weight (light-vs-medium, begin-vs-commit) — haptics are notoriously
hard to judge right from source alone.

### Added — Tier 2 indicator catalog (roadmap 5.6/5.7)

Twelve new indicators, closing out the Tier 2 catalog the roadmap laid out (Volume Profile
deliberately excluded — see below):

- **Trend overlays:** Donchian Channels, Keltner Channels, SuperTrend, Parabolic SAR, Ichimoku
  Cloud, Pivot Points (classic/Fibonacci/Camarilla).
- **Oscillators:** ADX/DMI, Commodity Channel Index, Money Flow Index, Williams %R, Rate of
  Change/Momentum (one indicator, a mode switch), Chaikin Money Flow.
- All twelve are `Indicator` conformances over new `IndicatorMath` functions
  (`IndicatorMathTier2.swift`), each documenting its convention the same way Tier 1 does. Reach them
  through `IndicatorCatalog.full` (standard + Tier 2) or the new `ChartIndicator` factories
  (`.donchianChannels()`, `.superTrend()`, `.adx()`, etc.).
- **The renderer's fill drawing gained real crossover-coloring support** (`IndicatorFill.colorFollowsCrossover`
  existed in the model since 5.1 but was never actually implemented — `BaseLayerRenderer.drawFills`
  always used one fixed color). Ichimoku's cloud needs this to flip between bullish and bearish
  tinting as Span A crosses Span B, so this pass implements it: a fill run splits wherever the two
  plots' raw values cross, each side colored independently. Every other fill (Bollinger, Donchian,
  Keltner) is unaffected — they don't set `colorFollowsCrossover`, so they take the same single-color
  path as before.
- **Known gap, documented rather than silently accepted:** Ichimoku's Senkou spans don't yet project
  past the most recent candle into blank future space, the way a real Ichimoku cloud does — the
  per-candle array model has no representation for a position beyond the data. Extending a pane past
  the last candle is a renderer-level change; tracked as roadmap follow-up.
- **Volume Profile deliberately not implemented.** As the roadmap already flagged, it's a horizontal
  histogram binned by price rather than a per-candle series, and doesn't fit `IndicatorResult`
  without a new output case — that's its own design task, not something to force into this pass.
- Cross-checked against an independently written Python reference implementation of each formula
  (`Tier2IndicatorMathTests.swift`), same policy and same caveat as Tier 1: internally consistent and
  formula-accurate, not yet validated against a live TradingView chart or another authoritative
  source (roadmap 5.9, now explicitly covering Tier 2 too).

### Added — drawing tools: design note, Core model, renderer, gestures (roadmap 6.1–6.3)

- **`docs/design/drawing-tools.md`** — the design note the roadmap calls for before any drawing-tool
  code: the app-owned `Codable` model anchored to `(Date, price)`, the `.drawings()`/`.drawingTool()`
  API shape, how a drawing tool's drag coexists with the chart's existing pan/pinch/long-press
  (a mode switch on the same `ChartGestureCoordinator`, not simultaneous gesture recognition), hit
  testing tolerances, z-order/lock/visibility, `UndoManager`-based undo, and a VoiceOver plan.
- **Core model** (`Sources/CandleKitCore/Drawings/`): `Drawing`, `DrawingAnchor`, `DrawingKind`,
  `DrawingTool`, `DrawingStyle`, `DrawingColor` (all `Codable`, no UI-framework dependency, same as
  the indicator model), plus `DrawingGeometry` — anchor↔position mapping against the chart's
  index-based viewport (exact match, interpolation, edge extrapolation) *and its inverse*
  (position↔anchor, for turning a live touch back into a `(Date, price)`), and
  distance-to-segment/infinite-line/ray/rectangle-edge for hit testing. All unit-tested on Linux,
  including a round-trip test (`time(forPosition:)` → `position(for:)` → back) cross-checked against
  an independent Python reference.
- **Renderer, controller, and gesture integration land on top of that model in this same pass:**
  - `DrawingsLayer`/`DrawingsLayerRenderer` — draws every visible drawing, the tool-in-progress
    preview, and the selected drawing's anchor handles.
  - `DrawingScreenMapping` — the one place anchors convert to and from screen pixels, shared by the
    renderer and hit testing so they can't independently disagree about where a drawing sits (the
    same role `CandleGeometry` plays for candle bodies, and for the same reason: that exact class of
    drift was a real, user-reported bug for the crosshair before `CandleGeometry` existed).
  - `DrawingController` — active-tool creation state, selection, whole-drawing move, and snapping to
    the nearest visible candle's OHLC within a configurable radius (roadmap 6.2), reusing the
    existing `impactLight` haptic on each new snap.
  - `ChartGestureCoordinator` gains a `drawingController` property and a guarded branch in its pan
    handler (claimed once, at gesture-began time, never renegotiated mid-drag), pinch and long-press
    now refuse to begin while a tool is active, and a new single-tap recognizer (required to fail
    against the existing double-tap) handles single-anchor placement and cursor-mode selection.
    Every one of these is a no-op path when no `.drawings(...)` is attached, so an ordinary chart's
    gesture behavior is provably unchanged.
  - New public API: `CandlestickChart.drawings(_:)` / `.drawingTool(_:)` / `.selectedDrawing(_:)`
    (the last one-way, chart → app, so an app can show its own inspector or delete button — deletion
    itself stays a plain `drawings.removeAll { ... }` on the app's own binding, per the note's §4/§5).
- **Eight of Tier 1's nine tools (6.3)** are implemented this way: horizontal line, horizontal ray,
  vertical line, trend line, ray, rectangle, Fibonacci retracement, text note. **The measure tool is
  not** — it's transient and non-persisted like the crosshair, not modeled in `DrawingKind`, and
  needs its own small piece of state rather than fitting this pass's `Drawing`-shaped machinery.
- **Known gaps, called out rather than left implicit** (see the roadmap's 6.1 entry for the full
  list): per-anchor resize (moving a selection today translates the whole drawing, not one endpoint);
  no in-chart text entry for `.textNote` yet (a tap places one with placeholder text); VoiceOver for
  drawings — both inspecting an existing one and constructing one — is still only the plan in the
  design note's §6, not code.

### Verification

None of the above has been run in an iOS build or on a device — same caveat as every other change in
this project made without a Swift toolchain available to compile or execute it. Reviewed carefully
by hand and cross-checked with independent reference logic wherever the math allowed it (the
position↔anchor round-trip in particular), but not compiled, not run, and the gesture-mode switching
in `ChartGestureCoordinator` especially deserves a real device pass before shipping — it's the part
of this codebase with the most previously hard-won, easy-to-regress correctness.

### Fixed — the toolbar's "Chart options" menu re-rendering on every live trade

Reported directly: the Demo app's menu "always gets refreshed." Root cause was `MarketView.body`
itself, not the menu: `feed.candles` (from `MarketFeed`, an `@Observable` that mutates on every
incoming trade — often several times a second for the simulated/live feed) was read directly inside
`MarketView.body`, both via a `.animation(value: feed.candles.isEmpty)` modifier and the `chart`
computed property. Since `optionsMenu` was *also* a plain computed property evaluated inside that
same `body`, every trade tick re-evaluated the whole body — including rebuilding the `Menu`'s entire
content from scratch, even though nothing in the menu itself ever reads `feed`.

- **Split `MarketView.body` into dedicated `View` types** along the same fault line the file's own
  `JumpToLatestButton` already establishes ("lives in its own view so that only this button, not the
  whole screen, re-renders"): a new `MarketChartSection` owns everything that reads `feed.candles`,
  and a new `ChartOptionsMenu` owns the toolbar menu, taking only `Binding`s and a plain
  `CandleChartState` reference — no `feed` dependency at all.
- With that split, a live trade re-renders only `MarketChartSection` (which is supposed to update
  live); `MarketView.body` and the toolbar's `Menu` are no longer touched by it.

### Verification

Not yet confirmed on a device — the fix follows an established, already-proven pattern in this same
file (`JumpToLatestButton`), and the reasoning (an `@Observable` property read inside a shared `body`
taints that whole body's Observation scope) is a well-documented SwiftUI behavior, not a guess, but
whether the menu now visibly stays put while trades stream in hasn't been eyeballed on a real device.

### Fixed — crosshair dulling moved into the real candle draw call, fixing alignment drift

Follow-up to the previous round's fix (which stopped the crosshair from dimming the whole plot and confined it to candle shapes only): that version drew the dimmed shapes as a *separate* overlay, recomputing each candle's outline independently of `BaseLayerRenderer`'s own pixel-snapped geometry. The two calculations agreed closely but not exactly, and the small, zoom-dependent gap between them was visible as the gray shapes drifting slightly out of alignment with the real candles underneath — worse at some zoom levels than others, and generally reading as a bug rather than an effect.

- **No more second shape.** `CrosshairLayer` no longer builds or fills an "other candles" overlay at all. Dulling now happens inside `BaseLayerRenderer.drawCandles` itself: candles are split into a normal-opacity batch and a reduced-opacity batch based on whether each one is the focused index, using the exact same per-candle rectangles either way. There is only ever one calculation of where a candle's edges are, so there's nothing left that could disagree with it.
- **New shared geometry helper.** `CandleGeometry.compute(index:frame:style:pixels:)` is the pixel-snapped body/wick rectangle calculation, factored out so both `BaseLayerRenderer` (drawing every candle) and `CrosshairLayer` (tracing the focused candle's glow) derive their rectangles from the same rounded numbers. The glow's outline is built from this too now, instead of its own separate, unsnapped shape — fixing the same class of drift for the glow ring itself, not just the dimming.
- **`crosshairDimOpacity` re-scoped, not renamed.** It now controls how much a non-focused candle's own fill *opacity* is reduced (blending it toward whatever's behind it), rather than the alpha of a black shape drawn on top of it. Same property, same default (0.35), same 0...1 range — just applied directly to the real draw instead of a stand-in for it.

### Verification

Not yet confirmed on a device. The geometry is now provably identical between the dimmed candles and the normally-drawn ones (same function, same inputs), which removes the specific bug reported, but the *visual* read of "opacity-reduced candle" vs. the earlier "gray tint on top of candle" hasn't been compared side by side on a screen yet — worth a look in both light and dark mode, particularly for hollow up-candles, whose stroke-only outline dims a little differently than a filled body.

### Fixed — crosshair no longer dims the whole chart, only the other candles

Follow-up to direct device feedback (screenshots in both light and dark mode): hovering the crosshair was darkening the *entire* plot area — grid, background, volume bars, indicator lines, all of it — when only the non-focused candles should recede.

- **Full-plot scrim removed.** The previous implementation filled the whole visible plot (every pane) with a blurred black scrim and cut a candle-shaped hole out of it via an even-odd fill. That's what made the whole background go gray instead of just the candles.
- **Replaced with a per-candle fill.** `CrosshairLayer.drawFocusGlow` now builds one combined path out of every *other* visible candle's own body-and-wick silhouette (`candleSilhouette(_:frame:style:expand:)`, extracted so the focused candle's glow and the dimming fill share identical geometry) and fills just that path with `style.crosshairDimOpacity`-strength black, no blur. Background, grid, axes, volume bars, and indicator lines are untouched — only candle pixels can darken.
- **Focused candle's glow is unchanged** (stroked outline, additive blend, two passes) — only what happens to the *other* candles changed.
- **Cost stays bounded to the visible window.** The dimming path is built once per crosshair move from `frame.visible` (already the on-screen candle range), not the full dataset, and filled in a single draw call.

### Verification

Not yet confirmed on a device. The geometry mirrors the existing per-candle body/wick shape used elsewhere (same rounded-rect construction, same `bodyWidthRatio`), so it should align pixel-for-pixel with the real candles underneath it, but that alignment — and whether the flat, unblurred edge reads as intentional rather than jagged at the candle boundary — needs eyes on a real screen in both light and dark mode before calling this settled.

### Changed — price axis now blends toward the background instead of standing out

Follow-up to the previous round's structural fix (plain `Material`, three-edge feathering) — this one addresses colour and opacity specifically, per feedback that the panel's own tint still read as a distinct box against its surroundings.

- **Blended toward the system background colour.** `Material` carries its own neutral grey-ish tint no matter what's behind it, which is what made it stand out rather than blend in. The panel now overlays `Color(uiColor: .systemBackground)` at low opacity on top of the material — `.systemBackground` resolves correctly in both light and dark automatically, no explicit colour-scheme branch needed.
- **More translucent than any single `Material` level allows.** There's no "thinner than ultraThin" material to reach for, so the whole panel now also gets a flat opacity reduction (0.7) on top of the background blend, for translucency `Material` alone can't reach.
- **Feather fractions widened** (leading 15%→20%, top/bottom 8%→12% each) for a smoother, less abrupt dissolve at all three edges.

### Verification

This round trades legibility against translucency more directly than the previous ones did — the whole point of a backing panel is to keep tick labels readable against moving candle colours, and turning that panel more translucent works directly against that. Whether 0.7 opacity still gives labels enough of a backdrop, or needs pulling back up, is exactly the kind of judgement call that needs eyes on a real screen, in both light and dark mode, not just reasoning.

## Earlier unreleased work

### Fixed — glass axis based on real device screenshots

The previous two rounds were reasoned about carefully but never seen rendered. This round is driven directly by screenshots showing what was actually wrong.

- **`glassEffect` reverted.** The screenshots showed visible colour-tinted glow artefacts along the top and bottom of the axis strip — greenish and blue-ish halos that clearly weren't a smooth material. `glassEffect` is a sophisticated, very new API, and diagnosing or tuning that kind of artefact without a device in hand isn't something that can be done responsibly by guessing at parameters a third time. The axis now uses a plain `Material` fill on every iOS version — predictable, well-understood, and known to adapt correctly to light and dark mode on its own. True Liquid Glass is future work, not abandoned, but it needs a way to iterate against a real device rather than another blind attempt.
- **Corner rounding and the stroke overlay removed.** A rounded shape plus a stroked outline are both hard-edged geometric treatments; layering them under an alpha feather (below) meant two different kinds of "edge" competing for attention. A plain rectangle, feathered, is simpler and was more likely to be part of what was reading as a box.
- **Feathering extended from one edge to three.** The previous version only faded the leading edge; the screenshots specifically showed hard top and bottom edges too. Two `.mask(LinearGradient)` calls now stack — leading (15%), then top/bottom (8% each) — since chained masks multiply their alpha, which is how one shape ends up faded on more than one side without hand-building a 2D gradient. The trailing edge, flush with the screen, stays fully opaque.
- **`ChartMetrics.priceAxisOverlap` raised from 28pt to 40pt** (of a ~64pt-wide axis). At 28, over a third of the axis's width had no candle content behind it at all — plain background, nothing to blur — which is what "there's still background under it" was describing. At 40, most of the axis now has real candle content sliding underneath.

### Verification

The specific claim to check is narrow and concrete: do the artefacts from the screenshots that prompted this round actually disappear. Material's own light/dark adaptation is well-established and lower-risk than the previous approach, but the exact feathering fractions (15%/8%/8%) and the overlap distance (40pt) are still first-guess numbers, not tuned ones.

## Earlier unreleased work

### Fixed — glow was washing out candle detail; axis edge still felt hard

Direct follow-up on device feedback to the previous round.

- **Crosshair glow switched from filled to stroked.** The previous version filled the focused candle's whole silhouette with a blurred, high-opacity additive colour. Blended on top of the real candle drawn underneath, that washed the shape into a bright blob rather than highlighting it — exactly the "blurs out the whole candle" symptom reported. A stroke puts the bright colour in a thin band tracing the outline only; the interior, where the real candle's colour and detail live, is untouched by the glow at all. Both blur radii and opacities were also reduced (outer: 14→10pt blur, 0.45→0.22 opacity; inner: 6→3pt blur, 0.85→0.5 opacity) so the rim reads as a highlight rather than a wash even where it does touch the edge.
- **Price axis leading edge now genuinely fades**, via `.mask(LinearGradient)`, instead of stopping at the rounded shape's geometric edge. The fade is narrow — 15% of the axis width — so it reads as an edge dissolve rather than fading out a third of the panel, which would have left the rounded-corner shape doing very little visible work of its own.

### Verification

Same caveat as the previous two rounds, plus one addition worth naming directly: `.mask(...)` on its own is generic and low-risk, but stacking it on a `glassEffect` view specifically hasn't been ruled out as an interaction neither has been tested independently. And the stroke-based glow's visibility is inherently zoom-dependent — a candle only a few points wide leaves little room for an outline before it just reads as a slightly thicker candle rather than a distinct glow; that's a real tuning question a device is needed to answer, not something more careful reasoning can settle in advance.

## Earlier unreleased work

### Changed — glass axis revised to real Liquid Glass; crosshair now spotlights

Follow-up on direct device feedback: the flat `.ultraThinMaterial` price axis "looked weird," and
the glow alone didn't stand out enough against a full-brightness chart.

- **Price axis now uses real Liquid Glass on iOS 26+.** `glassEffect(.regular, in:)` instead of a
  plain `Material` fill — genuine specular highlights and light response, not just a blur. Clipped
  to `UnevenRoundedRectangle` rounded only on the leading edge, since that's the one edge that's an
  actual boundary against the chart; the top, bottom and trailing edges are flush with the
  screen/pane edges, and rounding those (or rounding none of them, the previous behavior) most
  likely explains why a plain rectangular blur read as an undefined smudge rather than a panel.
- **iOS 17–25 fallback improved to match**: the same edge-rounded shape, filled with the chosen
  `Material`, with a faint leading-edge stroke for definition a borderless flat fill had no way to
  signal. `CandleChartStyle.priceAxisMaterial`'s public meaning is unchanged — it's still the on/off
  switch and the fallback material choice — but what it now controls chooses the best available
  rendering per OS rather than always using `Material`.
- **The crosshair now dims the rest of the chart while glowing the focused candle**
  (`CandleChartStyle.crosshairDimOpacity`, new, default `0.35`; `0` disables it, keeping only the
  glow). The dimmed region is the *same shape* the glow is drawn from — the glow's geometry doubles
  as the "hole" cut into the dim layer via an even-odd fill — so the dimmed boundary and the glow's
  soft edge coincide rather than reading as two independently-tuned, potentially mismatched rings.
  Dimming covers every pane uniformly; there's no per-pane point highlight (RSI's value at that
  candle, say) to carve a matching hole for, which is a deliberate scoping choice, not an oversight.
- Drawing order — dim, then glow, then the crosshair's own lines and tags — ensures the glow is
  never dimmed by the layer underneath it, and the lines/tags (drawn afterward on the original,
  unmodified context) are unaffected by either.

### Verification

Genuinely more uncertain than most changes in this project: this is new API usage
(`glassEffect(_:in:)`, confirmed against Apple's own documentation but never compiled) layered on
top of a rendering approach that already needed one round of device-driven correction. Two things
specifically need a look before trusting this: whether the `glassEffect` branch compiles and looks
right at all on iOS 26, and whether the dim-with-a-hole reads as a spotlight rather than a hard,
distracting edge. Both blur radii, both opacities, and the `16`pt corner radius are straightforward
to retune in place if the current values don't look right — see `CrosshairLayer.drawFocusGlow` and
`CandlestickChart.PriceAxisGlassPanel`.

## Earlier unreleased work

### Added — glass price axis and crosshair glow

Two cosmetic changes, both opt-in or additive — nothing here changes default appearance for
existing adopters.

- **`CandleChartStyle.priceAxisMaterial: Material?`** (default `nil`, unchanged appearance). Setting
  it — `.ultraThinMaterial` is a reasonable start — gives the price axis a frosted backdrop, and lets
  candles extend slightly underneath it (see `ChartMetrics.priceAxisOverlap`, internal, set
  automatically only when a material is chosen) so they show through, blurred, as they scroll toward
  the edge. Deliberately built on the standard `Material` APIs (iOS 15+) rather than iOS 26's
  `glassEffect()`, so it works across CandleKit's full iOS 17+ support; on iOS 26 a `Material` still
  renders with the system's current glass materials, just without the newer API's specular
  highlights and morphing.
- **Price axis tick labels moved out of the Canvas into a real view** (`PriceAxisGlassPanel`, new,
  in `CandlestickChart.swift`). A `Material` only blurs content *behind* the view it's attached to —
  labels painted into the same `Canvas` as the candles would have blurred right along with them.
  This is the same reason `LastPriceBadge` had to become a real view rather than Canvas-drawn text.
  Labels render identically whether or not a material is set; only the background layer is
  conditional.
- **Crosshair glow.** Long-pressing now draws a soft additive highlight around the focused candle,
  in `CrosshairLayer`. Two blurred passes at different radii and opacities (a single blur reads as a
  smudge), blended with `.plusLighter` so it brightens the candle rather than dulling it with an
  overlay. Deliberately uses only `GraphicsContext.Filter.blur(radius:)` — a single, simple
  parameter — rather than `.shadow(...)`, whose multi-parameter signature hasn't been confirmed to
  compile; getting a Canvas filter signature wrong has cost a compile-error round trip before, and
  `.blur` is a much smaller surface to be wrong about.

### Fixed during this change

Caught and corrected before packaging, not after: the price axis panel was initially wired to only
appear when a material was set, which meant leaving `priceAxisMaterial` at its default `nil` would
have drawn **no price labels at all** — a real regression, not a stub. Fixed so the panel — and the
labels — render unconditionally; only its background rectangle is conditional on the style.

### Verification

None of this has been seen rendered. The layout math (`ChartLayout`'s new `priceAxisOverlap`) was
checked by hand — with overlap `0` it's provably identical to the previous non-overlapping formula,
since that's the value used whenever `priceAxisMaterial` is `nil`, which is every existing
integration. What can't be checked without a device: whether tick labels stay legible against
candles moving underneath the glass, and whether the glow looks like a glow rather than a smudge or
a blown-out blob. Both are exactly the kind of thing that's hard to get right on the first attempt
without seeing it — tune the two blur radii and opacities in `CrosshairLayer.drawFocusGlow` and the
`28`pt overlap constant in `CandlestickChart` freely once you can.

## Earlier unreleased work

### Added — indicator panes (Phase 5.3)

RSI, MACD, Stochastic, ATR and OBV now actually draw. They were computed and cached since the
previous change but skipped by the renderer, because plotting 0–100 values against a price scale
would have been worse than plotting nothing. This closes that gap.

- **Stacked panes below the candles**, one per separate-pane indicator, each autoscaled to its own
  values with its own grid, value axis and title.
- **The price pane keeps what's left**, and indicator panes are capped at 60% of the content height
  no matter how many are added or how tall each asks to be — otherwise four indicators squeeze the
  candles into a sliver, which is the one thing the user is actually looking at.
- **Reference levels widen a pane's range**, so RSI's 70 line can't scroll off screen when the
  values are all low. A pinned `preferredRange` (RSI's 0...100) stays exactly pinned rather than
  drifting outward by the padding fraction on every render.
- **The crosshair spans every pane** — the candle under your finger lines up with its RSI or MACD
  value below — while the horizontal line and value tag belong to whichever pane the finger is
  actually in.
- **Gestures now cover the whole content area**, so a drag starting on an indicator pane pans the
  chart instead of doing nothing.
- Each pane is clipped to itself, so an indicator briefly exceeding its autoscaled range can't bleed
  into the candles above.
- The indicator drawing routines are now parameterised on a value mapping rather than reaching for
  the price scale, which is what lets panes and price overlays share one implementation.
- New Core helper `PriceScale.autoRange(forSeries:in:required:paddingFraction:)`, with tests.
- Demo: RSI and MACD toggles under a new "Panes" section on the Market tab.

### Known gaps

Panes aren't resizable or collapsible yet, volume can't move into its own pane, every separate-pane
indicator gets its own pane rather than being mergeable, and VoiceOver still reads only the price
rather than each pane's value at the crosshair. Tracked as roadmap task **5.11**.

One cosmetic edge: if an indicator has no visible values at all (fully inside its warm-up period),
its pane is laid out but left empty rather than collapsed. It reclaims the space as soon as values
appear.

### Verification

The new Core helper is covered by tests you can run with `swift test`, including the pinned-range
and no-visible-values cases. Everything else — pane layout, the spanning crosshair, gesture
coverage — is uncompiled and needs an iOS build and a look on device.

## Earlier unreleased work

### Changed — rendering layer migrated onto the indicator engine (Phase 5.10)

The engine added in the previous entry is now what the chart actually draws.

- **`ChartIndicator` wraps any `Indicator`**, including app-defined ones, with optional colour and
  line-width overrides and an `isVisible` flag (so a settings UI can toggle an indicator without
  discarding its configuration). Convenience factories added for the whole Tier 1 set:
  `.bollingerBands()`, `.vwap()`, `.rsi()`, `.macd()`, `.stochastic()`, `.atr()`, `.obv()`,
  alongside the existing `.sma()` / `.ema()` / new `.wma()`.
- **`IndicatorCache` is keyed by descriptor**, so changing one indicator's period recomputes only
  that indicator instead of invalidating every overlay on the chart. Covered by new tests that
  assert the computation count directly — a cache that silently recomputes every frame is
  indistinguishable from a working one without them.
- **The renderer draws the full output model:** lines (with dash patterns), stepped lines,
  sign-coloured histograms, point markers, fills between plots, and horizontal reference levels.
  Histograms are batched into two paths by sign, following the same constant-draw-call rule as the
  candles.
- **Autoscale now accounts for indicator overlays.** A long moving average on a trending series
  routinely sits outside the visible highs and lows; previously it would be clipped.
- **`CandleChartStyle` gained `indicatorPalette`**, so consecutive overlays are visually distinct
  without the app picking colours.
- Only visible indicators are computed — hiding one stops paying for it.
- `IndicatorKind` and `MovingAverage` are deprecated but still work, and now delegate to
  `IndicatorMath` so there is one implementation rather than two that can drift. Existing
  `.indicators([.sma(20), .ema(50, color: .blue)])` call sites are unchanged.
- Demo: Bollinger Bands and VWAP toggles on the Market tab, which exercise the multi-plot and fill
  paths that a plain moving average never touches.

### Known gap

Indicators that request their own pane — RSI, MACD, Stochastic, ATR, OBV — are computed and cached
but **not drawn**. The renderer skips anything not on the price pane, because plotting 0–100 RSI
values against a price scale would be worse than plotting nothing. Roadmap task **5.3** (indicator
panes) closes this and is the next task; until then, adding `.rsi()` to a chart will correctly
produce no visible output rather than a wrong one.

### Verification

The Core half — the new cache, its eviction and per-descriptor recomputation — is covered by tests
you can run with `swift test`. The rendering half is uncompiled as usual: the plot styles, fill
geometry and colour resolution need an iOS build and a look on a device.

## Earlier unreleased work

### Added — indicator engine (Phase 5.1, 5.2, most of Tier 1)

The foundation the indicator picker, saved layouts and indicator panes all depend on. All pure
Foundation in `CandleKitCore`, so **this is the first work in a while you can actually verify
yourself: run `swift test`.**

- **`Indicator` protocol and output model** (`IndicatorOutput.swift`, `Indicator.swift`). The old
  `IndicatorKind.values(for:) -> [Double?]` returned one number per candle, which cannot express
  Bollinger's three lines and a fill, MACD's histogram, RSI's pinned 0–100 pane with reference
  levels, or SAR's discrete dots. The new model covers plots (line, stepped, histogram, points,
  hidden), fills between plots, reference levels, a preferred scale range, and pane placement.
  Colours are expressed as roles rather than `Color` values, so Core stays UI-framework-free and
  Linux-testable.
- **Typed parameters** (`IndicatorParameter.swift`) — the piece that makes a *generic* picker
  possible. An indicator declares its inputs with kinds and valid ranges, so the settings form can
  be generated for any indicator, including one an app defines itself, with no bespoke UI. Values
  clamp on assignment, so a picker binding can't put an indicator into a divide-by-zero state.
- **`IndicatorCatalog`** — immutable and `Sendable` (no global mutable registry, so no locking and
  no Swift 6 concurrency problem). Apps extend it with `adding(_:)`, and two charts in one app can
  offer different sets. Provides category grouping and search for the picker.
- **`IndicatorDescriptor`** — the `Codable` `identifier + [key: value]` pair a saved layout stores.
  Unknown parameter keys are ignored and out-of-range values clamped on load, so a layout written
  by a newer build, or a hand-edited one, degrades gracefully instead of failing.
- **`IndicatorMath`** with SMA, EMA, WMA, Wilder smoothing, rolling population standard deviation,
  RSI, MACD, Stochastic, true range, ATR, Bollinger Bands, OBV and session-anchored VWAP. Every
  function documents which convention it implements, and where two are common the choice is a
  parameter rather than a silent decision.
- **Tier 1 indicators** as `Indicator` conformances: `MovingAverageIndicator` (SMA/EMA/WMA),
  `BollingerBandsIndicator`, `VWAPIndicator`, `RSIIndicator`, `MACDIndicator`,
  `StochasticIndicator`, `ATRIndicator`, `OBVIndicator`.
- **Tests** covering the maths, the parameter clamping, catalog round-tripping through `Codable`,
  the app-defined-indicator extension point, and degenerate inputs (empty series, single candle,
  mismatched array lengths, zero periods).

### Verification, and one thing that isn't verified

The O(n) WMA recurrence was checked against a direct computation of the definition over 200 random
inputs before being written, and the same check ships as a test. The expected values in
`IndicatorMathTests.swift` come from an independent reference implementation written separately
from the Swift, so the two agreeing is genuine evidence rather than the Swift agreeing with itself.

**What is not established: that these numbers match what a user sees on TradingView.** Validating
RSI against a widely reproduced published worked example came out consistently ~0.07 off, and
neither an alternative seeding convention nor intermediate rounding explained the gap. The most
likely explanation is that the recalled table was inaccurate, but that cannot be confirmed without
the primary source. Rather than bake in numbers of uncertain provenance, the tests verify internal
consistency and the documented formulas, and roadmap task **5.9** now tracks validating against an
authoritative source as required work — not optional polish.

### Changed

- Nothing was removed. `IndicatorKind` and the existing rendering path still work exactly as before;
  the new engine was added alongside it. Reconciling the two is roadmap task **5.10**, and has to
  happen before panes or the picker can ship.

### Decided

- **CandleKit will ship the indicator picker and drawing toolbar**, in a separate `CandleKitUI`
  product so the core stays headless. Recorded in the roadmap's decision log; open question 9 is
  closed.

## Earlier unreleased work

### Added — indicators, drawing tools, configuration and persistence roadmap

Phases 5–7 substantially expanded and restructured around what developers adopting a charting
library actually need.

- **Phase 5 (indicators)** now leads with architecture, not catalog. `IndicatorKind`'s current
  `[Double?]`-per-candle output can't express Bollinger Bands, MACD's histogram, Ichimoku's cloud or
  Parabolic SAR's dots, so a protocol and a richer output model (multi-line, band fill, histogram,
  point markers, reference levels) must land before any new indicator, or each one becomes migration
  debt. Catalog split into Tier 1 (the twelve that actually get used) and Tier 2 (the long tail,
  mostly good community-contribution material). Custom indicators folded into the architecture work
  rather than bolted on afterwards.
- **Indicator conventions called out explicitly.** RSI smoothing, ATR smoothing, MACD signal seeding
  and Stochastic %D all differ between platforms. Every indicator must document which convention it
  implements and test against cited reference values — a chart that disagrees with TradingView's
  numbers gets reported as a bug.
- **Phase 6 (drawing tools)** restructured the same way: interaction model, `(Date, price)` anchoring,
  hit testing, undo, and magnet/snapping first; then Tier 1 (horizontal line, ray, trend line,
  rectangle, Fibonacci retracement, text, measure) and Tier 2.
- **New Phase 7 — configuration, persistence and comparison**, promoted ahead of platform expansion:
  - `ChartConfiguration` making every capability individually switchable, replacing the ad-hoc
    `volumeVisible` / `headerVisible` modifiers before the surface grows further.
  - An open question on whether CandleKit ships default UI (indicator picker, drawing toolbar) — the
    recommendation is a separate `CandleKitUI` product so the core stays headless.
  - `ChartLayout: Codable`, versioned with a migration path from day one.
  - **Persistence recommendation: keep Core Data and SwiftData out of the core library.** Ship
    `Codable` as the contract with an optional `CandleKitPersistence` companion providing SwiftData
    wrappers. Reasoning is written out in 7.4 — adopting apps already have a persistence stack, a
    library-owned schema creates migration coupling, and a `Codable` value can be stored anywhere
    while a SwiftData model cannot.
  - Multi-symbol comparison (moved from 9.2), expanded with normalization modes and the genuinely
    hard part: aligning series with different trading calendars under an index-based x-axis.
- **Scope note added to the preamble.** Phases 5–7 are more work than Phases 0–4 combined. The plan
  states plainly that the extensibility API matters more than catalog size, and that Tier 1 finished
  properly beats both tiers half-finished.
- Old Phase 7 (More platforms) renumbered to Phase 11; all cross-references updated.
- Four new open questions: whether CandleKit ships UI, confirmation of the persistence stance, the
  comparison-view API boundary, and whether matching TradingView's numbers or textbook definitions
  wins when indicator conventions conflict.

### Added — competitive roadmap

`docs/ROADMAP.md` gains three new phases (8, 9, 10) plus a positioning section, laying out what
would make CandleKit a better choice than TradingView's Advanced Charts or SciChart iOS rather than
just a free imitation of either:

- **Phase 8 — signature features:** things a `WKWebView`-hosted chart structurally cannot do on
  Apple platforms — a home screen widget, a Live Activity, a watchOS companion, App Intents/Siri
  integration, chart-as-image sharing, and deeper visionOS use of depth.
- **Phase 9 — feature-parity rounding:** real gaps against professional charting tools that Phases
  4–6 don't already cover — extended-hours shading, multi-symbol comparison overlays, event
  markers, a price-crossing primitive for alerts, and a replay/bar-by-bar playback mode.
- **Phase 10 — developer experience:** `Codable` chart-layout persistence, a testing-support
  module, asset-class-aware number formatting, and a localization/RTL pass — the axis proprietary
  SDKs consistently under-invest in.
- An explicit **"What CandleKit deliberately will not become"** list — order books, bundled data
  feeds/brokers, a built-in alerting backend, and remote-config styling are called out as
  out-of-scope for the core library, with a suggested path (companion packages) for whichever of
  them someone eventually wants.
- The competitive claims are grounded in each competitor's own current pricing/licensing pages
  rather than assumed, and cited in the roadmap.

All of this is explicitly sequenced *after* the 1.0 criteria, not folded into getting there —
nothing here should pull focus while the project hasn't built yet (Phase 0).

## Earlier unreleased work

### Fixed — CI build failure

`animatedResetZoom()` and `animatedScrollToLatest()` were declared with no access modifier
(`internal`, Swift's default) when added a few commits back for the double-tap-to-reset gesture,
which only ever called them from within the `CandleKit` module. A later change (this changelog's
own "Jump to latest" and "Reset zoom" entries) had the Demo call them directly from its own module,
which needs `public` — an oversight on my part, since I recommended that change without checking
the methods it was calling were actually exposed. Xcode Cloud caught it correctly:

```
error: 'animatedResetZoom' is inaccessible due to 'internal' protection level
error: 'animatedScrollToLatest' is inaccessible due to 'internal' protection level
```

Both are now `public`, with doc comments explaining when to prefer them over the instant
`resetZoom()` / `scrollToLatest()`. Audited every other CandleKit symbol the Demo references
against its declared access level — nothing else is affected.

## Earlier unreleased work

### Fixed — docs

- `docs/PERFORMANCE.md`: the `xctrace` example was wrong in two ways. `--output` was placed after
  `--launch --`, where everything is passed to the launched app, so it was silently ignored and
  traces landed under auto-generated names. And `--launch --` takes a path to the `.app` bundle, not
  a bundle identifier.
- Made it explicit that **Animation Hitches requires a physical device** — on the Simulator it fails
  with `Hitches is not supported on this platform`, because hitch measurement reads real display
  pipeline timing. Added a section on what the Simulator can and can't tell you (gross algorithmic
  problems yes; relative phase cost no, since CPU work runs on the Mac's cores while rendering takes
  a different path), an `--attach` recipe that's easier for interactive profiling, the Xcode GUI
  route as the recommended default, and a troubleshooting table.

## Earlier unreleased work

### Added — performance instrumentation

Scrolling and the appear animation are reported fixed. This adds the measurement infrastructure
that should have come first, so the next round of performance work starts from numbers.

- `ChartPerformance`: opt-in instrumentation naming twelve phases of the per-frame work
  (`makeFrame`, `makeFrame.priceRange`, `draw.candles`, `draw.axes`, `draw.crosshair`, …). Emits
  `OSSignposter` intervals for the Points of Interest track in Instruments, and collects timings
  that `ChartPerformance.report(scenario:)` renders as a markdown table with call counts and
  mean/p50/p95/max per phase.
- Off by default, costing one `Bool` check per phase. Enable with the `CANDLEKIT_PERF` environment
  variable — so a Release build can be profiled without recompiling — or `setEnabled(_:)`.
- Demo: a capture bar on the Performance tab (record → interact → stop → copy). Reports are tagged
  with the device model, OS version and candle count, and simulator runs are labelled as not
  representative. `UIDevice.name` is deliberately not used, since it's often the owner's real name
  and these reports get pasted into a public repo.
- `docs/PERFORMANCE.md` rewritten: phase reference, in-app capture recipe, Instruments recipe
  (including an `xctrace` invocation), how to read the numbers against a 120 Hz budget, the two
  known-remaining costs, and a trace log with a template. The log is empty — the first entry should
  be a baseline on current `main`.
- `CLAUDE.md`: performance changes now require a before/after trace entry in the same change.

## Earlier unreleased work

### Performance — second pass (scrolling, zooming, appear animation)

Follow-up after the first pass didn't resolve the reported lag. See `docs/PERFORMANCE.md` for the
ranked hypothesis list, what's still open, and — more importantly — the Instruments recipe. None of
the below is measured; that document explains why measuring is now the priority over further
blind fixes.

- **The whole chart re-rendered on every animation frame.** `CandlestickChart.body` read
  `state.revision` at the top, so each bump — one per frame during a pan, fling or pinch, up to 120
  a second — invalidated the entire body: the header (which reformats a row of prices), the
  accessibility summary, the `UIViewRepresentable` gesture host, and the ZStack layout. Almost none
  of that changes when the viewport moves. `revision` is now read only by a new private
  `ChartContentLayer`, the one view that genuinely must repaint per frame. This is the largest
  single change in this pass and the most likely explanation for lag that survived the first round.
- **Accessibility strings were built on every frame.** `ChartAccessibility.summary` formats two
  dates and two numbers; date formatting is among the most expensive operations in Foundation, and
  this ran on every frame of every scroll to produce a string only VoiceOver reads. It's now
  attached only when `accessibilityVoiceOverEnabled` is true — and when VoiceOver *is* running
  there's no 120 Hz flinging to protect, so it stays fully accurate.
- **Appear animation issued a draw call per candle.** `drawAnimatedCandles` copied the
  `GraphicsContext` and issued two or three fills for every visible candle, every frame — over a
  thousand draw calls per frame at wide zoom, which is exactly why the animation stuttered worst
  when the most candles were on screen. Candles are now grouped into 8 quantised opacity buckets
  and drawn as batched paths, capping it at a couple of dozen fills. The fade zone spans only a few
  candles, so the quantisation isn't visible.
- **Axis labels ran `FormatStyle` inside the draw closure.** Every price and time label was
  re-formatted on every frame. Label strings are now built once in `makeFrame`, cached against the
  ticks that produced them (so panning, where tick values usually don't change at all, skips the
  work entirely), and passed to the renderer pre-formatted. The renderer no longer calls
  `ChartFormat` at all.
- **The crosshair Canvas re-rasterised even when idle.** `CrosshairLayer` always created a `Canvas`
  whose draw closure returned immediately when no crosshair was showing — but the Canvas itself
  still re-rendered every frame. It now produces no view at all when idle, and reads `revision`
  only while a crosshair is actually up.

### Added

- `docs/PERFORMANCE.md`: ranked hypotheses, the two known-remaining costs with concrete options for
  each, and a step-by-step Instruments recipe.

## Earlier unreleased work

Fixes from a pass looking specifically for memory leaks, hangs, and scrolling/animation smoothness,
prompted by reports that panning and animations didn't feel smooth. See `docs/ROADMAP.md` for the
full list of what's still open, and the "Verification" note at the end of this entry for what has
and hasn't been checked on a device.

### Fixed

- **Memory leak: chart animations could keep a whole chart alive forever.** `CandleChartState`'s
  appear-in and spring-to-target animations used `CADisplayLink(target: self, ...)`.
  `CADisplayLink` retains its target for as long as it's on a run loop; nothing invalidated these
  two if the chart was removed from the view hierarchy mid-animation (a list row scrolling away, a
  sheet dismissed, a navigation pop, all while data had just loaded or a "reset zoom" was still
  settling). Both are now driven through a small weak-referencing proxy (`DisplayLinkProxy`, new
  file) that never keeps the chart alive, and `CandlestickChart` now also calls
  `state.stopAnimations()` (new public method) from `.onDisappear`, so the common case cleans up
  immediately rather than only being leak-safe. The gesture coordinator's own two display links
  (momentum, rubber-band release) got the same treatment for consistency, even though their
  cleanup via `dismantleUIView` was already sound.
- **Scrolling: flinging to the newest or oldest candle stopped dead instead of bouncing.** Every
  other place the chart touches the data edge gives some kind of soft-limit feedback — dragging
  past the edge rubber-bands, a pinch past the zoom limit gives a haptic tick — except a fling that
  reached the edge under its own momentum, which just stopped. Momentum now hands off to the same
  rubber-band spring used for a drag release the instant it crosses the boundary, so it bounces
  like the rest of the chart instead of reading as a glitch.
- **Scrolling: a slow, deliberate drag could get mistaken for a long-press.** The crosshair's
  `minimumPressDuration` had been lowered from `0.25` to `0.15` seconds, which is close enough to
  how long a finger dwells before an intentional slow drag satisfies `UIPanGestureRecognizer`'s own
  movement threshold that panning would occasionally lose the race and open the crosshair instead.
  Reverted to `0.25`.
- **Redundant work on every render.** `ChartHeader` recomputed `TimeScale.estimatedInterval` from
  scratch on every render — including every crosshair move and every live price tick — duplicating
  work `CandleChartState.makeFrame` had already done and cached for the same data. It now reads the
  cached value.
- Overzealous haptics and sound. A recent pass had added `AudioServicesPlaySystemSound` (undocumented
  system sound IDs, not public API) plus layered haptics to nearly every gesture: a pop on long-press
  start, a peek on release, a click on every pinch past the zoom limit, a peek on every momentum
  edge-hit. Reaching the edge during ordinary scrolling is common, so that last one in particular
  fired on a large fraction of everyday scrolls. All system sounds are removed, and haptics are
  pared back to three: one light tap when the crosshair engages, one rigid tap at a hard zoom limit,
  one medium tap on double-tap-to-reset. Per-candle crosshair ticks still come from
  `CrosshairLayer`'s existing `.sensoryFeedback(.selection)`, unchanged.

### Added — animated price ticker

- The last-price tag (the badge on the price axis showing the current close) and `ChartHeader`'s
  price, change and percent values now use `.contentTransition(.numericText())`: digits roll up or
  down instead of cross-fading, the standard "stock ticker" look, on every live tick.
- This required moving the last-price tag out of the Canvas into a real SwiftUI view
  (`LastPriceBadge`, new). `.contentTransition` is a view modifier with no Canvas equivalent —
  Canvas-drawn text is rasterised immediately and can't animate. `ChartHeader`'s prices were already
  real views, so those only needed the modifier added.
- **Scoped deliberately to the numbers people actually watch tick**, not every number the chart
  draws. Axis tick labels and the crosshair's price/time tags stay Canvas-drawn:
  - Tick labels are a poor fit for `numericText` regardless — the *set* of visible ticks changes
    identity as the price range autoscales or the user pans, which is an insertion/removal, not a
    value transition on a stable view.
  - The crosshair's tags already update at gesture-frame-rate as a finger drags; animating those
    would fight the drag rather than help it, and would reintroduce a per-frame real-view cost in
    exactly the place the previous two passes worked to remove it.
  - If axis tick labels ever move to real views, it'll most likely be to fix the "text drawing in
    Canvas" performance question (see `docs/PERFORMANCE.md`), not for this animation — worth doing
    together if a trace shows `draw.axes` is hot, since the same view-based fix would clear both.
- `LastPriceBadge` reads `state.revision`, unlike most of `CandlestickChart.swift` — its vertical
  position needs to track the price scale during a pan or pinch. That's a deliberately narrow,
  cheap subscription (repositioning one small view), not the whole-subtree cost the render-scope
  refactor in the previous pass exists to avoid.

## Earlier unreleased work


### Added

- Appear-in and reset/scroll-to-latest animations now check `UIAccessibility.isReduceMotionEnabled`
  and skip straight to the end state when it's on, matching the demo's own build of the same
  feature for the reveal sweep. Direct-manipulation motion (the rubber-band drag itself, ordinary
  momentum) isn't gated, matching how `UIScrollView` behaves.
- `CandleChartState.stopAnimations()`: stops any in-flight appear or spring animation without
  touching the current viewport. Called automatically by `CandlestickChart` on disappear; also
  useful directly if you manage chart state outside a `CandlestickChart`'s own lifecycle.

### Changed (demo)

- The "Jump to latest" button and the chart-options menu's "Reset zoom" now call
  `animatedScrollToLatest()` / `animatedResetZoom()` instead of the instant versions, so they match
  the feel of double-tap-to-reset instead of snapping.

### Verification

None of this has been compiled — this environment has no Swift toolchain (see `docs/ROADMAP.md`,
Phase 0). Everything above was checked by careful reading, not by running it: the numeric spring
and rubber-band logic was traced by hand for the cases that looked riskiest (a stale rubber-band
flag surviving into an unrelated gesture, a momentum hand-off with too little overscroll to bounce
visibly), and the concurrency pattern in `DisplayLinkProxy` mirrors one already in
`Demo/CandleKitDemo/Performance/PerformanceView.swift`. It has **not** been verified that any of
this actually compiles under Swift 6's strict concurrency checking, and none of it has been felt on
a device. Before relying on this: run the Phase 0 build steps, then work through
`docs/QA.md`'s momentum/rubber-band/crosshair/Reduce-Motion items specifically, since those are
exactly what changed here.
