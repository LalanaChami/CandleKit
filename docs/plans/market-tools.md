# Plan: market data tools (order book, depth, time and sales, order lines)

Roadmap phase 12. Written 2026-11-14 against `main` at `d690914` plus the trader-tools docs commit
and the review-fixes commit.

This plan is written so that each step can be done on its own, in order, by someone who has not
seen the rest of the project. Every step names its files, its public API, its tests with exact
expected values, the commands that prove it works, and when to stop and ask.

---

## 1. What is being built, and why these tools

CandleKit draws price over time. Traders also decide from **who is waiting to trade** (the order
book) and **who just traded** (the tape). These are the tools that show that, ranked by how often
trading apps need them and how well they fit a chart library.

| Step | Tool | What the trader reads from it | Needs |
| --- | --- | --- | --- |
| 12.1–12.2 | **Order book model** (Core) | Best bid and ask, spread, depth, imbalance | Level 2 feed |
| 12.3–12.4 | **Trade model and flow** (Core) | Buy vs sell volume, delta, tape VWAP | Trade feed |
| 12.7 | **Order book ladder** (`OrderBookView`) | Size resting at each price, where the walls are | Level 2 feed |
| 12.8 | **Depth chart** (`DepthChartView`) | Cumulative supply and demand around the mid price | Level 2 feed |
| 12.9 | **Time and sales** (`TimeAndSalesView`) | Each trade: time, price, size, aggressor; large prints | Trade feed |
| 12.10 | **Bid/ask lines on the chart** (`.quoteLines`) | Where the spread sits relative to candles | Quote |
| 12.11 | **Depth on the price axis** (`.depthOverlay`, roadmap 9.10) | Book walls lined up with chart prices | Level 2 feed |
| 12.12 | **Order and position lines** (`.orderLines`, roadmap 9.7) | Open orders, entry, stop and target, draggable | App's orders |
| 12.13 | **Demo: Order flow tab** | — | — |
| 12.14 | **Docs** | — | — |

Deferred, recorded in the roadmap only (section 7 says why): volume delta and cumulative volume
delta pane, footprint (cluster) candles, liquidity heatmap, large-trade bubbles on the chart,
order-book imbalance history, options chain, screener heatmap.

CandleKit stays a display library: it never connects to an exchange, places an order or gives
advice. The app supplies the data and handles every action.

---

## 2. Rules for whoever executes this plan

Read `CLAUDE.md` and the three files in `.claude/rules/` first. They are short and they win over
this plan if the two disagree; if they disagree, stop and report it.

### Commands (run from the repo root unless stated)

```bash
swift test                                   # Core tests. Must pass after every step.
swift test --filter OrderBook                # one suite while iterating
xcodebuild build -quiet -scheme CandleKit -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
                                             # the ONLY command that compiles Sources/CandleKit
cd Demo && xcodegen generate && xcodebuild build -quiet -project CandleKitDemo.xcodeproj \
  -scheme CandleKitDemo -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

`swift build` passing says nothing about `Sources/CandleKit/` (every file there is inside
`#if os(iOS)`).

### Working rules

1. **One step, one branch, one commit.** Branch `feature/12.N-short-name` from the previous step.
   The commit message is given in each step and starts with the roadmap ID.
2. **Do the steps in order.** Steps 12.1–12.6 are Core only and need only `swift test`. Do not
   start a view step before the Core step it uses is committed with passing tests.
3. **Do not change anything this plan does not name.** No refactors, no renames, no "while I'm
   here" fixes, no performance changes. If something else looks wrong, add a row to "Known issues"
   in `docs/ROADMAP.md` and carry on.
4. **Do not change the expected values in tests.** They were computed independently (Python). If a
   test fails, the implementation is wrong. If you are certain a value in this plan is wrong, stop
   and report it with your working.
5. **No new dependencies.** No edits to `Package.swift` (no new targets or products are needed).
6. **Every public symbol gets a `///` doc comment.** One or two sentences, saying what it is and
   any limit. No comment that only repeats the name.
7. **Swift 6 strict concurrency.** Never add `@unchecked Sendable`, `nonisolated(unsafe)` or
   `@preconcurrency`. Core types are `Sendable` value types.
8. **Stop and ask** (do not guess) when: a command in "Verify" fails and two attempts have not
   fixed it; a step needs a file or symbol that doesn't exist where this plan says it is; a step
   seems to need a change to gestures, `CandleChartState.makeFrame` or `buildFrame`, or
   `ChartGestureView`; or the type-checker reports "unable to type-check this expression in
   reasonable time" in a file this plan didn't ask you to edit.
9. **Report after each step** in this shape:
   - Verified: the commands you ran and their result.
   - Not verified: everything that needs a Simulator or device (list what to look at).
   - Deviations: anything done differently from this plan, and why.

### Pitfalls that have already cost time on this project

- A SwiftUI `body` with too many modifiers stops type-checking. Keep each `body` small; move rows
  and sections into separate `private var` or small `View` structs.
- Memberwise initializers take arguments **in property declaration order**. When you add a stored
  property to a view, add the argument at the same position in every call.
- Never mutate an `@Observable` property from inside a view `body` or from `makeFrame`.
- `Demo/CandleKitDemo.xcodeproj` is generated and gitignored. After adding or removing a Demo
  file, run `xcodegen generate` in `Demo/`. Never edit the project file.
- The Demo has its own type named `Trade` (`Demo/CandleKitDemo/Data/MarketModels.swift`). The
  library type is called `MarketTrade` so the two never clash.

---

## 3. Design decisions (fixed; do not revisit)

**Where code goes.** Models and maths: `Sources/CandleKitCore/Market/` (Foundation only, tested).
Views and chart layers: `Sources/CandleKit/Market/` (SwiftUI, each file wrapped in
`#if os(iOS)` … `#endif`). Tests: `Tests/CandleKitCoreTests/`. Apps keep writing only
`import CandleKit`, which re-exports Core.

**The standalone views do not need a chart.** `OrderBookView`, `DepthChartView` and
`TimeAndSalesView` take plain values and can be placed anywhere. The three chart overlays are
modifiers on `CandlestickChart`.

**The app owns the data and the connection.** Views take values (`OrderBook`, `[MarketTrade]`).
The app updates its own state and SwiftUI redraws. `OrderBookStore` (step 12.6) is an optional
helper for the common case.

**Numbers are `Double`,** like `Candle`. Two levels are the same level when their prices are equal
as `Double`; a feed that sends the same price string always parses to the same `Double`.

**Order book conventions.** `bids` are sorted by price **descending**, `asks` **ascending**, so
index 0 is always the best price on each side. A size is the **total** resting at that price. An
update with size `0` (or a non-finite or negative size) removes the level.

**Trade side means the aggressor** (the taker): `.buy` lifted the ask, `.sell` hit the bid. Some
feeds report the maker's side instead (Coinbase does); the app flips it when it builds the trade.

**Colors.** Bids and buys use `MarketDataStyle.bidColor`, asks and sells `askColor`. Defaults are
the same green and red as `CandleChartStyle.standard`. No hard-coded colors in view code.

**Performance budget.** A book feed can send 20 updates a second and a tape hundreds of trades a
second. So: views draw a fixed, small number of rows (never the whole book); no formatter is
created per row; the depth chart is a single `Canvas`; nothing sorts the whole book per frame
(`OrderBook` keeps itself sorted); `OrderBookStore` publishes at most 5 times a second by default.

---

## 4. What using it looks like (the target API)

This is what the finished work lets an app write. Use it to check each step against.

```swift
import CandleKit

@State private var book = OrderBookStore()          // optional helper; plain OrderBook works too
@State private var trades = TradeTape(capacity: 200)

// From your feed:
book.reset(bids: snapshotBids, asks: snapshotAsks)
book.apply([OrderBookUpdate(side: .bid, price: 100.25, size: 0.75)])
trades.append(MarketTrade(id: "t1", time: .now, price: 100.5, size: 0.2, side: .buy))

// Standalone views:
OrderBookView(book.book)
    .rowsPerSide(12)
    .priceGrouping(0.5)
    .onSelectPrice { price in draftOrderPrice = price }

DepthChartView(book.book)
    .depthWindow(0.02)                               // ±2% around the mid price

TimeAndSalesView(trades.trades)
    .largeTradeSize(5)

// On the chart:
CandlestickChart(candles)
    .quoteLines(bid: book.book.bestBid?.price, ask: book.book.bestAsk?.price)
    .depthOverlay(book.book)
    .orderLines(orders) { id, newPrice in broker.move(id, to: newPrice) }
```

---

## 5. Test fixture used by several steps

The Core tests share one book. Put this helper at the top of each test file that needs it (copy
it; do not create a shared test-support file).

```swift
private func level(_ price: Double, _ size: Double) -> OrderBookLevel { OrderBookLevel(price: price, size: size) }

/// Bids 100.0…98.0, asks 100.5…102.5. Passed deliberately unsorted to prove `init` sorts.
private var sampleBook: OrderBook {
    OrderBook(
        bids: [level(99.0, 4.0), level(100.0, 1.5), level(98.0, 3.0), level(99.5, 2.0), level(98.5, 0.5)],
        asks: [level(101.5, 1.5), level(100.5, 1.0), level(102.5, 0.5), level(101.0, 2.5), level(102.0, 6.0)]
    )
}
```

Compare `Double` results with `abs(a - b) < 1e-9` unless the plan says "exactly".

---

## 6. Steps

### 12.0 Baseline (no code)

1. `git status` is clean and you are on `main` (or the branch the maintainer named).
2. Confirm these exist: `Sources/CandleKit/VolumeProfileLayer.swift`,
   `Sources/CandleKit/EventMarkersLayer.swift`, `docs/ROADMAP.md` containing "9.10 Market depth".
   If the roadmap has no 9.10, the trader-tools docs commit is missing: stop and report.
3. Run all three command groups from section 2. All must pass **before** you change anything. If
   any fails, stop and report the output; do not fix it as part of this plan.

---

### 12.1 Core: `OrderBook`

**Files**
- New `Sources/CandleKitCore/Market/OrderBook.swift`
- New `Tests/CandleKitCoreTests/OrderBookTests.swift`

**API** (write exactly these names and signatures)

```swift
import Foundation

/// Which side of the book a level is on.
public enum OrderBookSide: String, Sendable, Hashable, Codable, CaseIterable {
    /// Buyers waiting below the market.
    case bid
    /// Sellers waiting above the market.
    case ask
}

/// The total size resting at one price.
public struct OrderBookLevel: Sendable, Hashable, Codable {
    public var price: Double
    public var size: Double
    public init(price: Double, size: Double)
}

/// A change to one price level. `size` is the new total at that price, not a difference;
/// zero (or a negative or non-finite size) removes the level.
public struct OrderBookUpdate: Sendable, Hashable, Codable {
    public var side: OrderBookSide
    public var price: Double
    public var size: Double
    public init(side: OrderBookSide, price: Double, size: Double)
}

/// A level 2 order book: the size resting at each price on both sides.
public struct OrderBook: Sendable, Equatable {
    /// Buy levels, highest price first, so `bids[0]` is the best bid.
    public private(set) var bids: [OrderBookLevel]
    /// Sell levels, lowest price first, so `asks[0]` is the best ask.
    public private(set) var asks: [OrderBookLevel]

    public init(bids: [OrderBookLevel] = [], asks: [OrderBookLevel] = [])

    public var isEmpty: Bool { get }
    public var bestBid: OrderBookLevel? { get }
    public var bestAsk: OrderBookLevel? { get }
    /// Halfway between the best bid and best ask; `nil` unless both exist.
    public var midPrice: Double? { get }
    /// Best ask minus best bid; `nil` unless both exist. Negative when the book is crossed.
    public var spread: Double? { get }
    /// The spread as a share of the mid price, in basis points (1 bp = 0.01%).
    public var spreadBasisPoints: Double? { get }
    /// `true` when the best bid is at or above the best ask, which means the data is inconsistent
    /// (usually a missed update).
    public var isCrossed: Bool { get }

    public func levels(_ side: OrderBookSide) -> [OrderBookLevel]
    /// Sets, replaces or removes one level, keeping the side sorted.
    public mutating func apply(_ update: OrderBookUpdate)
    public mutating func apply(_ updates: [OrderBookUpdate])
    /// Replaces the whole book, for a fresh snapshot.
    public mutating func reset(bids: [OrderBookLevel], asks: [OrderBookLevel])
    /// A copy holding only the best `depth` levels on each side.
    public func trimmed(depth: Int) -> OrderBook
}
```

**Behaviour**
- `init` and `reset` clean their input: drop a level whose price is not finite or is `<= 0`, or
  whose size is not finite or is `<= 0`; if a price appears twice the **later** one wins; then
  sort (bids descending, asks ascending).
- `apply(_:)` with one update: ignore it if the price is not finite or `<= 0`. Find the price with
  a **binary search** in the sorted side (remember bids are descending). If the size is finite and
  `> 0`: replace the size if the price exists, otherwise insert at the sorted position. Otherwise:
  remove the level if it exists, do nothing if it doesn't.
- `spreadBasisPoints` is `spread / midPrice * 10_000`; `nil` if mid is `nil` or `0`.
- `trimmed(depth:)` with `depth <= 0` returns an empty book.
- Nothing here may crash on any input. No `precondition`, no force unwrap.

**Tests** (`@Suite("Order book")`, using `sampleBook` from section 5)

| Test | Expect |
| --- | --- |
| `initSorts` | `bids.map(\.price) == [100, 99.5, 99, 98.5, 98]`, `asks.map(\.price) == [100.5, 101, 101.5, 102, 102.5]` |
| `bestAndSpread` | bestBid price 100, size 1.5; bestAsk price 100.5, size 1.0; mid 100.25; spread 0.5; bps ≈ 49.87531172069826; `isCrossed == false` |
| `emptyBook` | `OrderBook()`: `isEmpty`, all five optionals `nil`, `isCrossed == false` |
| `oneSided` | bids only: `midPrice`, `spread`, `spreadBasisPoints` are `nil`; `bestBid` is not |
| `initDropsBadLevels` | bids `[(100, 1), (.nan, 1), (99, 0), (98, -1), (-5, 1), (97, .infinity)]` → prices `[100]` |
| `initLaterDuplicateWins` | bids `[(100, 1), (100, 7)]` → one level, size 7 |
| `applyUpdates` | start from `sampleBook`, apply in order: bid 99.5 size 0; bid 100.25 size 0.75; ask 100.5 size 3.0; ask 103.0 size 1.0; bid 97.0 size 0 (not present); ask 101.0 size `.nan`. Result bids `[(100.25, 0.75), (100, 1.5), (99, 4), (98.5, 0.5), (98, 3)]`, asks `[(100.5, 3), (101.5, 1.5), (102, 6), (102.5, 0.5), (103, 1)]` |
| `applyIgnoresBadPrice` | applying bid price `.nan` size 1, and bid price 0 size 1, leaves `sampleBook` equal to itself |
| `crossedBook` | bids `[(101, 1)]`, asks `[(100, 1)]` → `isCrossed`, spread −1 |
| `trimmed` | `sampleBook.trimmed(depth: 2)`: bid prices `[100, 99.5]`, ask prices `[100.5, 101]`; `trimmed(depth: 0).isEmpty`; `trimmed(depth: 99) == sampleBook` |
| `resetReplaces` | after `reset(bids: [(50, 1)], asks: [(51, 2)])` the book equals `OrderBook(bids: [(50,1)], asks: [(51,2)])` |

**Verify:** `swift test` (all suites pass).
**Commit:** `12.1: Order book model (Core)`

---

### 12.2 Core: order book maths (grouping, depth, imbalance, ladder, depth curve)

**Files**
- New `Sources/CandleKitCore/Market/OrderBookMath.swift`
- New `Tests/CandleKitCoreTests/OrderBookMathTests.swift`

**API**

```swift
import Foundation

/// A level together with the running total of size from the best price out to it.
public struct DepthLevel: Sendable, Hashable {
    public var price: Double
    public var size: Double
    public var cumulativeSize: Double
    public init(price: Double, size: Double, cumulativeSize: Double)
}

/// Pure calculations on an order book.
public enum OrderBookMath {
    /// Merges levels into price buckets `tick` wide. Bids round **down** to a bucket and asks round
    /// **up**, so a grouped price is never better than any real level inside it. Input and output
    /// are best-first. A `tick` that is not finite or is `<= 0` returns `levels` unchanged.
    public static func grouped(_ levels: [OrderBookLevel], side: OrderBookSide, tick: Double) -> [OrderBookLevel]

    /// Running totals, best price first.
    public static func cumulative(_ levels: [OrderBookLevel]) -> [DepthLevel]

    /// Bid size minus ask size over their sum, across the best `depth` levels of each side:
    /// +1 is all bids, −1 all asks. `nil` when there is no size at all or `depth <= 0`.
    public static func imbalance(of book: OrderBook, depth: Int) -> Double?

    /// Bid and ask size per price bucket across `priceRange`, for drawing the book against a price
    /// axis. Bucket 0 starts at `priceRange.lowerBound`. Levels outside the range are skipped.
    /// Returns empty arrays when `bucketCount < 1` or the range has no height.
    public static func buckets(
        of book: OrderBook, priceRange: ClosedRange<Double>, bucketCount: Int
    ) -> (bids: [Double], asks: [Double])
}

/// The rows an order-book ladder shows: the best levels of each side with their running totals.
public struct OrderBookLadder: Sendable, Equatable {
    public struct Row: Sendable, Hashable, Identifiable {
        public var side: OrderBookSide
        public var price: Double
        public var size: Double
        public var cumulativeSize: Double
        /// `cumulativeSize` as a share (0...1) of the largest running total on either side.
        public var depthFraction: Double
        public var id: Double { price }
    }
    /// Best ask first.
    public var asks: [Row]
    /// Best bid first.
    public var bids: [Row]
    /// The largest running total among the rows shown; `0` for an empty ladder.
    public var maxCumulativeSize: Double

    /// - Parameters:
    ///   - rowsPerSide: how many rows to keep on each side (values below 1 give an empty ladder).
    ///   - tick: group prices into buckets this wide first; `nil` shows the raw levels.
    public init(book: OrderBook, rowsPerSide: Int, tick: Double? = nil)
}

/// Points for a depth chart: cumulative size on each side within a window around the mid price.
public struct DepthCurve: Sendable, Equatable {
    /// Best bid first (prices descending), cumulative size rising.
    public var bids: [DepthLevel]
    /// Best ask first (prices ascending), cumulative size rising.
    public var asks: [DepthLevel]
    public var midPrice: Double
    /// From the lowest bid shown to the highest ask shown.
    public var priceRange: ClosedRange<Double>
    public var maxCumulativeSize: Double

    /// `nil` unless both sides have at least one level inside the window.
    /// - Parameter window: how far from the mid price to include, as a share of it (0.02 = ±2%).
    ///   Values that are not finite or are `<= 0` include every level.
    public init?(book: OrderBook, window: Double = 0.02)
}
```

**Behaviour**
- `grouped`: bucket index is `Int((price / tick + 1e-9).rounded(.down))` for bids and
  `Int((price / tick - 1e-9).rounded(.up))` for asks; the bucket's price is
  `Double(index) * tick`. Because the input is sorted, levels of one bucket are adjacent: walk the
  list once and add to the last output bucket while the index is the same. The epsilon stops
  `0.3 / 0.1 == 2.9999999999999996` from landing in the wrong bucket.
- `buckets`: `height = (upper - lower) / Double(bucketCount)`; a level at `price` goes in
  `min(bucketCount - 1, Int(((price - lower) / height).rounded(.down)))`; skip levels with
  `price < lower` or `price > upper`.
- `OrderBookLadder.init`: group each side if `tick` is given, take the first `rowsPerSide`,
  compute running totals, then `maxCumulativeSize = max(last bid total, last ask total)` and
  `depthFraction = cumulativeSize / maxCumulativeSize` (0 when the max is 0).
- `DepthCurve.init?`: needs `book.midPrice`. Keep bids with `price >= mid * (1 - window)` and asks
  with `price <= mid * (1 + window)`. `priceRange` is `bids.last.price ... asks.last.price`.

**Tests** (`@Suite("Order book maths")`)

| Test | Expect |
| --- | --- |
| `cumulativeBids` | cumulative of `sampleBook.bids` → totals `[1.5, 3.5, 7.5, 8.0, 11.0]` |
| `cumulativeAsks` | → `[1.0, 3.5, 5.0, 11.0, 11.5]` |
| `imbalance` | depth 1 → 0.2; depth 3 → 0.2; depth 5 → −0.022222222222222223; depth 10 → same as 5; depth 0 → `nil`; empty book → `nil` |
| `groupBidsRoundDown` | bids, tick 1.0 → `[(100, 1.5), (99, 6.0), (98, 3.5)]` |
| `groupAsksRoundUp` | asks, tick 1.0 → `[(101, 3.5), (102, 7.5), (103, 0.5)]` |
| `groupSmallTicks` | bids `[(0.3,1), (0.29,2), (0.21,3), (0.2,4)]`, tick 0.1 → 2 levels, prices ≈ `[0.3, 0.2]`, sizes `[1, 9]`. Asks `[(0.3,1), (0.31,2), (0.4,3), (0.41,4)]`, tick 0.1 → 3 levels, prices ≈ `[0.3, 0.4, 0.5]`, sizes `[1, 5, 4]` |
| `groupBadTickIsIdentity` | tick `0`, `-1`, `.nan` each return the input unchanged |
| `buckets` | `sampleBook`, range `98...103`, 5 buckets → bids `[3.5, 6.0, 1.5, 0, 0]`, asks `[0, 0, 1.0, 4.0, 6.5]`; `bucketCount: 0` → both empty; range `100...100` → both empty |
| `ladderRaw` | `rowsPerSide: 3` → bid prices `[100, 99.5, 99]`, ask prices `[100.5, 101, 101.5]`, max 7.5, bid fractions ≈ `[0.2, 0.4666666666666667, 1.0]`, ask fractions ≈ `[0.13333333333333333, 0.4666666666666667, 0.6666666666666666]` |
| `ladderGrouped` | `rowsPerSide: 2, tick: 1.0` → bids `[(100, 1.5, total 1.5), (99, 6.0, total 7.5)]`, asks `[(101, 3.5, total 3.5), (102, 7.5, total 11.0)]`, max 11.0 |
| `ladderEmpty` | empty book, or `rowsPerSide: 0` → no rows, max 0 |
| `depthCurve` | `window: 0.01` → mid 100.25; bids `[(100, total 1.5), (99.5, total 3.5)]`; asks `[(100.5, total 1.0), (101, total 3.5)]`; max 3.5; `priceRange == 99.5...101` |
| `depthCurveWholeBook` | `window: 0` → 5 bids, 5 asks, max 11.5 |
| `depthCurveNeedsBothSides` | a book with bids only → `nil` |

**Verify:** `swift test`.
**Commit:** `12.2: Order book grouping, depth, imbalance and ladder maths (Core)`

---

### 12.3 Core: `MarketTrade`, `TradeTape`, `TradeFlow`

**Files**
- New `Sources/CandleKitCore/Market/MarketTrade.swift`
- New `Tests/CandleKitCoreTests/MarketTradeTests.swift`

**API**

```swift
import Foundation

/// One executed trade (a "print" on the tape).
public struct MarketTrade: Sendable, Hashable, Identifiable {
    /// Who crossed the spread to make the trade happen.
    public enum Side: String, Sendable, Hashable, Codable, CaseIterable {
        /// A buyer took the offer. Usually drawn green.
        case buy
        /// A seller hit the bid. Usually drawn red.
        case sell
        /// The feed didn't say. See `TradeMath.tickRuleSide`.
        case unknown
    }
    /// Unique within the feed, for example the exchange's trade id.
    public var id: String
    public var time: Date
    public var price: Double
    public var size: Double
    public var side: Side
    public init(id: String, time: Date, price: Double, size: Double, side: Side = .unknown)
}

/// The most recent trades, oldest first, never more than `capacity`.
public struct TradeTape: Sendable, Equatable {
    public let capacity: Int
    public private(set) var trades: [MarketTrade]
    /// - Parameter capacity: values below 1 are treated as 1.
    public init(capacity: Int = 200)
    /// Adds a trade as the newest. A trade with the same `id` as the current newest is ignored
    /// (feeds resend the last trade on reconnect).
    public mutating func append(_ trade: MarketTrade)
    public mutating func append(contentsOf newTrades: [MarketTrade])
    public mutating func removeAll()
}

/// Totals over a group of trades.
public struct TradeFlow: Sendable, Equatable {
    public var buyVolume: Double
    public var sellVolume: Double
    public var unknownVolume: Double
    public var tradeCount: Int
    /// Sum of price × size.
    public var notional: Double
    public init(buyVolume: Double = 0, sellVolume: Double = 0, unknownVolume: Double = 0, tradeCount: Int = 0, notional: Double = 0)

    public var totalVolume: Double { get }
    /// Buy volume minus sell volume. Positive means buyers were the aggressors.
    public var delta: Double { get }
    /// Volume-weighted average price of these trades; `nil` with no volume.
    public var vwap: Double? { get }
    /// Buy volume as a share (0...1) of buy plus sell volume; `nil` when both are zero.
    public var buyShare: Double? { get }
    /// Adds one trade. A trade whose price or size is not finite, or whose size is `<= 0`, is skipped.
    public mutating func add(_ trade: MarketTrade)
}

/// Pure calculations on trades.
public enum TradeMath {
    /// Totals for `trades`.
    public static func flow(of trades: [MarketTrade]) -> TradeFlow
    /// Guesses the aggressor for a feed that doesn't report it (the "tick rule"): a higher price
    /// than the previous trade is a buy, a lower one a sell, an equal one keeps `previousSide`.
    public static func tickRuleSide(price: Double, previousPrice: Double?, previousSide: MarketTrade.Side) -> MarketTrade.Side
}
```

**Behaviour**
- `TradeTape.append`: append, then if `trades.count > capacity` remove from the front
  (`trades.removeFirst(trades.count - capacity)`). Simple is fine: capacity is small.
- `tickRuleSide` with `previousPrice == nil` returns `previousSide`.

**Tests** (`@Suite("Market trades")`). Shared data, times are seconds since 1970:

```swift
private func trade(_ id: String, _ t: Double, _ price: Double, _ size: Double, _ side: MarketTrade.Side) -> MarketTrade {
    MarketTrade(id: id, time: Date(timeIntervalSince1970: t), price: price, size: size, side: side)
}
private var sampleTrades: [MarketTrade] {
    [
        trade("1", 0, 100.0, 0.5, .buy), trade("2", 10, 100.5, 1.5, .sell), trade("3", 59, 101.0, 2.0, .buy),
        trade("4", 60, 100.0, 1.0, .unknown), trade("5", 125, 99.0, 4.0, .sell), trade("6", 130, 99.5, 0.25, .buy),
        trade("7", 200, 98.0, 1.0, .sell),
    ]
}
```

| Test | Expect |
| --- | --- |
| `flowTotals` | `TradeMath.flow(of: sampleTrades)`: buy 2.75, sell 6.5, unknown 1.0, count 7, notional 1021.625, total 10.25, delta −3.75, vwap ≈ 99.67073170731707, buyShare ≈ 0.2972972972972973 |
| `flowEmpty` | no trades: all zero, `vwap == nil`, `buyShare == nil` |
| `flowSkipsBadTrades` | adding trades with size 0, size −1, price `.nan`, size `.infinity` leaves a default `TradeFlow()` unchanged |
| `tapeKeepsNewest` | capacity 3, append the 7 sample trades → ids `["5", "6", "7"]` |
| `tapeIgnoresRepeatOfNewest` | capacity 10, append trade "1" twice → count 1; then "2", then "1" again → count 3 (only an immediate repeat is ignored) |
| `tapeCapacityFloor` | `TradeTape(capacity: 0).capacity == 1` |
| `tapeAppendContentsOf` | capacity 5, `append(contentsOf: sampleTrades)` → ids `["3","4","5","6","7"]` |
| `tickRule` | walk prices `[100, 100.5, 100.5, 100.2, 100.2, 100.2, 100.3]` starting with `previousPrice: nil`, `previousSide: .unknown`, feeding each result back in → `[.unknown, .buy, .buy, .sell, .sell, .sell, .buy]` |

**Verify:** `swift test`.
**Commit:** `12.3: Trade model, tape and flow totals (Core)`

---

### 12.4 Core: trades per candle and cumulative delta

**Files**
- New `Sources/CandleKitCore/Market/TradeAggregation.swift`
- New `Tests/CandleKitCoreTests/TradeAggregationTests.swift`

**API**

```swift
import Foundation

/// Groups trades by the candle they happened in.
public enum TradeAggregation {
    /// One `TradeFlow` per candle (same count and order as `candles`). A trade belongs to the last
    /// candle that opened at or before it; trades before the first candle, or more than `interval`
    /// after the last candle opened, are left out.
    public static func flows(trades: [MarketTrade], candles: [Candle], interval: TimeInterval) -> [TradeFlow]

    /// Running sum of `delta`, one value per flow (cumulative volume delta).
    public static func cumulativeDelta(_ flows: [TradeFlow]) -> [Double]
}
```

**Behaviour**
- Use the existing `EventMarkerLayout.candleIndex(for:in:interval:)` (in
  `Sources/CandleKitCore/ChartEvent.swift`) to find each trade's candle. Do not write a second
  search.
- Empty `candles` returns `[]`.

**Tests** (`@Suite("Trade aggregation")`). Candles open at 0, 60 and 120 seconds, `interval: 60`
(any OHLC values). Trades: `sampleTrades` from 12.3 **plus** `trade("8", -5, 100.0, 9.0, .buy)`.

| Test | Expect |
| --- | --- |
| `flowsPerCandle` | 3 flows. Candle 0: buy 2.5, sell 1.5, unknown 0, count 3, notional 402.75, delta 1.0, vwap 100.6875. Candle 1: unknown 1.0, count 1, notional 100.0, delta 0, `buyShare == nil`. Candle 2: buy 0.25, sell 4.0, count 2, notional 420.875, delta −3.75, vwap ≈ 99.02941176470588 |
| `tradesOutsideAreDropped` | total `tradeCount` across the 3 flows is 6 (trade "7" at 200s is past 120+60; trade "8" is before the first candle) |
| `cumulativeDelta` | `[1.0, 1.0, -2.75]` |
| `noCandles` | `flows(trades: sampleTrades, candles: [], interval: 60) == []`; `cumulativeDelta([]) == []` |

**Verify:** `swift test`.
**Commit:** `12.4: Trades per candle and cumulative delta (Core)`

---

### 12.5 Core: sample order book and trades

For previews, the Demo's offline mode, documentation and tests. Deterministic like
`CandleSampleData.randomWalk`.

**Files**
- New `Sources/CandleKitCore/Market/MarketSampleData.swift`
- New `Tests/CandleKitCoreTests/MarketSampleDataTests.swift`

**API**

```swift
import Foundation

/// Deterministic fake order books and trades for previews, demos and tests.
public enum MarketSampleData {
    /// A book with `levels` levels per side around `midPrice`, one `tick` apart, sizes growing
    /// loosely with distance from the mid. The same arguments always give the same book.
    public static func orderBook(midPrice: Double = 100, levels: Int = 25, tick: Double = 0.05, seed: UInt64 = 42) -> OrderBook

    /// `count` trades, `spacing` seconds apart starting at `start`, prices walking from `startPrice`.
    public static func trades(
        count: Int,
        start: Date = Date(timeIntervalSince1970: 1_767_225_600), // 2026-01-01 00:00 UTC
        spacing: TimeInterval = 1,
        startPrice: Double = 100,
        tick: Double = 0.05,
        seed: UInt64 = 42
    ) -> [MarketTrade]
}
```

**Behaviour** (use the existing `SplitMix64` in `Sources/CandleKitCore/SampleData.swift`)
- `orderBook`: for `i` in `0..<max(0, levels)`: bid price `midPrice - tick * (Double(i) + 0.5)`,
  ask price `midPrice + tick * (Double(i) + 0.5)`; size
  `((0.5 + generator.nextDouble() * 2) * (1 + Double(i) * 0.15) * 100).rounded() / 100`. Draw the
  bid size then the ask size for each `i`. Skip a bid whose price is `<= 0`. A `tick` that is not
  finite or `<= 0` is treated as `0.01`.
- `trades`: for each index, `step = Int((generator.nextDouble() * 5).rounded(.down)) - 2` (−2…2);
  `price = max(tick, previous + Double(step) * tick)`; side `.buy` if `step > 0`, `.sell` if
  `step < 0`, otherwise the previous trade's side (first trade: `.buy`); size
  `((0.01 + generator.nextDouble() * 2) * 100).rounded() / 100`; id `"s\(seed)-\(index)"`.

**Tests** (`@Suite("Market sample data")`) — properties only, no exact values:

| Test | Expect |
| --- | --- |
| `bookIsDeterministic` | two calls with the same arguments are `==`; a different seed is `!=` |
| `bookShape` | default call: 25 bids, 25 asks, not crossed, `midPrice` ≈ 100 (within 1e-9), bids strictly descending, asks strictly ascending, every size `> 0` |
| `bookZeroLevels` | `levels: 0` and `levels: -3` give an empty book |
| `tradesAreDeterministic` | same arguments `==`; ids unique; times strictly ascending; `count: 0` → `[]` |
| `tradesStayPositive` | `count: 500, startPrice: 0.1, tick: 0.05` → every price `> 0` and every size `> 0` |

**Verify:** `swift test`.
**Commit:** `12.5: Sample order book and trades (Core)`

---

### 12.6 Publishing throttle (Core) and `OrderBookStore`

A level 2 feed can update 20 times a second. Redrawing that often wastes battery and is
unreadable. `OrderBookStore` keeps the full book up to date and publishes a trimmed copy to
SwiftUI a few times a second.

**Files**
- New `Sources/CandleKitCore/Market/PublishThrottle.swift`
- New `Tests/CandleKitCoreTests/PublishThrottleTests.swift`
- New `Sources/CandleKit/Market/OrderBookStore.swift` (inside `#if os(iOS)`)

**Core API**

```swift
import Foundation

/// Decides when a fast-changing value may be published again. Pure: the caller supplies the time.
public struct PublishThrottle: Sendable, Equatable {
    /// Minimum seconds between two publishes. Negative or non-finite values are treated as 0.
    public let interval: TimeInterval
    public private(set) var lastPublish: TimeInterval?
    public init(interval: TimeInterval)
    /// `0` when a publish is allowed at `now`; otherwise the seconds still to wait.
    public func delay(at now: TimeInterval) -> TimeInterval
    /// Records a publish at `now`.
    public mutating func markPublished(at now: TimeInterval)
}
```

`delay(at:)`: `0` if never published; otherwise `max(0, interval - (now - lastPublish))`. If `now`
is earlier than `lastPublish` (a clock that went backwards) return `0`.

**Tests** (`@Suite("Publish throttle")`)

| Test | Expect |
| --- | --- |
| `firstPublishIsImmediate` | `PublishThrottle(interval: 0.2).delay(at: 1000) == 0` |
| `waitsOutTheInterval` | after `markPublished(at: 10)`: `delay(at: 10.05)` ≈ 0.15; `delay(at: 10.2) == 0`; `delay(at: 11) == 0` |
| `clockGoingBackwards` | after `markPublished(at: 10)`: `delay(at: 9) == 0` |
| `badIntervals` | `PublishThrottle(interval: -1).interval == 0`; `.nan` → 0 |

**Store API** (`Sources/CandleKit/Market/OrderBookStore.swift`)

```swift
#if os(iOS)
import Observation
import SwiftUI

/// Holds a live order book and republishes it to SwiftUI at a steady, readable rate.
///
/// ```swift
/// @State private var store = OrderBookStore()
/// store.reset(bids: snapshot.bids, asks: snapshot.asks)   // on connect
/// store.apply(updates)                                    // on every feed message
/// OrderBookView(store.book)
/// ```
@MainActor
@Observable
public final class OrderBookStore {
    /// The book as last published: at most `depth` levels per side, refreshed at most once per
    /// `publishInterval`. Views read this.
    public private(set) var book = OrderBook()

    /// - Parameters:
    ///   - publishInterval: minimum seconds between two published books. 0.2 (five a second) by default.
    ///   - depth: levels kept per side in the published book. The full book is still tracked.
    public init(publishInterval: TimeInterval = 0.2, depth: Int = 200)

    /// Replaces the book with a fresh snapshot and publishes it straight away.
    public func reset(bids: [OrderBookLevel], asks: [OrderBookLevel])
    /// Applies feed updates. Publishing is delayed if the last publish was too recent.
    public func apply(_ updates: [OrderBookUpdate])
    /// Empties the book, for example when the symbol changes.
    public func clear()
}
#endif
```

**Store behaviour**
- Private, `@ObservationIgnored`: `var full = OrderBook()`, `var throttle: PublishThrottle`,
  `var pending: Task<Void, Never>?`, `let depth: Int`.
- Time source: `ProcessInfo.processInfo.systemUptime`.
- `apply`: `full.apply(updates)`; then `let wait = throttle.delay(at: now)`. If `wait == 0`,
  publish now (`book = full.trimmed(depth: depth)`, `throttle.markPublished(at: now)`). Otherwise,
  if `pending == nil`, start **one** task:
  `pending = Task { [weak self] in try? await Task.sleep(for: .seconds(wait)); guard !Task.isCancelled else { return }; self?.publishNow() }`.
  `publishNow()` sets `pending = nil` and publishes.
- `reset` and `clear`: cancel `pending`, set it to `nil`, update `full`, publish immediately.
- No `deinit` work is needed (the task holds `self` weakly).

**Verify:** `swift test`, then the `xcodebuild … -scheme CandleKit` command.
**Not verifiable here:** that a live feed publishes about five times a second (checked in 12.13).
**Commit:** `12.6: Publish throttle and OrderBookStore`

---

### 12.7 `OrderBookView` (the ladder) and `MarketDataStyle`

**Files** (each inside `#if os(iOS)` … `#endif`)
- New `Sources/CandleKit/Market/MarketDataStyle.swift`
- New `Sources/CandleKit/Market/OrderBookView.swift`

**`MarketDataStyle`**

```swift
/// Colors and number formatting shared by the order book, depth chart and time-and-sales views.
public struct MarketDataStyle: Sendable {
    /// Bids and buys.
    public var bidColor: Color
    /// Asks and sells.
    public var askColor: Color
    /// Opacity of the size bars drawn behind ladder rows.
    public var depthBarOpacity: Double
    /// Decimal places for prices. `nil` picks a value from the price, like the chart does.
    public var priceFractionDigits: Int?
    /// Decimal places for sizes.
    public var sizeFractionDigits: Int
    /// Height of one ladder or tape row, in points, before Dynamic Type scaling.
    public var rowHeight: CGFloat

    public init(
        bidColor: Color = CandleChartStyle.standard.upColor,
        askColor: Color = CandleChartStyle.standard.downColor,
        depthBarOpacity: Double = 0.18,
        priceFractionDigits: Int? = nil,
        sizeFractionDigits: Int = 4,
        rowHeight: CGFloat = 22
    )

    /// The default look.
    public static let standard = MarketDataStyle()
}
```

Add an internal helper in the same file, used by all three views:

```swift
extension MarketDataStyle {
    func priceText(_ price: Double) -> String {
        ChartFormat.price(price, digits: priceFractionDigits ?? PriceScale.suggestedFractionDigits(forPrice: price))
    }
    func sizeText(_ size: Double) -> String {
        ChartFormat.price(size, digits: sizeFractionDigits)
    }
}
```

(`ChartFormat` is internal, in `Sources/CandleKit/ChartFrame.swift`.
`PriceScale.suggestedFractionDigits(forPrice:)` is public in Core. `CandleChartStyle.standard` is a
computed `static var` in `Sources/CandleKit/Configuration.swift`.)

**`OrderBookView` public API**

```swift
/// A level 2 order book ladder: asks above, the spread in the middle, bids below.
///
/// ```swift
/// OrderBookView(book)
///     .rowsPerSide(10)
///     .priceGrouping(0.5)
///     .onSelectPrice { price in orderPrice = price }
/// ```
///
/// Each row shows price, size and the running total, with a bar whose length is the running total
/// relative to the deepest row shown. Rows are a fixed count, so a very deep book costs no more
/// to draw than a shallow one.
public struct OrderBookView: View {
    public init(_ book: OrderBook)
    public var body: some View

    /// Rows shown on each side. Default 10. Values below 1 are treated as 1.
    public func rowsPerSide(_ count: Int) -> OrderBookView
    /// Merges prices into buckets this wide. `nil` (the default) shows every level.
    public func priceGrouping(_ tick: Double?) -> OrderBookView
    public func marketDataStyle(_ style: MarketDataStyle) -> OrderBookView
    /// Hides the column headers ("Price", "Size", "Total"). Shown by default.
    public func headerVisible(_ visible: Bool) -> OrderBookView
    /// Called with a row's price when the person taps it, for example to prefill an order ticket.
    public func onSelectPrice(_ action: @escaping (Double) -> Void) -> OrderBookView
}
```

Modifiers follow the existing pattern in `CandlestickChart` (`var copy = self; copy.x = …; return copy`).

**Layout** (keep `body` small; make each numbered piece its own `private var` or private `View`)
1. `let ladder = OrderBookLadder(book: book, rowsPerSide: rows, tick: tick)` once at the top of `body`.
2. Header row (if visible): three `Text`s, `.font(.caption2)`, `.foregroundStyle(.secondary)`.
3. Ask rows: `ForEach(ladder.asks.reversed())` so the **best ask is nearest the spread**.
4. Spread row: `"Spread  0.50  (4.99 bps)"` from `book.spread` and `book.spreadBasisPoints`, and
   the mid price; show `"—"` when they are `nil`. If `book.isCrossed`, show the text in
   `.orange` with the label "Crossed".
5. Bid rows: `ForEach(ladder.bids)`.
6. One private `OrderBookRow` view used by both sides: an `HStack` of price (colored bid/ask),
   size and total (`.monospacedDigit()`, `.font(.caption)`), fixed height from a
   `@ScaledMetric(relativeTo: .caption) var rowHeight` seeded from `style.rowHeight`, with
   `.background(alignment: .trailing)` holding a `Rectangle` filled with the side color at
   `style.depthBarOpacity`, scaled with
   `.scaleEffect(x: row.depthFraction, y: 1, anchor: .trailing)`.
7. If `onSelectPrice` is set, wrap the row in a `Button` with `.buttonStyle(.plain)`; otherwise no
   button.
8. When the book is empty show `ContentUnavailableView("No order book", systemImage: "list.bullet.rectangle")`.

**Accessibility:** each row is one element:
`.accessibilityElement(children: .ignore)` and
`.accessibilityLabel("Ask 100.50, size 1.0000, total 1.0000")` (or "Bid …"). Cap Dynamic Type
with `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` on the whole view, like the chart.

**Do not** use `List` (row insets and separators fight the fixed layout), animate row changes, or
create a formatter inside a row.

Add a preview at the bottom of the file:

```swift
#Preview {
    OrderBookView(MarketSampleData.orderBook())
        .rowsPerSide(8)
        .padding()
}
```

**Verify:** `swift test`; `xcodebuild … -scheme CandleKit`.
**Not verifiable here (list in the report):** light and dark mode, bars grow from the right, best
ask sits directly above the spread, tapping a row calls back, VoiceOver reads a row, large
Dynamic Type does not clip.
**Commit:** `12.7: OrderBookView ladder and MarketDataStyle`

---

### 12.8 `DepthChartView`

**File:** new `Sources/CandleKit/Market/DepthChartView.swift` (inside `#if os(iOS)`).

**Public API**

```swift
/// A depth chart: cumulative bid size falling away to the left of the mid price and cumulative
/// ask size to the right, drawn as two filled steps.
///
/// ```swift
/// DepthChartView(book).depthWindow(0.02).frame(height: 180)
/// ```
public struct DepthChartView: View {
    public init(_ book: OrderBook)
    public var body: some View
    /// How far either side of the mid price to show, as a share of it. Default 0.02 (±2%).
    public func depthWindow(_ window: Double) -> DepthChartView
    public func marketDataStyle(_ style: MarketDataStyle) -> DepthChartView
}
```

**Drawing** (one `Canvas`, no child views per level)
1. `guard let curve = DepthCurve(book: book, window: window)` else show
   `ContentUnavailableView("No depth", systemImage: "chart.xyaxis.line")`.
2. Inside `Canvas { context, size in … }` leave 16 pt at the bottom for labels:
   `plotHeight = size.height - 16`.
3. Mapping: `x(price) = (price - range.lowerBound) / (range.upperBound - range.lowerBound) * size.width`
   (if the range has no width, draw nothing); `y(total) = plotHeight * (1 - total / curve.maxCumulativeSize)`.
4. Bid path, as steps: start at `(x(mid), plotHeight)`; for each bid level in order (best first):
   horizontal line to `x(level.price)` at the **previous** total's height, then vertical to
   `y(level.cumulativeSize)`. After the last level, line to the left edge `x = 0` at the same
   height, then down to `(0, plotHeight)` and close. Fill with `style.bidColor.opacity(0.25)`,
   stroke the top edge with `style.bidColor`, line width 1.5.
5. Ask path: mirror image to the right, ending at `x = size.width`, with `style.askColor`.
6. A 1 pt vertical line at `x(mid)` in `Color.secondary.opacity(0.5)`.
7. Three labels using `context.draw(Text(…).font(.caption2).foregroundStyle(.secondary), at:anchor:)`:
   lowest price at bottom-left (anchor `.bottomLeading`), mid price at bottom-centre, highest price
   at bottom-right. Format with `style.priceText`.

**Accessibility:** the whole view is one element with
`.accessibilityLabel("Depth chart")` and
`.accessibilityValue("Bids \(total bid size) down to \(lowest price), asks \(total ask size) up to \(highest price)")`.

Add a `#Preview` with `MarketSampleData.orderBook()` and `.frame(height: 180)`.

**Verify:** `swift test`; `xcodebuild … -scheme CandleKit`.
**Not verifiable here:** the two steps meet at the mid line without a gap, fills don't overlap,
labels don't clip in a narrow width, dark mode.
**Commit:** `12.8: DepthChartView`

---

### 12.9 `TimeAndSalesView`

**File:** new `Sources/CandleKit/Market/TimeAndSalesView.swift` (inside `#if os(iOS)`).

**Public API**

```swift
/// A time-and-sales tape: the latest trades, newest at the top, colored by who was the aggressor.
///
/// ```swift
/// TimeAndSalesView(tape.trades).largeTradeSize(5)
/// ```
///
/// Pass trades oldest first (the order `TradeTape.trades` uses). Only the newest `maximumRows`
/// are drawn.
public struct TimeAndSalesView: View {
    public init(_ trades: [MarketTrade])
    public var body: some View
    /// Rows drawn. Default 50. Values below 1 are treated as 1.
    public func maximumRows(_ count: Int) -> TimeAndSalesView
    /// Hides trades smaller than this. Default 0 (show everything).
    public func minimumSize(_ size: Double) -> TimeAndSalesView
    /// Trades at least this large get a highlighted row. `nil` (default) highlights nothing.
    public func largeTradeSize(_ size: Double?) -> TimeAndSalesView
    public func marketDataStyle(_ style: MarketDataStyle) -> TimeAndSalesView
    /// Hides the column headers ("Time", "Price", "Size"). Shown by default.
    public func headerVisible(_ visible: Bool) -> TimeAndSalesView
}
```

**Layout**
1. At the top of `body`: `let rows = trades.reversed().lazy.filter { $0.size >= minimumSize }.prefix(maximumRows)`
   then `Array(rows)`. This touches at most the rows drawn plus the ones filtered out.
2. A `ScrollView` containing a `LazyVStack(spacing: 0)` with `ForEach(rows)` (`MarketTrade` is
   `Identifiable`).
3. Private `TradeRow` view: `HStack` of time, price, size; `.font(.caption).monospacedDigit()`;
   price colored `bidColor` for `.buy`, `askColor` for `.sell`, `.primary` for `.unknown`; fixed
   height as in 12.7.
4. Time text: `trade.time.formatted(date: .omitted, time: .standard)`.
5. Large trade: row background is the side color at opacity 0.15 and the size text is
   `.fontWeight(.semibold)`.
6. Empty: `ContentUnavailableView("No trades yet", systemImage: "clock")`.

**Accessibility:** each row one element, label `"Buy 0.2000 at 100.50, 9:41:07 AM"` (use "Sell"
or "Trade" for the other sides).

Add a `#Preview` with `MarketSampleData.trades(count: 60)` and `.largeTradeSize(1.8)`.

**Do not** animate insertions (a busy tape would never stop moving) or auto-scroll.

**Verify:** `swift test`; `xcodebuild … -scheme CandleKit`.
**Not verifiable here:** newest row is at the top, colors, large-trade highlight, smoothness with
a fast feed (checked in 12.13).
**Commit:** `12.9: TimeAndSalesView`

---

### 12.10 Chart overlay: bid and ask lines (`.quoteLines`)

**Files**
- New `Sources/CandleKit/Market/QuoteLinesLayer.swift` (inside `#if os(iOS)`)
- Edit `Sources/CandleKit/CandlestickChart.swift`

**Model this on `Sources/CandleKit/VolumeProfileLayer.swift`.** Read that file first. The layer:

```swift
/// Dashed lines across the plot at the current best bid and best ask.
struct QuoteLinesLayer: View {
    let state: CandleChartState
    let bid: Double?
    let ask: Double?
    let style: MarketDataStyle

    var body: some View {
        let _ = state.revision
        if let frame = state.currentFrame {
            Canvas { context, _ in
                var clipped = context
                clipped.clip(to: Path(frame.layout.plot))
                // for each of bid (style.bidColor) and ask (style.askColor), if non-nil and finite:
                //   y = frame.y(forPrice: price); skip if outside plot.minY...plot.maxY
                //   stroke a line from plot.minX to plot.maxX, lineWidth 1, dash [2, 3], color.opacity(0.8)
            }
            .allowsHitTesting(false)
        }
    }
}
```

**Edits to `CandlestickChart.swift`** (three small additions; change nothing else)
1. With the other private stored properties (after `private var eventSelectionHandler …`), add:
   ```swift
   private var quoteBid: Double?
   private var quoteAsk: Double?
   private var marketStyle = MarketDataStyle.standard
   ```
2. In the `ZStack`, directly **after** the `if let volumeProfileStyle { … }` block, add:
   ```swift
   if quoteBid != nil || quoteAsk != nil {
       QuoteLinesLayer(state: state, bid: quoteBid, ask: quoteAsk, style: marketStyle)
   }
   ```
3. In the `// MARK: - Modifiers` extension add:
   ```swift
   /// Draws dashed lines at the best bid and best ask, so the spread is visible against the
   /// candles. Pass `nil` for either to hide it. Lines outside the visible price range aren't drawn.
   public func quoteLines(bid: Double?, ask: Double?) -> CandlestickChart

   /// Colors for the market-data overlays (`quoteLines`, `depthOverlay`, `orderLines`).
   public func marketDataStyle(_ style: MarketDataStyle) -> CandlestickChart
   ```

**Stop condition:** if the `CandlestickChart.body` stops type-checking after step 2, move the
`ZStack`'s overlay layers you added into a small private `@ViewBuilder` function taking `state`,
and report it as a deviation. Do not restructure anything else.

**Verify:** `swift test`; `xcodebuild … -scheme CandleKit`; Demo build.
**Not verifiable here:** lines track the price scale while panning and zooming, and disappear
when the quote is off screen.
**Commit:** `12.10: Bid and ask lines on the chart`

---

### 12.11 Chart overlay: depth on the price axis (`.depthOverlay`, roadmap 9.10)

Horizontal bars along the **left** edge of the plot showing book size at each price, lined up
with the chart's own price scale. (The right edge is where the volume profile draws.)

**Files**
- New `Sources/CandleKit/Market/DepthOverlayLayer.swift` (inside `#if os(iOS)`)
- Edit `Sources/CandleKit/CandlestickChart.swift`

**Layer**
- Inputs: `state`, `book: OrderBook`, `style: MarketDataStyle`, `maximumWidthShare: Double`.
- `let _ = state.revision`; needs `state.currentFrame` and `state.currentPriceRange`.
- `bucketCount = max(1, Int(plot.height / 4))` (bars about 4 pt tall).
- `let buckets = OrderBookMath.buckets(of: book, priceRange: priceRange, bucketCount: bucketCount)`.
- `maxSize = max(buckets.bids.max() ?? 0, buckets.asks.max() ?? 0)`; draw nothing if 0.
- For bucket `i` with size `> 0`: its price span is
  `low + Double(i) * height ... low + Double(i + 1) * height`; convert both ends with
  `frame.y(forPrice:)`; rect from `plot.minX`, width `plot.width * maximumWidthShare * size / maxSize`.
  Batch all bid rects into one `Path` and all ask rects into another; fill each once
  (`style.bidColor.opacity(0.3)`, `style.askColor.opacity(0.3)`). Two fills total, no per-bar draw.
- Clip to the plot. `.allowsHitTesting(false)`.

**Edits to `CandlestickChart.swift`**
1. Stored properties: `private var depthBook: OrderBook?` and
   `private var depthOverlayWidthShare = 0.25`.
2. In the `ZStack`, after the quote-lines block from 12.10:
   ```swift
   if let depthBook, !depthBook.isEmpty {
       DepthOverlayLayer(state: state, book: depthBook, style: marketStyle, maximumWidthShare: depthOverlayWidthShare)
   }
   ```
3. Modifier:
   ```swift
   /// Draws the order book as horizontal bars along the left edge of the plot, lined up with the
   /// price axis, so resting size ("walls") can be read against the candles. Only levels inside
   /// the visible price range are drawn. Pass `nil` to hide it.
   ///
   /// - Parameter maximumWidthShare: the longest bar as a share of the plot width (0.05...0.6).
   public func depthOverlay(_ book: OrderBook?, maximumWidthShare: Double = 0.25) -> CandlestickChart
   ```
   Clamp `maximumWidthShare` to `0.05...0.6`.

Cost per redraw is O(book levels) for the bucketing. Pass a trimmed book (`OrderBookStore.book`
is already trimmed to 200 per side). Say so in the modifier's doc comment.

**Verify:** `swift test`; `xcodebuild … -scheme CandleKit`; Demo build.
**Not verifiable here:** bars line up with the price axis labels, move with a manual price-axis
drag, and don't hitch while panning.
**Commit:** `12.11: Order book depth overlay on the chart (9.10)`

---

### 12.12 Chart overlay: order and position lines (`.orderLines`, roadmap 9.7)

Shows the app's open orders and position as labelled horizontal lines. A line marked draggable
can be dragged by its tag; the chart reports the new price and the **app** decides what to do.
CandleKit never places or changes an order.

**Files**
- New `Sources/CandleKitCore/Market/ChartOrderLine.swift` + tests in
  `Tests/CandleKitCoreTests/ChartOrderLineTests.swift`
- New `Sources/CandleKit/Market/OrderLinesLayer.swift` (inside `#if os(iOS)`)
- Edit `Sources/CandleKit/CandlestickChart.swift`

**Core API**

```swift
import Foundation

/// A horizontal line the app wants on the chart for one of its orders or its position.
public struct ChartOrderLine: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        case buy, sell, position, stopLoss, takeProfit
    }
    /// The app's own identifier (an order id), returned in the move callback.
    public var id: String
    public var price: Double
    public var kind: Kind
    /// Short text for the tag, e.g. "Buy 0.5" or "Stop". The price is appended by the chart.
    public var label: String
    /// Whether the person may drag this line. Default `false`.
    public var isDraggable: Bool
    public init(id: String, price: Double, kind: Kind, label: String, isDraggable: Bool = false)
}

/// Pure helpers for dragging an order line.
public enum OrderLineMath {
    /// Rounds `price` to the nearest multiple of `tick`. A `tick` that is `nil`, not finite or
    /// `<= 0` returns `price` unchanged.
    public static func snapped(_ price: Double, tick: Double?) -> Double
    /// Signed distance from `reference` to `price` as a share of `reference` (0.01 = +1%).
    /// `nil` when `reference` is 0 or either value is not finite.
    public static func percentDistance(of price: Double, from reference: Double) -> Double?
}
```

`snapped`: `(price / tick).rounded() * tick`.

**Tests** (`@Suite("Order lines")`)

| Test | Expect |
| --- | --- |
| `snapsToTick` | `snapped(100.26, tick: 0.5)` ≈ 100.5; `snapped(100.24, tick: 0.5)` ≈ 100.0; `snapped(0.1234, tick: 0.01)` ≈ 0.12 |
| `snapBadTick` | tick `nil`, `0`, `-1`, `.nan` each return 100.26 exactly |
| `percentDistance` | `(of: 101, from: 100)` ≈ 0.01; `(of: 95, from: 100)` ≈ −0.05; `from: 0` → `nil`; `.nan` → `nil` |

**Layer** (`OrderLinesLayer`)
- Inputs: `state`, `lines: [ChartOrderLine]`, `style: MarketDataStyle`, `tick: Double?`,
  `onMove: ((String, Double) -> Void)?`.
- `@State private var drag: (id: String, price: Double)?` — the line being dragged and its live price.
- `let _ = state.revision`; needs `state.currentFrame`.
- Draw the lines in one `Canvas` (`.allowsHitTesting(false)`): for each line use the live drag
  price if it is the one being dragged; `y = frame.y(forPrice:)`; skip if outside the plot;
  stroke `plot.minX ... plot.maxX`, width 1, dash `[6, 3]` for orders and solid for `.position`.
  Colors: `.buy` and `.takeProfit` → `style.bidColor`; `.sell` and `.stopLoss` → `style.askColor`;
  `.position` → `Color.accentColor`.
- Over the canvas, one small tag per on-screen line (these are real views, like the buttons in
  `EventMarkersLayer`): `Text("\(line.label)  \(style.priceText(price))")`, `.font(.caption2.weight(.semibold))`,
  white text on the line's color in a `Capsule`, positioned with `.position(x: plot.maxX - 60, y: y)`.
- If `line.isDraggable` and `onMove != nil`, add to the tag:
  ```swift
  .gesture(
      DragGesture(minimumDistance: 1)
          .onChanged { value in
              let raw = frame.price(atY: y + value.translation.height)
              drag = (line.id, OrderLineMath.snapped(raw, tick: tick))
          }
          .onEnded { _ in
              if let drag { onMove?(drag.id, drag.price) }
              drag = nil
          }
  )
  ```
  where `y` is the line's **resting** position (from `line.price`, not the drag price).
  `frame.price(atY:)` and `frame.y(forPrice:)` are both in `Sources/CandleKit/ChartFrame.swift`.
- Non-draggable tags get `.allowsHitTesting(false)` so they never block panning.
- Accessibility: each tag `.accessibilityLabel("Buy 0.5 at 100.50")`; a draggable one also gets
  `.accessibilityAdjustableAction` that moves the price by one `tick` (or by 0.1% of the price
  when `tick` is `nil`) and calls `onMove`.

**Edits to `CandlestickChart.swift`**
1. Stored: `private var orderLines: [ChartOrderLine] = []`, `private var orderLineTick: Double?`,
   `private var orderLineMoveHandler: ((String, Double) -> Void)?`.
2. In the `ZStack`, directly **after** the `if !chartEvents.isEmpty { EventMarkersLayer… }` block
   and **before** `PriceAxisScaleGesture(state: state)`:
   ```swift
   if !orderLines.isEmpty {
       OrderLinesLayer(state: state, lines: orderLines, style: marketStyle, tick: orderLineTick, onMove: orderLineMoveHandler)
   }
   ```
   It must come after `ChartGestureView` so its tags receive touches first.
3. Modifier:
   ```swift
   /// Draws the app's orders and position as labelled horizontal lines. A line whose
   /// `isDraggable` is `true` can be dragged by its tag; when the drag ends, `onMove` receives the
   /// line's id and the new price, and the app decides what to do with it. The chart never places
   /// or changes an order, and the line returns to `price` until the app updates the array.
   ///
   /// - Parameters:
   ///   - tick: rounds a dragged price to this increment (the instrument's tick size).
   public func orderLines(
       _ lines: [ChartOrderLine], tick: Double? = nil, onMove: ((String, Double) -> Void)? = nil
   ) -> CandlestickChart
   ```

**Verify:** `swift test`; `xcodebuild … -scheme CandleKit`; Demo build.
**Not verifiable here:** dragging a tag moves only that line; panning the chart elsewhere still
works; a non-draggable tag doesn't block panning; the callback fires once on release; VoiceOver.
**Commit:** `12.12: Order and position lines on the chart (9.7)`

---

### 12.13 Demo: "Order flow" tab

**Files** (all new unless stated; run `xcodegen generate` in `Demo/` afterwards)
- `Demo/CandleKitDemo/OrderFlow/OrderFlowFeed.swift`
- `Demo/CandleKitDemo/OrderFlow/SimulatedOrderFlow.swift`
- `Demo/CandleKitDemo/OrderFlow/CoinbaseOrderFlow.swift`
- `Demo/CandleKitDemo/OrderFlow/OrderFlowView.swift`
- Edit `Demo/CandleKitDemo/App/CandleKitDemoApp.swift`: add a fifth tab **after** Performance:
  `OrderFlowView().tabItem { Label("Order flow", systemImage: "list.bullet.rectangle") }.tag(4)`.
  Change nothing else in that file.

**Rules:** public CandleKit API only; works offline with the simulated source; no API keys.
Do **not** edit `MarketView.swift`.

**`OrderFlowFeed`** — `@MainActor @Observable final class`
- `let store = OrderBookStore()`, `private(set) var tape = TradeTape(capacity: 200)`,
  `private(set) var status: String` ("Simulated", "Connecting…", "Live", "Disconnected").
- `func run(live: Bool, productID: String) async` — called from `.task(id:)`. Clears the store
  and tape, then consumes an `AsyncStream<OrderFlowEvent>` until cancelled.
- `enum OrderFlowEvent: Sendable { case snapshot(bids: [OrderBookLevel], asks: [OrderBookLevel]); case updates([OrderBookUpdate]); case trade(MarketTrade) }`
- Tape throttling: append every trade to a private `@ObservationIgnored` buffer and copy it into
  the observed `tape` at most 5 times a second (reuse `PublishThrottle`), so a burst of trades is
  one redraw.

**`SimulatedOrderFlow`** — `struct`, `static func events(seed: UInt64) -> AsyncStream<OrderFlowEvent>`
- First event: a snapshot from `MarketSampleData.orderBook(midPrice: 100, levels: 40, tick: 0.05, seed: seed)`.
- Then every 200 ms (`Task.sleep`): 4 random updates near the mid (pick a level index 0..<40 and a
  side, set a new size 0.2…3.0, occasionally 0 to remove it) and one trade at the best bid or ask
  price with a random size, id `"sim-\(counter)"`. Use `SystemRandomNumberGenerator`.
- Stop cleanly when the consuming task is cancelled (`continuation.onTermination` cancels the
  producing task).

**`CoinbaseOrderFlow`** — `struct`, `static func events(productID: String) -> AsyncStream<OrderFlowEvent>`
- Connect to `wss://ws-feed.exchange.coinbase.com` with `URLSessionWebSocketTask`. Within 5
  seconds send:
  `{"type":"subscribe","product_ids":["BTC-USD"],"channels":["level2_batch","matches"]}`
  (`level2_batch` is the public book channel; plain `level2` needs authentication).
- Messages (all numbers arrive as **strings**; parse with `Double(_:)` and skip what fails):
  - `{"type":"snapshot","bids":[["price","size"],…],"asks":[[…]]}` → `.snapshot`
  - `{"type":"l2update","changes":[["buy"|"sell","price","size"],…]}` → `.updates`
    (`"buy"` → `.bid`, `"sell"` → `.ask`; size `"0"` removes the level, which `OrderBook` handles)
  - `{"type":"match"|"last_match","trade_id":123,"time":"2026-…Z","price":"…","size":"…","side":"buy"|"sell"}`
    → `.trade`. **Coinbase's `side` is the maker's side.** The aggressor is the opposite:
    `"sell"` → `MarketTrade.Side.buy`, `"buy"` → `.sell`. Id is `String(trade_id)`. Parse `time`
    with `ISO8601DateFormatter` with `.withFractionalSeconds`; fall back to `Date()`.
  - Ignore every other `type`.
- Decode with `JSONSerialization` into `[String: Any]` (the shapes differ per type). Keep parsing
  in one `static func event(from text: String) -> OrderFlowEvent?` so it is easy to read.
- On any error or close, finish the stream. `OrderFlowFeed` shows "Disconnected"; no automatic
  reconnect in this step.

**`OrderFlowView`**
- State: `@State private var feed = OrderFlowFeed()`, `@State private var live = false`,
  `@State private var grouping: Double? = nil`, `@State private var selectedPrice: Double?`.
- `.task(id: live) { await feed.run(live: live, productID: "BTC-USD") }`
- A `ScrollView` with these sections, **each its own small `private var`** to keep `body` short:
  1. Header: status text, a `Toggle("Live (Coinbase BTC-USD)", isOn: $live)`, and the imbalance
     as text: `OrderBookMath.imbalance(of: feed.store.book, depth: 10)` formatted as a percent.
  2. `DepthChartView(feed.store.book).frame(height: 160)`
  3. A `Picker` for grouping (None / 0.5 / 1 / 5 / 10 when live; None / 0.1 / 0.5 when
     simulated) and `OrderBookView(feed.store.book).rowsPerSide(10).priceGrouping(grouping).onSelectPrice { selectedPrice = $0 }`,
     with a line of text under it showing the selected price.
  4. `TimeAndSalesView(feed.tape.trades).maximumRows(30).largeTradeSize(live ? 0.5 : 2.5).frame(height: 320)`
  5. A small `CandlestickChart(CandleSampleData.randomWalk(count: 200, startPrice: 100))` with
     `.quoteLines(bid:ask:)`, `.depthOverlay(feed.store.book)` and two sample `.orderLines`
     (one draggable "Buy 1" and one "Stop") held in `@State`, updating the array in `onMove`,
     `.frame(height: 280)`. Show this section only when **not** live (the sample candles sit near
     100, which matches the simulated book, not a live BTC price).

**Verify:** `swift test`; both `xcodebuild` builds; then run in the Simulator and check, listing
each result in the report:
- Simulated: ladder, depth chart and tape update about five times a second and stay readable.
- Tapping a ladder row shows the price. Grouping changes the rows.
- Live toggle: status goes Connecting → Live, the book fills, trades appear; toggling back
  returns to simulated without a crash.
- The chart section: quote lines sit at the spread, depth bars on the left, the "Buy 1" tag
  drags and stays where released, panning the chart still works.
- No purple runtime warnings in Xcode.

**Commit:** `12.13: Demo Order flow tab`

---

### 12.14 Documentation

One commit, no code changes.

1. `README.md`: after the existing trader-tools sections add **"Order book, depth and tape"** and
   **"Market overlays on the chart"**, each a short paragraph and the matching snippet from
   section 4 of this plan. State once: "CandleKit displays the data you give it. It does not
   connect to an exchange or place orders."
2. New `website/docs/guides/market-data.md` with the same content in more detail: the data
   conventions from section 3 (sort order, size is a total, aggressor side), the Coinbase side
   flip as a worked example, and the throttling advice. Add it to `website/sidebars.js` next to
   `trader-tools`.
3. `CHANGELOG.md`, under "## Unreleased": an "Added: market data tools" list, one line per step.
4. `docs/ROADMAP.md`: tick 12.1–12.14, set 9.7 and 9.10 to `[~]` with "see phase 12", and under
   each list what still needs a device check (copied from your step reports).
5. No screenshots or GIFs in this step (they need a maintainer-run Simulator capture).

**Verify:** `swift test` and both builds still pass (nothing should have changed).
**Commit:** `12.14: Document market data tools`

---

## 7. Deferred tools (roadmap only) and why

| Tool | Why not now |
| --- | --- |
| **Volume delta and CVD pane** | `TradeAggregation` (12.4) already computes the numbers. Drawing them in a chart pane needs an indicator whose input is more than candles; the `Indicator` protocol and `IndicatorCache` key only on candles and parameters. Needs a design note first. |
| **Footprint (cluster) candles** | Bid×ask volume per price inside each candle. Needs trade history per candle, a readable zoom level and a new renderer. Large. |
| **Liquidity heatmap** | Book history over time behind the candles. Needs the app to record book snapshots, a storage format and a texture renderer; per-frame cost needs a trace. |
| **Large-trade bubbles on the chart** | Small once CVD's data path exists; shares the "trades as chart input" design. |
| **Imbalance history, spread history** | Indicators over book data; same input problem as CVD. |
| **Options chain, screener heatmap, watchlist** | Not chart-adjacent; a separate product if ever. |

---

## 8. Reference: how the expected values were produced

All numbers in the test tables come from a Python script written from the behaviour descriptions
in this plan, not from any Swift code. The book and trade fixtures are the ones in sections 5 and
12.3. If a value looks wrong, recompute it by hand from the fixture before changing anything.
