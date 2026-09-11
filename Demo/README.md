# CandleKit Demo

An iOS app that shows what [CandleKit](https://github.com/LalanaChami/CandleKit) can do, using real market data and ordinary app code.

## What's inside

**Market** streams live Bitcoin, Ether or Solana prices from Coinbase and builds candles from individual trades as they arrive. Scroll back and older candles load in automatically. Switch timeframes from 1 minute to 1 day, toggle moving averages and volume, or change to simulated data to work offline.

**Styles** shows each built-in style next to the code that produces it: standard, red-up, color-blind safe, hollow candles, custom brand colors, and a compact layout for cards.

**In a page** puts a chart inside a scrolling detail screen, to show that horizontal drags move the chart while vertical drags still scroll the page.

**Performance** loads 1,000, 10,000 or 100,000 candles with two indicators, and shows a refresh-rate meter while you fling and pinch.

## Running it

You need Xcode 16 or later and an iOS 17 simulator or device.

If the repository includes `CandleKitDemo.xcodeproj`, open it and run. Otherwise, generate the project first with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open CandleKitDemo.xcodeproj
```

To run on a device, choose your team under **Signing & Capabilities** and change the bundle identifier if Xcode asks.

The demo tracks CandleKit's `main` branch. To pick up the newest changes, choose **File › Packages › Update to Latest Package Versions** in Xcode.

## Working on CandleKit and the demo together

Clone both repositories side by side:

```
Developer/
├── CandleKit/
└── CandleKitDemo/
```

Then either drag the `CandleKit` folder into the demo's project navigator in Xcode, which overrides the remote package with your local copy, or change the package in `project.yml` to `path: ../CandleKit` and run `xcodegen generate` again. Edits to CandleKit then show up in the demo on the next build.

## Market data

Live prices come from the public [Coinbase Exchange API](https://docs.cdp.coinbase.com/api-reference/exchange-api/rest-api/products/get-product-candles): the REST candles endpoint for history and the WebSocket `ticker` channel for trades. No account or API key is needed. This project isn't affiliated with Coinbase, and the data is shown for demonstration only. Candles missed while the connection is down aren't backfilled.

## Project layout

```
CandleKitDemo/
├── App/            App entry point and tabs
├── Data/           Coinbase and simulated data sources
├── Market/         Live chart screen and the feed that builds candles from trades
├── Styles/         Style gallery
├── Detail/         Chart inside a scrolling page
└── Performance/    Large datasets and the refresh-rate meter
```

`project.yml` is the source of truth for the Xcode project. If you change settings, edit it and regenerate rather than editing the project in Xcode.

## License

MIT. See [LICENSE](LICENSE).
