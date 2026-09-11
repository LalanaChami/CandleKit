---
paths:
  - "Demo/**"
---

# Demo app

- The demo is sample code people will copy. Prefer clear, conventional SwiftUI over clever abstractions.
- Use only CandleKit's public API. No `@testable import` and no internal symbols. If something is missing, record the API gap in `docs/ROADMAP.md`.
- `Demo/project.yml` is the source of truth. After editing it, run `xcodegen generate` from `Demo/`. `CandleKitDemo.xcodeproj` is gitignored.
- The package reference must be `path: ..` so the demo builds against the working tree.
- Swift 6 language mode. `MarketFeed` is `@MainActor`. Data sources are `Sendable` structs.
- `MarketFeed.run(_:)` is driven by `.task(id:)`. The `generation` token stops a cancelled run from writing into a newer one. Keep that pattern when changing the feed.
- Every screen must work with the simulated source, offline, with no network.
- Coinbase Exchange public API, no keys:
  - Candles: `GET https://api.exchange.coinbase.com/products/{id}/candles?granularity=&start=&end=`. Granularity must be one of 60, 300, 900, 3600, 21600 or 86400. A request may cover at most 300 buckets (we use 290). Rows are `[time, low, high, open, close, volume]`. Sort the results yourself and dedupe them.
  - Trades: `wss://ws-feed.exchange.coinbase.com`, public `ticker` channel. Send a subscribe message within 5 seconds of connecting or the server disconnects.
- Candles missed while the WebSocket is disconnected are not backfilled (known issue KI-9).
