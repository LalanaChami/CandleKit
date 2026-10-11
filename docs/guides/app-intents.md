# Siri, Shortcuts and Spotlight (roadmap 8.4)

CandleKit ships no `AppIntent` type, on purpose: intents must be declared in your app's own target
so the system can find them at install time, and what "show a chart" means (which symbols, which
screen) is your app's business. This guide is the pattern; `Demo/CandleKitDemo/Intents/ShowChartIntent.swift`
is a working sample.

## The pattern

1. **Make the parameters `AppEnum`s** (or `AppEntity` if your symbols come from a database). The
   sample has `AssetOption` and `TimeframeOption`, each mapping to the demo's own `Product` and
   `Timeframe`.
2. **Declare the intent** with `openAppWhenRun = true`. `perform()` does not touch UI. It writes a
   request into a small `@MainActor @Observable` router and returns.
3. **Apply the request in the view** with `.onChange(of: router.pendingChart, initial: true)`, then
   clear it. The chart you show is just a normal `CandlestickChart` driven by your own state.
4. **Add an `AppShortcutsProvider`** with phrases. Each phrase must contain `\(.applicationName)`;
   phrases that include an `AppEnum` parameter let people say "Show Ether chart in CandleKit".

## The cold-launch gotcha

If the app isn't running, the system launches it and runs `perform()` possibly before any SwiftUI
view exists. A design that finds the view and calls it will silently do nothing on cold launch while
working fine in testing with the app already open. Leave the request in shared state and let the view
read it when it appears (`initial: true`). The router also resets the selected tab, so the request
works from any screen.

## Trying it

- Run the Demo once so the system registers the shortcuts.
- Shortcuts app: search "CandleKit"; "Show chart" is listed with its Asset and Timeframe fields.
- Spotlight: type "Show Bitcoin chart".
- Siri: say the phrase. Test once with the app force-quit to cover the cold launch.

## Not covered

An intent that returns data without opening the app (for example a spoken price) needs a data path
that works without UI and is outside CandleKit's scope. Donating intents for "recently viewed"
suggestions is also left to the host app.

## Status

Sample code written without a compiler; build it and run it from Shortcuts before relying on it.
