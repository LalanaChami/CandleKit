---
id: trader-tools
title: Trader Tools
sidebar_label: Trader Tools
---

# Trader Tools

Features aimed at making and planning trades. All are opt-in and add nothing to a chart that doesn't use them.

## Series types

```swift
CandlestickChart(candles).seriesType(.heikinAshi)
```

`.candles`, `.ohlcBars`, `.line`, `.area` and `.heikinAshi`. Heikin-Ashi shows smoothed values in the header and last-price tag.

## Scrolling to a date

```swift
chartState.scroll(to: earningsDate, alignment: .center, animated: true)
chartState.setVisibleCandleCount(60)
```

`visibleDateRange` gives the first and last visible candle times.

## Event markers

```swift
CandlestickChart(candles)
    .eventMarkers(events) { cluster in selected = cluster.events }
```

Earnings, dividends, splits, news or your own. Close markers merge into one with a count.

## Volume profile and anchored VWAP

```swift
CandlestickChart(candles)
    .volumeProfile()
    .indicators([.anchoredVWAP(from: swingLowDate, bands: 1)])
```

## Position and risk

Pick the **Risk** tool and drag from entry to target. The stop starts at half the distance on the other side (a 2:1 plan); drag any handle to change it. `PositionPlan` computes reward-to-risk and a position size from your risk amount.

## Channels and Fibonacci extension

Both are three-point tools. After the two-point drag a third point is placed for you; select the drawing and drag its handles.

These tools show information, not advice. Volume profile and VWAP are computed from candle data, not exchange volume-at-price, and the risk tool ignores fees and slippage.
