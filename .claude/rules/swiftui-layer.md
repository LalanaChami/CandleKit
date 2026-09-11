---
paths:
  - "Sources/CandleKit/**"
---

# SwiftUI and UIKit layer

- Every file except `Exports.swift` is wrapped in `#if os(iOS)` … `#endif`. When adding another platform, add explicit platform branches; don't remove guards wholesale.
- The minimum is iOS 17. Check the availability of every SwiftUI, UIKit and Accessibility API you use. Anything newer needs an `if #available` fallback.
- Compile with `xcodebuild build -scheme CandleKit -destination 'generic/platform=iOS Simulator'` after every change. `swift build` does not compile this layer.

## State and observation

- `CandleChartState` is `@MainActor @Observable`. Observed properties: `revision`, `crosshairIndex`, `crosshairY`. Everything that `makeFrame` touches is `@ObservationIgnored`.
- Never mutate an observed property inside `makeFrame` or any view body. User callbacks such as `onReachOldestCandle` must not run during a view update either; defer them if needed.
- After changing the viewport outside rendering, bump `revision` (see `commitViewport()`).
- Keep crosshair reads out of `CandlestickChart.body`. Only `CrosshairLayer`, `ChartHeader` and public observers read crosshair state.
- Changes to this pattern need plan mode and a note in the completion report about what to check at runtime (purple runtime warnings, redraw counts).

## Rendering

- Batch geometry into as few paths as possible per color. Don't add a draw call per candle.
- Use `PixelGrid` for crisp lines and edges. Body and wick widths are whole device pixels with matching parity so wicks stay centered.
- Don't allocate or format text per candle. Axis labels come from the tick lists only.
- Use semantic system colors. Consider light mode, dark mode and increased contrast. Hardcoded colors are only acceptable for tag foregrounds on filled backgrounds.

## Gestures

- Gestures live in `ChartGestureCoordinator`, using UIKit recognizers on a view that covers exactly the plot, so all locations are plot-local.
- Only pan and pinch recognize simultaneously. Pan begins only for mostly-horizontal drags so a parent ScrollView keeps working.
- Momentum stops when a pan hits the data edge, when a new gesture begins, and when the view is dismantled.

## Accessibility

- The chart is a single accessibility element with a spoken summary, an adjustable action for paging, and an `AXChartDescriptor` for Audio Graphs. New interactive features need a VoiceOver path too.
- Chart text scales with Dynamic Type, capped at `.accessibility2`.

## Verification

Nothing in this layer can be fully verified from the command line. In every completion report, list the device checks the maintainer needs to do: gestures, haptics, rendering in light and dark mode, VoiceOver, and performance.
