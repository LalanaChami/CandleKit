---
id: replay
title: Replay
sidebar_label: Replay
---

# Replay

`ReplayController` plays a loaded series back one candle at a time.

```swift
@State private var replay = ReplayController()

CandlestickChart(candles).replay(replay)

replay.begin(at: 60)
replay.play()
```

![Replay revealing candles with play, step and speed controls](/img/media/replay.gif)

`step()` reveals one more candle, `pause()` holds, `end()` shows the whole series, and `candlesPerSecond` sets the speed. Playback stops at the last candle. Replay only goes forward; calling `begin(at:)` with a smaller number resets the viewport.

In the Demo, use **Chart Options → Replay** on the Market screen, or the Replay card in the Styles tab.

![Replay and Live Activity cards in the Styles tab](/img/media/styles-bottom.png)
