---
id: drawings
title: Drawing Tools API
sidebar_label: Drawing Tools API
---

# Drawing Tools API

The complete reference for the drawing-tools model. See the [Drawing Tools guide](/guides/drawing-tools)
for a friendlier walkthrough with screenshots — this page documents every public property, case
and method precisely.

## `DrawingAnchor`

One point a drawing is anchored to, in terms that survive history changes: a moment in time and a
price — never a candle index, which shifts when older history is prepended.

```swift
public struct DrawingAnchor: Codable, Hashable, Sendable {
    public var time: Date
    public var price: Double

    public init(time: Date, price: Double)
}
```

## `DrawingKind`

What a *finished* drawing is. Stable across releases — this is what a saved layout stores, so a
case can be added but never renamed or removed without a migration story.

```swift
public enum DrawingKind: String, Codable, Sendable, CaseIterable {
    case horizontalLine, horizontalRay, verticalLine, trendLine, ray, rectangle
    case fibonacciRetracement, textNote

    public var anchorCount: Int { get }
}
```

| Case | `anchorCount` |
| --- | --- |
| `.horizontalLine` | 1 |
| `.horizontalRay` | 2 |
| `.verticalLine` | 1 |
| `.trendLine` | 2 |
| `.ray` | 2 |
| `.rectangle` | 2 |
| `.fibonacciRetracement` | 2 |
| `.textNote` | 1 |

## `DrawingTool`

What a person can pick from a drawing toolbar. Distinct from `DrawingKind` — which is what a
*finished* drawing is tagged as — every current case maps 1:1 to a `DrawingKind` of the same name.

```swift
public enum DrawingTool: String, Sendable, CaseIterable {
    case horizontalLine, horizontalRay, verticalLine, trendLine, ray, rectangle
    case fibonacciRetracement, textNote

    public var kind: DrawingKind { get }
}
```

## `DrawingColor`

A plain RGBA color. `CandleKitCore` has no `SwiftUI.Color` (Linux has no SwiftUI), so this is the
portable, `Codable` stand-in a drawing's style is stored in.

```swift
public struct DrawingColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1)

    public static let `default`: DrawingColor  // a neutral mid-blue
}
```

Convert to and from `SwiftUI.Color` with the initializer extension CandleKit provides:

```swift
extension Color {
    public init(_ drawingColor: DrawingColor)
}
```

## `DrawingStyle`

Visual configuration for one drawing. Deliberately per-drawing (not chart-wide) so two trend lines
on the same chart can carry different colors, matching how a trader actually annotates a chart.

```swift
public struct DrawingStyle: Codable, Hashable, Sendable {
    public var color: DrawingColor
    public var lineWidth: Double
    public var dash: [Double]?          // nil = solid line
    public var fillOpacity: Double?     // nil = stroke-only (a trend line has nothing to fill)

    public init(
        color: DrawingColor = .default,
        lineWidth: Double = 1.5,
        dash: [Double]? = nil,
        fillOpacity: Double? = nil
    )
}
```

## `Drawing`

One drawing on the chart — the unit an app's `[Drawing]` array (bound via `.drawings($drawings)`)
stores, persists and mutates.

```swift
public struct Drawing: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var kind: DrawingKind
    public var anchors: [DrawingAnchor]
    public var style: DrawingStyle
    public var isLocked: Bool
    public var isHidden: Bool
    public var text: String?

    public init(
        id: UUID = UUID(),
        kind: DrawingKind,
        anchors: [DrawingAnchor],
        style: DrawingStyle = DrawingStyle(),
        isLocked: Bool = false,
        isHidden: Bool = false,
        text: String? = nil
    )

    public var hasValidAnchorCount: Bool { get }
}
```

| Property | Description |
| --- | --- |
| `id` | Stable identity for the drawing. |
| `kind` | What kind of drawing this is. |
| `anchors` | `kind.anchorCount` entries, in a kind-specific order — e.g. `.rectangle`'s two anchors are opposite corners; `.ray`'s first anchor is the origin the ray extends from. |
| `style` | Color, width, dash and fill for this drawing. |
| `isLocked` | Prevents move/resize/delete through the chart's own gestures without affecting programmatic edits. |
| `isHidden` | Hides the drawing from rendering and hit testing without removing it. |
| `text` | Only meaningful for `.textNote`; `nil` for every other kind. |
| `hasValidAnchorCount` | `true` when `anchors.count` matches what `kind` requires. Mainly useful to validate drawings loaded from a saved layout. |

## `DrawingController`

Chart-local, transient UI state for drawing tools — never part of the app's own `[Drawing]` model.
CandleKit creates exactly one per chart instance; you don't construct this yourself, but its public
surface is documented here for completeness.

```swift
@MainActor
@Observable
public final class DrawingController {
    public private(set) var selectedDrawingID: UUID?
    public var snappingEnabled = true
    public var snapRadius: Double = 14
    public var activeTool: DrawingTool? { get }

    public init()
}
```

| Member | Description |
| --- | --- |
| `selectedDrawingID` | The currently selected drawing's id, or `nil`. Selection is chart-local UI state, never written into the persisted `Drawing` model. |
| `snappingEnabled` | Whether a placed or dragged anchor snaps to the nearest visible candle's open/high/low/close within `snapRadius`. On by default. |
| `snapRadius` | Snap search radius, in points, around the raw touch location. Defaults to `14`. |
| `activeTool` | Mirrors the bound `DrawingTool?` from `.drawingTool(_:)`. |
