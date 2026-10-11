# visionOS depth (roadmap 8.6): design note, no code yet

The roadmap says to get hands-on time before committing to anything beyond a flat chart. Nothing here
has been tried on a device or the visionOS simulator, so this is a list of questions and a proposed order.

## What works without changes

Probably a flat chart in a window: SwiftUI and Canvas run on visionOS. `CandleKit` is currently guarded
with `#if os(iOS)`, so enabling visionOS needs the guards widened and the UIKit gesture layer reviewed
(the chart's gestures use UIKit recognizers; visionOS supports many of them, but gaze/pinch input and
the lack of multi-touch pan/zoom need checking).

## Ideas worth prototyping (in this order)

1. **Flat chart in a window**, with hover effects for the crosshair (gaze instead of long press).
2. **Several symbols side by side** as separate windows or ornaments, reusing the comparison work.
3. **Depth for volume only**: extrude volume bars along z behind the candles with `RealityView` or `Model3D`.
   This is the one place depth carries meaning rather than decoration.
4. **Candle extrusion**: probably not. It adds cost per candle and can make prices harder to read.

## Decision criteria

Keep a depth feature only if people read prices faster or compare symbols more easily with it, and only if
it keeps the per-frame cost independent of series length, as the rest of the library does.
