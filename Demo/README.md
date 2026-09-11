# CandleKit Demo

An iOS app that shows what CandleKit can do, using real market data and ordinary app code. The demo lives inside the CandleKit repository and always builds against the local package source.

## What's inside

**Market** streams live Bitcoin, Ether or Solana prices from Coinbase and builds candles from individual trades as they arrive. Scroll back and older candles load in automatically. Switch timeframes from 1 minute to 1 day, toggle moving averages and volume, or switch to simulated data to work offline.

**Styles** shows each built-in style next to the code that produces it: standard, red-up, color-blind safe, hollow candles, custom brand colors, and a compact layout for cards.

**In a page** puts a chart inside a scrolling detail screen, showing that horizontal drags move the chart while vertical drags still scroll the page.

**Performance** loads 1,000, 10,000 or 100,000 candles with two indicators, and shows a refresh-rate meter while you fling and pinch.

## Running it

You need Xcode 16 or later and an iOS 17 simulator or device.

From the `Demo/` directory:

```sh
brew install xcodegen   # if not already installed
xcodegen generate
open CandleKitDemo.xcodeproj
```

`CandleKitDemo.xcodeproj` is gitignored. Always edit `project.yml` and regenerate instead of editing the project directly.

To run on a device, set your team under **Signing & Capabilities**.

## Market data

Live prices come from the public [Coinbase Exchange API](https://docs.cdp.coinbase.com/api-reference/exchange-api/rest-api/products/get-product-candles): the REST candles endpoint for history and the WebSocket `ticker` channel for trades. No account or API key is needed. This project isn't affiliated with Coinbase, and the data is shown for demonstration only. Candles missed while the connection is down aren't backfilled.

## Project layout

```
Demo/
├── project.yml         XcodeGen spec — source of truth for the Xcode project
├── Support/            Info.plist and other non-Swift resources
└── CandleKitDemo/
    ├── App/            App entry point and tab bar
    ├── Data/           Coinbase and simulated data sources, shared models
    ├── Market/         Live chart screen and the feed that builds candles from trades
    ├── Styles/         Style gallery
    ├── Detail/         Chart inside a scrolling page
    └── Performance/    Large datasets and the refresh-rate meter
```
