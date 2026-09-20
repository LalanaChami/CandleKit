# Design note: drawing tools (Phase 6, item 6.1)

Status: **agreed design, not yet implemented beyond the pure Core model** (`Sources/CandleKitCore/Drawings/`).
See `docs/ROADMAP.md` Phase 6 for the checklist this note resolves the open questions for.

This mirrors how Phase 5 was handled: get the model and the interaction rules right once, before
any tool-specific code, because every tool afterwards (line, ray, rectangle, Fibonacci, …) is
mechanical once the hard parts — anchoring, gesture coexistence, hit testing, persistence — are
settled. Getting those wrong is expensive to unwind once nine tools depend on them; getting them
right costs nothing extra done first.

## 1. What a drawing is, and who owns it

A drawing is **app-owned state**, the same relationship the app already has with `[Candle]`, not
chart-owned state like `CandleChartState`'s viewport. The chart binds to it and renders it, but the
app decides what exists, persists it, and is the source of truth. Concretely:

```swift
CandlestickChart(candles)
    .drawings($drawings)              // Binding<[Drawing]>, app-owned
    .drawingTool($activeTool)         // Binding<DrawingTool?>, nil = not drawing (pan/zoom/crosshair as today)
```

This is the same shape `.indicators([...])` already uses for `[ChartIndicator]`, and for the same
reason: an app that wants to save, sync, undo, or filter its indicators (or its drawings) needs to
own the array, not have the chart hide it inside opaque `@State`.

### 1.1 The `Drawing` model — `Codable`, anchored to `(Date, price)`

```swift
public struct Drawing: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var kind: DrawingKind
    public var anchors: [DrawingAnchor]     // 1...4 points depending on kind
    public var style: DrawingStyle          // color, line width, dash, fill opacity
    public var isLocked: Bool
    public var isHidden: Bool
    public var text: String?                // only meaningful for .textNote
}

public struct DrawingAnchor: Codable, Hashable, Sendable {
    public var time: Date
    public var price: Double
}

public enum DrawingKind: String, Codable, Sendable {
    case horizontalLine, horizontalRay, verticalLine, trendLine, ray, rectangle
    case fibonacciRetracement, textNote
    // Tier 2, added the same way, no model change needed: parallelChannel, ellipse, triangle,
    // fibonacciExtension, fibonacciFan, fibonacciTimeZones, andrewsPitchfork, longPosition,
    // shortPosition, arrow, callout.
}
```

**Anchored to `(Date, price)`, never `(candleIndex, price)`.** This is the one non-negotiable
decision in this whole note, because it's the one that's unfixable after the fact: a saved
drawing's positions must survive the app prepending older history (which shifts every existing
index) and switching timeframes (which changes what a "candle" even corresponds to at that point in
time). An index is a *view* of the data, not a fact about the world; a `(Date, price)` pair is a
fact about the world.

**Converting a `Date` back to a screen position** goes through `Viewport`, exactly like a candle
does — a drawing's `time` is looked up against the current candle array to find its position, using
the same index-based x-axis (`Viewport.position(atX:)` and its inverse) everything else uses.
Concretely: find the candle whose time matches (exact hit — the common case, since most anchors get
created *on* a candle via snapping, 6.2), and when it doesn't exist anymore or never did (freehand
placement between candles, or the candle it was anchored to got pruned from a shortened history
window), interpolate between the two candles that bracket it, and clamp to an edge extrapolation
when the anchor point is now entirely outside the loaded range. This lookup is O(log n) (binary
search on sorted candle times) recomputed only when the candle array or the drawing's anchors
change, not per frame — the same "recompute on data change, read every frame" split `ChartFrame`
already uses for everything else.

**Timeframe switches are explicitly out of scope for automatic handling in 1.0.** A trend line drawn
on the 1-hour chart has a "reasonable" position on the 1-day chart projected from the same two
timestamps, but there's no single correct answer for what a drawing anchored between two 1-hour
candles should look like when those two points now fall inside the *same* daily candle. The
recommendation: store drawings **per timeframe** (an app already has one `[Drawing]` array per
chart instance; if it wants per-symbol-per-timeframe drawings — the TradingView convention — that's
its own keying decision, not something `Drawing` itself needs an opinion on). Revisit only if real
usage shows people expect a trend line to travel across timeframe switches.

### 1.2 Why not `Codable` closures or view-builder style tools

An earlier instinct was a more "SwiftUI-native" API — something like a `DrawingToolBuilder` result
builder mirroring `ToolbarContent`. Rejected: drawings are *data* a person creates by dragging on
the chart and an app needs to store, list, edit, and delete outside of any particular render pass.
A view-builder shape fits configuration that's fixed at compile time (a toolbar's buttons); it does
not fit runtime-created, persisted records. `Codable` structs plus a `Binding` is the boring, right
answer, consistent with `[ChartIndicator]` and `IndicatorDescriptor` already established for
indicators.

## 2. Gesture coexistence — the actual crux

The chart already owns pan (one-finger drag), pinch (zoom), long-press (crosshair), and double-tap
(reset), all as UIKit recognizers in `ChartGestureCoordinator` (see `ChartGestureView.swift`). A
drawing tool needs a drag gesture too — trend line, rectangle, and the rest are all "drag from one
point to another." Two drags on the same view is normally simultaneous-recognition or bust; the
resolution here is neither — it's **mode switching**, and it already has a precedent in this
codebase: the crosshair itself is a mode (long-press engages it; it doesn't run *simultaneously*
with panning, because a drag means different things once the crosshair is up vs. not).

**`drawingTool: DrawingTool?` (nil = cursor/pan mode) governs which meaning a one-finger drag has,
decided once at gesture-began time, not renegotiated mid-drag:**

- **`nil` (cursor mode, the default — today's exact behavior, unchanged):** a drag pans the
  viewport; pinch zooms; long-press engages the crosshair. Tapping an existing, unlocked drawing
  selects it (hit testing, §3) and shows its drag handles; dragging a handle moves that anchor;
  dragging the body moves the whole drawing. This is a *second* interpretation of a plain drag,
  disambiguated by where it starts: touching within a drawing's hit tolerance selects/moves it,
  touching empty plot area pans the chart, exactly like a `UIScrollView` full of buttons already
  works.
- **A tool selected (e.g. `.trendLine`):** a one-finger drag creates a drawing instead of panning —
  first touch places anchor 1, drag tracks anchor 2 live, release commits it. Pinch and long-press
  are suppressed while a tool is active (there is nothing useful for the crosshair to do mid-draw,
  and pinch-while-placing-a-point is not a combination worth supporting for 1.0). After committing,
  the tool **stays selected** for another drawing of the same kind — TradingView's convention, and
  the one that matches "I want to draw five Fibonacci levels," not "I drew one and now I'm back to
  panning by accident." A visible "done drawing" affordance (tapping the tool button again, or a
  dedicated cursor button) returns to `nil`.
- **A single-anchor tool (horizontal line, vertical line, text note):** a plain tap places it
  immediately, for a fast placement — but a press-and-drag also works, tracking the anchor live
  (with a price/time axis tag, §7a) and committing on release, the same "line follows your finger
  until you let go" a trader gets from every other charting app for a horizontal price level. This
  was revised from the original "no drag at all" plan once it became clear a horizontal line's exact
  price is usually the thing being fine-tuned, and a blind tap doesn't let you fine-tune it. Both
  gestures are still governed by the same `drawingTool` state; a tap is simply a drag with zero
  travel.

This is a **new UIKit recognizer state**, not a rewrite of the existing ones: `ChartGestureCoordinator`
gains a `drawingController: DrawingController?` (nil when no app binding is attached, so a chart
with no `.drawings()` call pays zero cost and behaves exactly as it does today) and each existing
recognizer's `shouldBegin`/handler checks `drawingController?.activeTool` first. Pan's handler, for
instance, becomes: *if a tool is active, route to the drawing controller's drag-to-create instead of
`state.pan(...)`* — a branch at the top of an existing method, not a parallel gesture stack. Pinch
and long-press's existing delegate methods gain a guard clause refusing to begin while a tool is
active.

**This does not feel modal in the sense of trapping the user** — cursor mode (the default) is
functionally identical to today's chart, and a tool is a deliberate, visible choice (tapping a
toolbar button) with an equally deliberate, visible exit. It *is* modal in the technical sense
(one meaning for "drag" at a time), which is the correct and standard behavior for every charting
app this competes with; a chart where drawing and panning are simultaneously live is the actual
usability bug to avoid.

## 3. Hit testing and selection

- **Tolerance, not exact geometry.** A touch is compared against each visible drawing's *stroke*
  (for lines/rays: distance from point to line segment; for shapes: distance to the nearest edge)
  with a minimum tolerance of **22pt** (Apple HIG's minimum comfortable touch target radius,
  already how this codebase treats analogous problems — see the long-press candle hit test), not
  the 1pt mathematical line. Anchors themselves get a tighter, but still touch-sized, **16pt**
  handle radius once a drawing is selected, so grabbing a specific endpoint is reliable without the
  handles overlapping each other at typical zoom levels.
- **Topmost wins.** Drawings are ordered (§4); hit testing walks that order back-to-front and stops
  at the first hit, matching how overlapping views resolve taps everywhere else.
- **Locked drawings are not hit-tested for move/edit** (an explicit design choice: locking exists
  specifically so an annotation stops being accidentally nudged), but are still hit-tested for
  *selection* so their existence and style remain inspectable/deletable through a settings UI rather
  than only through the layer list.
- **Selection is chart-local UI state**, not part of the `Drawing` model — which drawing is
  currently selected doesn't belong in a saved layout any more than which candle the crosshair is
  over does. It lives in `DrawingController` (owned by `CandleChartState`'s SwiftUI-layer sibling,
  not `CandleKitCore`).

## 4. Z-order, duplicate, lock, visibility

- **Z-order is array order** in the app-owned `[Drawing]` — last drawn is topmost, exactly like a
  `ZStack`. "Bring to front" / "send to back" are array moves the app performs on its own binding;
  CandleKit doesn't need a separate z-index field.
- **Duplicate** copies a `Drawing` with a new `id` and nudges its anchors by a fixed screen-space
  offset (converted to the equivalent time/price delta at the moment of duplication) so the copy
  doesn't sit exactly on top of the original.
- **Lock** (`isLocked`) prevents move/resize/delete through the chart's own gestures; it does not
  prevent an app from editing the struct directly (locking is a chart-interaction affordance, not an
  access control).
- **Visibility** (`isHidden`) hides a drawing from rendering and hit testing without removing it —
  the same "toggle without losing configuration" pattern `ChartIndicator.isVisible` already
  established.

## 5. Deletion, undo/redo

Deletion is `drawings.removeAll { $0.id == target }` on the app's own binding — no
CandleKit-side API needed beyond what selection + a delete affordance already require.

**Undo/redo is `UndoManager`, registered by the app, not owned by CandleKit.** CandleKit doesn't
have — and shouldn't invent — an opinion on whether undo should also cover indicator changes,
viewport position, or anything else in the host app; that's an app-level concern. What CandleKit
does provide: every mutation the chart itself makes to the `drawings` binding (create, move,
resize, delete via the chart's own gestures) happens as one discrete, atomic write to the binding,
so an app that wraps its `@State private var drawings: [Drawing]` with
`.onChange(of: drawings) { registerUndo(...) }` (or drives it through a `@Observable` model with its
own `UndoManager` integration) gets correct undo/redo for free, one array-diff per user action, with
no partial-drag states leaking into the undo stack.

## 6. Accessibility

Drawings must be reachable by VoiceOver, not just visible — the same bar `ChartAccessibilityDetails`
already holds the chart itself to. Plan:

- Each visible, non-hidden drawing becomes one `accessibilityElement` (a custom "shape" in the
  chart's accessibility container, alongside the chart itself and its data-table equivalent), with:
  - a **label** describing what it is and where — `"Trend line, from $182.40 on Jun 3 to $191.10 on
    Jun 14"`, `"Horizontal line at $185.00"` — generated from the drawing's kind and anchors, the
    same way `ChartAccessibility.summary` already formats dates and prices for the chart overview.
  - an **adjustable action** (`accessibilityAdjustableAction`) for a selected drawing's active
    anchor, incrementing/decrementing price and, separately, time, mirroring the pattern
    `ChartAccessibilityDetails` already uses for scrolling the chart via VoiceOver's increment/
    decrement gesture instead of a drag.
  - a **custom action** for delete, and for cycling selection to the next anchor on a multi-anchor
    drawing.
- Creating a drawing without sight (no drag-to-place) is out of scope for the first pass — flagged
  here rather than silently dropped. A VoiceOver-accessible creation flow (e.g., "place anchor at
  current crosshair position" as a custom action, chained twice for a two-anchor tool) is real work
  and is being scoped as a fast follow rather than blocking Tier 1's initial landing, consistent
  with how the project has previously separated "accessible to inspect and adjust" (must-have day
  one) from "accessible to construct via an alternate flow" (follow-up) when the two genuinely
  require different affordances. This gap is tracked explicitly in the roadmap, not left implicit.

## 7. Magnet / snapping (6.2)

Snapping is a **creation-time and drag-time modifier**, not a property of the stored `Drawing` —
a snapped anchor is stored as the exact `(Date, price)` it snapped to, indistinguishable afterward
from one placed freehand at that same point. Implementation: while placing or dragging an anchor,
candidates are the open/high/low/close of every visible candle within a screen-space radius (default
14pt, matching the anchor handle's own visual size) of the raw touch point; the nearest candidate
under that radius wins and the anchor snaps to it, with a light haptic (reusing the existing
`impactLight` generator `ChartGestureCoordinator` already has) on each new snap target. A
`snappingEnabled: Bool` toggle (default `true`) and the radius are both configuration on
`DrawingController`, per-chart, not per-drawing.

## 7a. Trader-facing readout, color, and haptics

Added after direct feedback that the mechanics above were right but the tools didn't yet feel like
something a trader would reach for on a real chart.

- **Price/time on the axis, not just the line.** A horizontal line or ray is meaningless to a trader
  without its exact price; a vertical line, without its exact time. Both are tagged on the relevant
  axis — live while the anchor is being dragged into place, and permanently once committed — using
  the same `ChartText.drawPriceTag`/`drawTimeTag` primitives the chart's own last-price badge already
  draws with, so the visual language matches rather than introducing a second style of "number in a
  colored pill." The tag's background is the drawing's own color; its foreground flips between black
  and white by a cheap luminance check so it stays legible against any color a trader picks.
- **A live delta while dragging a two-anchor tool.** Sizing a trend line, a rectangle, or a Fibonacci
  retracement is fundamentally "how far did price move between these two points" — so while the
  second anchor is being dragged, a small badge near it shows the signed price delta and percent
  change, colored green for up and red for down. This is deliberately preview-only: a committed
  drawing doesn't carry a permanent badge, which would be visual noise on every trend line on a busy
  chart.
- **Color is per-drawing, not chart-wide**, because `DrawingStyle`/`Drawing.style` already was
  (§1.1) — this pass just gives an app-level way to *set* it easily.
  `CandlestickChart.defaultDrawingStyle(_:)` is the one new CandleKit API: it sets what a *newly
  created* drawing starts as. Recoloring a drawing that already exists — including the one currently
  selected — needs no further API: it's `drawings[index].style.color = newColor` on the app's own
  `.drawings(...)` binding, the same "app owns the array" principle §4/§5 already establish for
  deletion. `Color(_ drawingColor: DrawingColor)` (previously internal, used only by the renderer) is
  now `public`, so an app's own color-swatch picker can render a swatch that matches the rendered line
  exactly instead of reimplementing the RGBA conversion.
- **Haptics mark the gesture, not just the snap.** `ChartGestureCoordinator` already fired a light tap
  on a new snap target (§7); this adds a light tap when a drawing-creation gesture *begins* (an active
  tool, not a selection drag) and a medium tap when it *commits* — the same begin/commit weight
  distinction the crosshair (`handleLongPress`) and double-tap-to-reset (`handleDoubleTap`) already use
  elsewhere in this file — plus a medium tap on a successful quick-tap placement. This generalizes the
  specific ask ("haptics when drawing horizontal lines") to every tool, since there's no principled
  reason a trend line or rectangle should feel different to draw than a horizontal line.

## 8. What CandleKit renders vs. what the app owns — summary table

| Owned by the app (`Binding`) | Owned by CandleKit |
|---|---|
| `[Drawing]` — the data | Rendering every visible, non-hidden drawing |
| `DrawingTool?` — which tool is active | Gesture routing while a tool is active or a drawing is selected |
| Undo/redo registration | Hit testing, selection state, drag handles |
| Persistence (see roadmap 7.3/7.4) | Snapping candidates and radius |
| Deciding what "per timeframe" storage means | VoiceOver descriptions and adjustable actions |

## Exit criteria (restated from the roadmap, unchanged)

Drawings survive history prepends and timeframe switches (per §1.1's explicit scoping — "survive"
means "don't corrupt or crash," not "reproject visually across timeframes"), round-trip through
`Codable` without loss, and are fully operable under VoiceOver for inspection and adjustment (per
§6, with construction flagged as a tracked follow-up rather than silently incomplete).

## What's implemented as of this note

The pure, `Codable`, UI-framework-free model described in §1.1 — `Sources/CandleKitCore/Drawings/`
(`Drawing`, `DrawingAnchor`, `DrawingKind`, `DrawingTool`, `DrawingStyle`, `DrawingColor`), plus the
geometry math §3 depends on (distance-to-segment/line/ray/rectangle-edge hit testing, anchor↔position
conversion via `Viewport`, and its inverse, position↔anchor) — all unit-tested on Linux like the rest
of `CandleKitCore`.

On top of that, the UI-layer pieces originally deferred: `DrawingsLayer`/`DrawingsLayerRenderer` (the
renderer), `DrawingScreenMapping` (the shared anchor↔pixel conversion the renderer and hit testing
both use, so they can't disagree — the same role `CandleGeometry` plays for candle bodies),
`DrawingController` (creation-in-progress state, selection, whole-drawing move, snapping per §7), the
`ChartGestureCoordinator` mode-switch integration from §2 (a new `drawingController` property, a
guarded branch in the pan handler decided once at gesture-began time, pinch/long-press refusing to
begin while a tool is active, and a new single-tap recognizer required to fail against the existing
double-tap), and the public `.drawings($drawings)` / `.drawingTool($activeTool)` API on
`CandlestickChart`. Eight of Tier 1's nine tools (6.3) are implemented this way; the measure tool
is not (see the roadmap's 6.3 entry for why it doesn't fit this same shape).

**Deliberately scoped out of this pass, not silently missing:**
- **Per-anchor resize.** Moving a selected drawing in cursor mode translates every anchor by the same
  delta; dragging a single endpoint to reshape a drawing (distinct from moving the whole thing) needs
  its own hit-testing pass against each anchor's 16pt handle and is a fast follow.
- **Text entry for `.textNote`.** A tap places one with placeholder text; CandleKit doesn't yet offer
  an in-chart text field or sheet to edit `Drawing.text`; an app wanting live text entry needs to
  build that itself against the exposed `Drawing` model for now.
- **VoiceOver**, both halves of §6 — inspecting/adjusting an existing drawing (the must-have) and
  constructing one (the flagged follow-up) are both still just the plan in §6, not code.
- **Verification.** Like everything else built in this codebase without a Swift toolchain available
  to compile or run it, this is unverified in an iOS build or on a device — reviewed carefully by
  hand, cross-checked with independent reference math where the logic allowed it (the anchor↔position
  round-trip in particular), but not run.
