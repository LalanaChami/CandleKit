#if os(iOS)
import SwiftUI
import UIKit

/// A small label drawn in the corner of an image made by ``CandleChartState/snapshot(scale:colorScheme:watermark:)``.
///
/// Off by default: an app's own shared screenshots shouldn't carry CandleKit's name unless the app
/// chooses that. Pass ``candleKit`` to credit the library, or your own text to brand the image.
public struct ChartWatermark: Sendable, Equatable {
    public var text: String

    public init(_ text: String) {
        self.text = text
    }

    /// "Made with CandleKit".
    public static let candleKit = ChartWatermark("Made with CandleKit")
}

extension CandleChartState {
    /// Renders the chart as it currently looks on screen into an image, ready for a share sheet,
    /// the Photos library or a pasteboard.
    ///
    /// ```swift
    /// if let image = state.snapshot(colorScheme: colorScheme, watermark: .candleKit) {
    ///     UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    /// }
    /// ```
    ///
    /// The image covers the same visible range, zoom and price scale as the chart on screen, at the
    /// chart's current point size. Returns `nil` until the chart has drawn at least once.
    ///
    /// What is and isn't in the image in this version:
    /// - Included: grid, volume, candles, indicators and indicator panes, the axes, the last-price
    ///   line and tag, and the optional watermark.
    /// - Not included: the crosshair, drawings, and the header above the chart. A frosted
    ///   (`priceAxisMaterial`) axis is drawn as a plain axis, because `Material` doesn't render under
    ///   `ImageRenderer`.
    ///
    /// - Parameters:
    ///   - scale: Pixels per point. The default of 3 matches current iPhones.
    ///   - colorScheme: The appearance to render in. `ImageRenderer` can't see the chart's own
    ///     environment, so pass your view's `colorScheme` if you want the image to match what the
    ///     person is looking at. When `nil`, the current system appearance is used.
    ///   - watermark: Text drawn in the bottom-right corner of the plot, or `nil` for none.
    public func snapshot(
        scale: CGFloat = 3,
        colorScheme: ColorScheme? = nil,
        watermark: ChartWatermark? = nil
    ) -> UIImage? {
        guard let frame = currentFrame, let style = currentStyle else { return nil }
        // The chart's full size, recovered from its regions: the price axis ends at the right edge
        // and the time axis at the bottom edge (see `ChartRegions.init`).
        let size = CGSize(width: frame.layout.priceAxis.maxX, height: frame.layout.timeAxis.maxY)
        guard size.width > 0, size.height > 0 else { return nil }

        let resolvedScheme = colorScheme
            ?? (UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light)

        let renderer = ImageRenderer(
            content: ChartSnapshotView(frame: frame, style: style, size: size, watermark: watermark)
                .environment(\.colorScheme, resolvedScheme)
                .environment(\.displayScale, scale)
        )
        renderer.scale = scale
        return renderer.uiImage
    }
}

/// The chart, redrawn from a finished `ChartFrame` for `ImageRenderer`.
///
/// Reuses `ChartBaseLayer` (the same Canvas the live chart draws) and `PriceAxisLabels`, so the image
/// can't drift from the screen. Everything the live chart layers on top for interaction (crosshair,
/// gestures, drawings) is deliberately absent.
private struct ChartSnapshotView: View {
    let frame: ChartFrame
    let style: CandleChartStyle
    let size: CGSize
    let watermark: ChartWatermark?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(uiColor: .systemBackground))
            ChartBaseLayer(frame: frame, style: style, appearPhase: 1)
            PriceAxisLabels(frame: frame, style: style)
            lastPriceTag
            if let watermark {
                Text(watermark.text)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(style.axisLabelColor.opacity(0.8))
                    .position(
                        x: frame.layout.plot.maxX - 6 - watermarkHalfWidth(watermark),
                        y: frame.layout.plot.minY + 14
                    )
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// `position` places a view's center, so a right-aligned label needs half its width. Estimated
    /// from the character count rather than measured: this runs once per share, and a few points
    /// of error on a corner watermark isn't visible.
    private func watermarkHalfWidth(_ watermark: ChartWatermark) -> CGFloat {
        CGFloat(watermark.text.count) * 3.2
    }

    @ViewBuilder
    private var lastPriceTag: some View {
        if let last = frame.candles.last, let label = frame.lastPriceLabel {
            let axis = frame.layout.priceAxis
            let plot = frame.layout.plot
            let half: CGFloat = 10
            let y = min(max(frame.y(forPrice: last.close), plot.minY + half), plot.maxY - half)
            // Same structure as `LastPriceBadge` in CandlestickChart.swift (minus the numeric
            // transition, which means nothing in a still image), so the tag lands in the same place.
            HStack(spacing: 0) {
                Text(label)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        last.isBullish ? style.upColor : style.downColor,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                Spacer(minLength: 0)
            }
            .padding(.leading, 2)
            .frame(width: axis.width, height: half * 2, alignment: .leading)
            .position(x: axis.minX + axis.width / 2, y: y)
        }
    }
}
#endif
