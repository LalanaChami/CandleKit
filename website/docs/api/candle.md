---
id: candle
title: Candle
sidebar_label: Candle
---

# `Candle`

One OHLCV bar.

```swift
public struct Candle: Hashable, Sendable, Identifiable
```

:::caution
Series passed to `CandlestickChart` must be sorted by `time` in ascending order, with no duplicate
times.
:::

## Fields

| Field | Type | Description |
| --- | --- | --- |
| `time` | `Date` | The bar's timestamp. |
| `open` | `Double` | Opening price. |
| `high` | `Double` | Highest price during the period. |
| `low` | `Double` | Lowest price during the period. |
| `close` | `Double` | Closing price. |
| `volume` | `Double` | Traded volume. |

## Initializer

```swift
public init(time: Date, open: Double, high: Double, low: Double, close: Double, volume: Double = 0)
```

`volume` defaults to `0` when you don't have volume data.

## Computed properties

```swift
public var id: Date { time }
```

`Identifiable` conformance — `id` is just `time`.

```swift
public var isBullish: Bool
```

`true` when the candle closed at or above its open (`close >= open`).

## `CandleSampleData`

`CandleKitCore` ships a deterministic fake data generator, useful for previews, demos and tests:

```swift
public enum CandleSampleData {
    public static func randomWalk(
        count: Int,
        start: Date = /* 2026-01-01 00:00 UTC */,
        interval: TimeInterval = 3_600,
        startPrice: Double = 100,
        volatility: Double = 0.01,
        seed: UInt64 = 42
    ) -> [Candle]
}
```

The same `seed` always produces the same candles, so your previews and screenshots stay stable
across runs. Prices are rounded to two decimal places, so `startPrice` must be at least `1`.

```swift
let candles = CandleSampleData.randomWalk(count: 200)
let volatileCandles = CandleSampleData.randomWalk(count: 500, startPrice: 50_000, volatility: 0.02)
```
