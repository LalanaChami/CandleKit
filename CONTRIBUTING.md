# Contributing to CandleKit

Thanks for helping. Bug reports, feature requests and pull requests are all welcome.

## Reporting a bug

Please include the iOS version, the device or simulator, roughly how many candles you were showing, and the smallest snippet that reproduces the problem. For rendering glitches, a screenshot or screen recording helps a lot.

## Making a change

Open an issue before starting anything large, so we can agree on the approach first.

Keep logic that doesn't need a screen in `CandleKitCore`, and cover it with tests in `Tests/CandleKitCoreTests`. Coordinate math, scales, indicators and data handling all belong there. `CandleKit` should stay a thin layer that turns those results into drawing and gestures.

Before opening a pull request, run `swift test`, build the `CandleKit` scheme for an iOS Simulator in Xcode, and try your change in the previews in both light and dark mode. Public API needs documentation comments.

## Performance

The chart redraws on every frame of a scroll, so avoid per-frame allocations that grow with the size of the data set, and avoid work that runs over all candles rather than the visible range. If a change touches the render path, mention how you checked its performance.

## Code of conduct

Be kind and assume good intent. Maintainers may remove comments or contributions that are disrespectful.
