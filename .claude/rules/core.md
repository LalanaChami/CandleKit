---
paths:
  - "Sources/CandleKitCore/**"
  - "Tests/**"
---

# CandleKitCore and tests

- Import only Foundation. No SwiftUI, UIKit or CoreGraphics types: use `Double`, not `CGFloat`. This keeps Core buildable on Linux and fully unit-testable.
- Public types are `Sendable` value types unless there's a concrete reason otherwise.
- Coordinate conventions: candle `i` spans positions `[i, i+1)` and is centered at `i + 0.5`. `Viewport.pan(byPoints:)` with positive `dx` reveals older candles. `zoom(by:anchorX:width:limits:)` keeps the position under `anchorX` fixed.
- Functions called every frame take the visible `Range<Int>` and must be O(visible). `TimeScale.estimatedInterval` is the exception: it samples at most 50 gaps.
- Runtime data must never crash the chart. Empty series, a single candle, flat prices, NaN or infinite values, zero volume and tiny or zero sizes clamp or return `nil`. `precondition` is only for programmer errors, such as invalid `ZoomLimits` or sample-data arguments.
- Tests use swift-testing (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`), not XCTest. Use `@testable import CandleKitCore` for internal helpers.
- Tests that touch dates use a fixed Gregorian calendar in UTC, never `Calendar.current`. Build dates from epoch seconds and say in a comment what date they represent.
- Compare floating-point results with a tolerance unless the value is exactly representable.
- Don't derive expected values in your head. For indicators, use published reference values or compute them independently (for example, with a short script), and note the source in a comment.
