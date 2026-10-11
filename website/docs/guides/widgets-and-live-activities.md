---
id: widgets-and-live-activities
title: Widgets & Live Activities
sidebar_label: Widgets & Live Activities
---

# Widgets & Live Activities

The `CandleKitWidgets` product depends only on `CandleKitCore` and supports iOS 17 and watchOS 10.

## Home-screen widget

`WidgetCandleChart` is a non-interactive chart for WidgetKit. Long series are downsampled so drawing cost stays bounded.

```swift
WidgetCandleChart(candles, mode: .line, maxCandles: 40, showsLastPrice: true)
```

![The Demo's small widget on the home screen](/img/media/widget-small.png)

## Live Activities and the Dynamic Island

`SparklineView` draws a price line from plain closing prices.

![Compact Dynamic Island](/img/media/live-activity-compact.png)
![Expanded Dynamic Island](/img/media/live-activity-expanded.png)
![Lock Screen banner, with the system permission prompt](/img/media/live-activity-lockscreen.png)

## Siri and Shortcuts

CandleKit ships no intent type, because intents must live in your app target. See `docs/guides/app-intents.md` in the repository for the pattern and the Demo's `ShowChartIntent`.
