# Home-screen widget (roadmap 8.1)

## Decision

The widget does not host `CandlestickChart`. It uses a separate view, `WidgetCandleChart`, in a
separate SPM product, `CandleKitWidgets`, that depends only on `CandleKitCore`.

## Why not the full chart

- A widget is a rendered snapshot: no gestures, no scrolling, no animation. Most of `CandlestickChart`
  (viewport, crosshair, drawings, state object, display link) would be dead weight.
- Extensions have a small memory budget and a short render window. `CandleChartState` and its
  layers are built for a long-lived interactive view.
- `Canvas` drawing in a widget snapshot is not something I could confirm renders reliably, so the
  widget view draws with `Shape`/`Path`, which WidgetKit always renders.

## What it does

- Reduces the series with `CandleAggregator.downsample(_:maxCount:)` (Core, tested) so draw cost is
  bounded by `maxCandles` (default 40) however long the data is.
- Scales prices with `PriceScale.autoRange` and `LinearScale`, the same code the main chart uses.
- Draws wicks and bodies as four batched paths (bullish/bearish by wick/body), or a close line with a
  gradient fill (`.line`).
- Optional last-price label; a VoiceOver summary (last price and change over the shown span).

## Deliberately absent

Axes, grid, volume, indicators, crosshair, interaction. A widget this small can't carry axis labels
legibly; the host adds its own header (symbol, price) as the demo does.

## Data flow (host's job)

The host app or a background task writes recent candles to storage the extension can read (typically
an App Group container); `TimelineProvider.getTimeline` loads and passes them in. The Demo's widget
uses simulated candles instead so it needs no App Group or signing setup. Keep stored history to a
few hundred candles.

## Not verified

Written and reviewed without building the extension target. Needs: `xcodegen generate` in `Demo/`,
a build, and a look at small/medium/large in the widget gallery, plus a real-data App Group setup in
an actual app.
