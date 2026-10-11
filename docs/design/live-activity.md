# Live Activity, Dynamic Island and watchOS (roadmap 8.2, 8.3)

## Decision

One tiny renderer serves both: `SparklineView` in the `CandleKitWidgets` product, with the index
selection (`SparklineSampling`) in `CandleKitCore` where it is unit tested. It takes plain closing prices,
not candles, so the values can travel inside an `ActivityAttributes.ContentState` or a watch
complication entry.

## Why not the full chart

An activity's content state is capped at about 4 KB, it is updated a few times a minute at best, and its
process is short-lived. The full `CandlestickChart` (viewport, gestures, state object) can't live there.
`SparklineView` is one `Shape` stroking one path, at most 30 points by default (under 300 bytes of state).

## What the Demo shows

`PriceLiveActivity` (in the widget extension) draws a Lock Screen banner and the four Dynamic Island
layouts (compact leading/trailing, minimal, expanded). The Styles tab has a card that starts the
activity and ticks it with simulated prices every 4 seconds from a foreground task.

## Host app checklist

- Add `NSSupportsLiveActivities` to the app's Info.plist (the Demo does).
- Share the `ActivityAttributes` file between the app and the extension.
- Update from push (`pushType: .token`) in a real app; the app is usually suspended when prices move.
- Keep `ContentState` small: send a thinned list of closes, not candles.

## watchOS (8.3)

`CandleKitWidgets` and `CandleKitCore` declare `.watchOS(.v10)`; their code is plain SwiftUI shapes and
Foundation. `CandleKit` (the interactive chart) stays iOS-only. CI builds `CandleKitWidgets` for the watchOS
simulator. Not done yet: a watch app target and a complication in the Demo. A complication is a WidgetKit
widget, so `WidgetCandleChart` and `SparklineView` can be used in one as they are.

## Not verified

Written without a compiler and not run. Needs: `xcodegen generate`, a build, then the Start button on a
device or simulator that supports Live Activities (the Dynamic Island needs an iPhone 14 Pro or later
simulator). `swift test` for `SparklineSamplingTests` not run locally.
