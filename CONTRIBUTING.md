# Contributing to CandleKit

Thanks for helping. Bug reports, feature requests and pull requests are all welcome.

## Reporting a bug

Please include the iOS version, the device or simulator, roughly how many candles you were showing, and the smallest snippet that reproduces the problem. For rendering glitches, a screenshot or screen recording helps a lot.

## Making a change

Open an issue before starting anything large, so we can agree on the approach first.

Keep logic that doesn't need a screen in `CandleKitCore`, and cover it with tests in `Tests/CandleKitCoreTests`. Coordinate math, scales, indicators and data handling all belong there. `CandleKit` should stay a thin layer that turns those results into drawing and gestures.

## Building and testing

You'll need Xcode 16 or later (Swift 6 toolchain) and an iOS 17 simulator or device.

```sh
swift build && swift test            # CandleKitCore: builds and tests on macOS and Linux
swift test --filter Viewport         # run a matching suite or test by name
```

`swift build` passing proves nothing about the SwiftUI layer — every file in `Sources/CandleKit/` is wrapped in `#if os(iOS)`, so it compiles out entirely on a plain `swift build`. If you touched anything under `Sources/CandleKit/`, also run:

```sh
xcodebuild build -scheme CandleKit -destination 'generic/platform=iOS Simulator'
```

To build and run the demo app, from the `Demo/` directory:

```sh
brew install xcodegen   # if not already installed
xcodegen generate       # regenerates CandleKitDemo.xcodeproj from project.yml — never edit the .xcodeproj directly, it's gitignored
open CandleKitDemo.xcodeproj
```

Or to build it headlessly the way CI does:

```sh
xcodebuild build -project CandleKitDemo.xcodeproj -scheme CandleKitDemo -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Before opening a pull request: run `swift test`, run the `xcodebuild` build above for any change under `Sources/CandleKit/` (the demo builds too if the UI layer or a public API changed), and try your change in the Xcode previews in both light and dark mode. Public API needs documentation comments.

## Formatting

CandleKit uses the `swift-format` tool that ships with the Swift 6 toolchain (`swift format` from the command line, or Xcode's built-in "Format File" / format-on-save). There's no checked-in config yet and CI doesn't lint for it — that's tracked as a follow-up so a mechanical reformat doesn't land bundled with unrelated changes. Until then, match the style of the surrounding code.

## Performance

The chart redraws on every frame of a scroll, so avoid per-frame allocations that grow with the size of the data set, and avoid work that runs over all candles rather than the visible range. If a change touches the render path, mention how you checked its performance.

## Code of conduct

Be kind and assume good intent. Maintainers may remove comments or contributions that are disrespectful.
