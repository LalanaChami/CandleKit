---
id: market-data
title: Market Data Tools
sidebar_label: Market Data Tools
---

# Market Data Tools

The order book, the depth chart and the tape show what candles can't: who is waiting to trade and who just traded. CandleKit displays the data you give it. It does not connect to an exchange, place orders or give advice.

The three views take plain values and need no chart. The three overlays are modifiers on `CandlestickChart`.

## Data conventions

- **Sort order.** `OrderBook.bids` is sorted by price descending and `asks` ascending, so index 0 is the best price on each side. Pass levels to `OrderBook(bids:asks:)` in any order.
- **A size is a total.** `OrderBookLevel.size` is everything resting at that price. An `OrderBookUpdate` carries the new total, not a difference, and a size of zero removes the level.
- **Numbers are `Double`,** like `Candle`. Two levels are the same level when their prices are equal as `Double`; a feed that sends the same price text always parses to the same value.
- **A trade's side is the aggressor** (the taker): `.buy` lifted the ask, `.sell` hit the bid.

## Feeding an order book

```swift
@State private var store = OrderBookStore()

store.reset(bids: snapshot.bids, asks: snapshot.asks)   // on connect
store.apply(updates)                                    // on every feed message
```

A level 2 feed can change twenty times a second, which is too fast to read and wasteful to draw. `OrderBookStore` keeps the full book current and publishes `store.book`, trimmed to `depth` levels per side, at most once per `publishInterval` (0.2 seconds by default). If you manage the book yourself, hold an `OrderBook` in your own state and call `apply(_:)` on it; throttle how often you hand it to a view.

`book.isCrossed` is `true` when the best bid is at or above the best ask. That means an update was missed; request a fresh snapshot.

## Order book ladder

```swift
OrderBookView(store.book)
    .rowsPerSide(12)
    .priceGrouping(0.5)
    .onSelectPrice { price in draftOrderPrice = price }
```

Asks are listed above the spread and bids below it. Each row shows price, size and the running total, and the bar behind a row is the running total relative to the deepest row shown. `priceGrouping` merges levels into buckets: bids round down and asks round up, so a grouped price is never better than a real level inside it.

## Depth chart

```swift
DepthChartView(store.book)
    .depthWindow(0.02)      // 2% either side of the mid price
    .frame(height: 180)
```

## Time and sales

```swift
@State private var tape = TradeTape(capacity: 200)

tape.append(MarketTrade(id: "t1", time: .now, price: 100.5, size: 0.2, side: .buy))

TimeAndSalesView(tape.trades)
    .minimumSize(0.01)
    .largeTradeSize(5)
```

`TradeTape` keeps the newest trades and ignores an immediate repeat of the last id, which feeds send on reconnect.

### Worked example: the Coinbase side flip

Coinbase's `matches` channel reports the **maker's** side. The aggressor is the opposite:

```swift
// {"type":"match","trade_id":123,"side":"sell","price":"100.50","size":"0.2", ...}
let aggressor: MarketTrade.Side = makerSide == "sell" ? .buy : .sell
```

For a feed that reports no side at all, `TradeMath.tickRuleSide(price:previousPrice:previousSide:)` guesses it from the direction of the last price change.

## Buy and sell volume

```swift
let flow = TradeMath.flow(of: tape.trades)            // buyVolume, sellVolume, delta, vwap
let perCandle = TradeAggregation.flows(trades: trades, candles: candles, interval: 60)
let cvd = TradeAggregation.cumulativeDelta(perCandle) // cumulative volume delta
let lean = OrderBookMath.imbalance(of: store.book, depth: 10)   // -1 all asks ... +1 all bids
```

These are numbers for your own views. A chart pane for delta is planned (roadmap 12.15).

## Overlays on the chart

```swift
CandlestickChart(candles)
    .quoteLines(bid: store.book.bestBid?.price, ask: store.book.bestAsk?.price)
    .depthOverlay(store.book)
    .orderLines(orders, tick: 0.01) { id, newPrice in broker.move(id, to: newPrice) }
```

- **`quoteLines`** draws dashed lines at the best bid and ask.
- **`depthOverlay`** draws the book as bars along the left edge of the plot, lined up with the price axis. It walks every level of the book on each redraw, so pass a trimmed book (`OrderBookStore.book` already is).
- **`orderLines`** draws each `ChartOrderLine` as a labelled line. A line with `isDraggable: true` can be dragged by its tag. When the drag ends the callback receives the id and the new price, rounded to `tick`. The line returns to its old price until you update the array, so the app stays in charge of what a drag means.

`marketDataStyle(_:)` on the views and on the chart sets the bid and ask colors and the number formatting.

## Previews and tests

`MarketSampleData.orderBook()` and `MarketSampleData.trades(count:)` return the same data for the same seed.
