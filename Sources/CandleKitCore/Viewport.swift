import Foundation

/// Minimum and maximum candle spacing, in points.
public struct ZoomLimits: Hashable, Sendable {
    public var minimumSpacing: Double
    public var maximumSpacing: Double

    public init(minimumSpacing: Double = 1.5, maximumSpacing: Double = 48) {
        precondition(
            minimumSpacing > 0 && minimumSpacing <= maximumSpacing,
            "ZoomLimits requires 0 < minimumSpacing <= maximumSpacing"
        )
        self.minimumSpacing = minimumSpacing
        self.maximumSpacing = maximumSpacing
    }

    public func clamp(_ spacing: Double) -> Double {
        guard spacing.isFinite else { return minimumSpacing }
        return min(max(spacing, minimumSpacing), maximumSpacing)
    }
}

/// The visible window onto a candle series.
///
/// The horizontal axis is measured in *positions*: candle `i` occupies `[i, i + 1)` and is centered
/// at `i + 0.5`. Indexing by position instead of timestamp means market closures (nights, weekends,
/// holidays) never leave gaps. The type has no UI dependencies, so every mapping is unit tested.
///
/// `Codable` so a `ChartLayout` (see `ChartLayout.swift`) can capture and restore exactly where a
/// trader left the chart scrolled and zoomed to.
public struct Viewport: Hashable, Sendable, Codable {
    /// Position shown at the right edge of the plot. Fractional values allow smooth panning.
    public var rightEdge: Double
    /// Width of one candle slot, in points. This is the zoom level.
    public var spacing: Double

    public init(rightEdge: Double, spacing: Double) {
        self.rightEdge = rightEdge
        self.spacing = spacing
    }

    /// A viewport showing the newest candle with `rightPadding` empty slots after it.
    public static func latest(count: Int, spacing: Double, rightPadding: Double = 3) -> Viewport {
        Viewport(rightEdge: Double(count) + rightPadding, spacing: spacing)
    }

    public func visibleCandleCount(width: Double) -> Double {
        width / spacing
    }

    /// Position shown at the left edge of the plot.
    public func leftEdge(width: Double) -> Double {
        rightEdge - width / spacing
    }

    public func position(atX x: Double, width: Double) -> Double {
        rightEdge - (width - x) / spacing
    }

    public func x(atPosition position: Double, width: Double) -> Double {
        width - (rightEdge - position) * spacing
    }

    public func centerX(ofCandle index: Int, width: Double) -> Double {
        x(atPosition: Double(index) + 0.5, width: width)
    }

    /// The candle under `x`, clamped to the data. `nil` when there is no data.
    public func candleIndex(atX x: Double, width: Double, count: Int) -> Int? {
        guard count > 0, spacing > 0 else { return nil }
        let raw = position(atX: x, width: width).rounded(.down)
        guard raw.isFinite else { return nil }
        return Int(min(max(raw, 0), Double(count - 1)))
    }

    /// Indices of candles at least partially inside a plot of `width` points.
    public func visibleRange(width: Double, count: Int) -> Range<Int> {
        guard count > 0, spacing > 0, width > 0, rightEdge.isFinite else { return 0..<0 }
        let lowerPosition = leftEdge(width: width).rounded(.down)
        let upperPosition = rightEdge.rounded(.up)
        let lower = Int(min(max(lowerPosition, 0), Double(count)))
        let upper = Int(min(max(upperPosition, 0), Double(count)))
        return lower..<max(lower, upper)
    }

    /// Moves the content by `dx` points. Dragging right (positive `dx`) reveals older candles.
    public mutating func pan(byPoints dx: Double) {
        guard spacing > 0, dx.isFinite else { return }
        rightEdge -= dx / spacing
    }

    /// Scales candle spacing while keeping the position under `anchorX` fixed on screen.
    public mutating func zoom(by scale: Double, anchorX: Double, width: Double, limits: ZoomLimits) {
        guard scale.isFinite, scale > 0, spacing > 0 else { return }
        let anchor = position(atX: anchorX, width: width)
        let newSpacing = limits.clamp(spacing * scale)
        rightEdge = anchor + (width - anchorX) / newSpacing
        spacing = newSpacing
    }

    /// Keeps at least half a screen of data visible in either direction.
    public func clamped(count: Int, width: Double, limits: ZoomLimits) -> Viewport {
        var result = self
        result.spacing = limits.clamp(spacing)
        guard width > 0 else { return result }
        let halfScreen = width / result.spacing / 2
        let maximumRight = Double(count) + halfScreen
        let minimumRight = min(Double(count), halfScreen)
        let edge = rightEdge.isFinite ? rightEdge : maximumRight
        result.rightEdge = min(max(edge, minimumRight), maximumRight)
        return result
    }

    /// `true` when the newest candle is fully on screen.
    public func isShowingLatest(count: Int) -> Bool {
        rightEdge >= Double(count)
    }
}
