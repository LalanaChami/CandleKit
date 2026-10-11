# Design note: multi-symbol comparison (roadmap 7.6)

Status: **implemented, uncompiled and not yet checked on a device.** Answers open question 8 in
`docs/ROADMAP.md` as a recommendation for the maintainer to confirm or overrule.

## 1. A mode of `CandlestickChart`, not a second view

Comparison is `.comparing([ComparisonSeries])` on the existing view. The viewport, gestures,
crosshair, time axis, drawings and accessibility all hang off one primary series; a second public
view would copy every one of them and then have to be kept in step. The cost is that the primary
series stays special: it defines the x positions and the raw price scale.

## 2. Alignment by timestamp

The x-axis is index-based, so a second symbol has to be placed on the primary's indices.
`SeriesAlignment.align(primary:other:maxGap:)` (Core, O(n + m)) gives, for each primary candle, the
most recent `other` close at or before its time. It returns `nil` before `other` starts and when
that close is older than `maxGap` (default: three times `other`'s typical interval). A closed market
therefore shows as a break in the line, not an invented flat stretch.

## 3. Normalization without touching the candle renderer

Percent change and "indexed to 100" are both linear in price. So each comparison series is multiplied
by one constant, chosen so it equals the primary's close at the first visible candle where it has a
value, and is then drawn with the existing price scale. Only the axis changes meaning:

- axis base = primary close at the first visible candle (0% or 100 there);
- ticks are chosen in axis space (round percentages) and mapped back to price positions;
- the crosshair tag, the last-price tag and tick labels use the same conversion
  (`ComparisonScaling.axisValue(forPrice:)` / `price(forAxisValue:)`).

The scaling is O(visible) (`ComparisonMath.scaling`). It is recomputed on the same cadence as the
cached price range (not while scrolling), so lines don't slide against candles during a pan, and the
axis re-bases when the person stops or zooms. The chart's autoscale range is widened by the lines'
extent over the same ±15-candle window.

## 4. Deferred, on purpose

- A true secondary price axis (a second set of tick labels in another series' own units).
- Per-series dash styles beyond color and width.
- Comparison in `ChartLayout` (saved layouts).
- The header, accessibility summary and drawings still show the primary's own prices; drawings stay
  in primary-price space, which is the geometry space, so they keep working.
- Comparison series are not shown in the crosshair tag itself; the legend in the chart's corner follows
  the crosshair instead.
