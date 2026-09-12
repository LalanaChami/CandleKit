# Device QA checklist

Manual checks that need a simulator or device — none of this can be verified from the command
line. Start here; `docs/ROADMAP.md` task 1.1 will grow this into a fuller pass once Phase 0 (the
project actually building) is done.

Run through the **"Unreleased" changes** section first — it covers exactly what changed in the
most recent fix pass and is the most important section to check before trusting any of it.

## Unreleased changes (check these first)

- [ ] **Momentum edge-bounce.** Flick the chart hard enough to reach the newest or the oldest
      candle. It should overshoot slightly and spring back, not stop dead. Try it at both a slow
      and a fast flick speed — a very slow flick that dies right at the edge may not visibly bounce
      (expected; see CHANGELOG), but anything with real speed behind it should.
- [ ] **Rubber-band drag still feels right.** Drag past either edge with a finger down; it should
      resist increasingly, and spring back on release. Confirm this still works exactly as before —
      the momentum change reuses this same code path.
- [ ] **Long-press no longer competes with slow drags.** Do a slow, deliberate one-finger drag
      (not a flick) starting from a dead stop. It should pan, not open the crosshair. Repeat several
      times — this was intermittent, not every time — and also confirm a genuine long-press (finger
      down, hold still) still opens the crosshair promptly.
- [ ] **Haptics.** You should feel: one light tap when the crosshair engages, a further tick each
      time it snaps to a new candle while dragging, one rigid tap only when a pinch hits its zoom
      limit, one medium tap on double-tap-to-reset. You should **not** hear any sound effects, and
      should **not** feel a tap just from an ordinary scroll reaching the edge.
- [ ] **Reduce Motion** (Settings → Accessibility → Motion → Reduce Motion, on). With it on:
      new data should appear immediately (no per-candle sweep-in), double-tap-to-reset and the
      "Jump to latest" button should snap instantly (no spring), and a fling into the edge should
      stop dead again rather than bounce. With it off, all of the above should animate as usual —
      confirm the flag doesn't leak into the normal case.
- [ ] **No leaked animations.** Trigger the appear animation (switch timeframe or symbol so new
      data loads) or start a "reset zoom", then immediately navigate away or switch tabs before it
      finishes. Nothing should visibly continue in the background, and returning to the chart
      shouldn't show it mid-animation from before. This is hard to fully verify without Instruments
      (see below) but should at least look right.
- [ ] **Instruments: Leaks and Allocations.** Repeatedly trigger the appear animation and reset-zoom
      spring while the chart is on screen, then navigate away mid-animation each time, several times
      in a row. Watch for `CandleChartState` instances that should have deallocated but haven't.
      This is the one item on this list that actually confirms the memory-leak fix rather than just
      the visible behavior around it.

## General interaction

- [ ] Pan with momentum; pinch anchored under both fingers; pan and pinch together.
- [ ] Long-press crosshair: header updates, price/time tags stay on their axes, releases cleanly.
- [ ] Double-tap resets zoom and scrolls to latest.
- [ ] A vertical drag starting on the chart scrolls the containing page (see the "In a page" demo
      tab) instead of being captured by the chart.
- [ ] Rotate the device and resize (iPad split view); nothing clips or misaligns.
- [ ] Light mode, dark mode, and Increase Contrast.
- [ ] Dynamic Type from the smallest size through AX5.
- [ ] VoiceOver: the chart announces a summary, swiping up/down pages through history, and the
      Audio Graph (rotor → Charts) plays the close-price series.
- [ ] Live data: chart follows the latest candle when scrolled to the right edge; stays where you
      left it when scrolled back into history.
- [ ] Scroll back far enough to trigger history loading; confirm it only fires once per batch and
      recovers if the fetch fails and you scroll away and back.
- [ ] On a ProMotion device, momentum feels like it's running at 120Hz (smooth, not 60Hz-choppy).

## What to do with a failure

Note the device/OS, the exact steps, and whether it reproduces every time or intermittently. For
anything covered by an existing KI-N in `docs/ROADMAP.md`, add the note there. For anything new,
add a new KI-N row.
