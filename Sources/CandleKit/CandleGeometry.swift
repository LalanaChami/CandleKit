#if os(iOS)
import SwiftUI

/// The exact on-screen body and wick rectangles for one candle, in points.
///
/// Shared by `BaseLayerRenderer` (which draws every candle from this) and `CrosshairLayer` (which
/// traces a glow around just the focused one), so the two can never disagree about where a
/// candle's edges actually are. The crosshair used to recompute a candle's shape on its own, in
/// un-pixel-snapped coordinates — close to, but not exactly, what `BaseLayerRenderer` draws — and
/// that small, zoom-dependent drift was visible as the crosshair's highlight shape sliding out of
/// alignment with the real candle underneath it. Snapping to the pixel grid here, the same way
/// `BaseLayerRenderer` already does, removes the drift by construction: both call sites derive
/// their rectangles from the same rounded numbers instead of two independent calculations that
/// happen to usually agree.
struct CandleGeometry {
    let body: CGRect
    let wick: CGRect

    /// Body and wick widths in whole device pixels, with matching parity so the wick sits exactly
    /// centered in the body. Mirrors `BaseLayerRenderer.widthsInPixels`.
    static func widthsInPixels(
        frame: ChartFrame,
        style: CandleChartStyle,
        pixels: PixelGrid
    ) -> (body: CGFloat, wick: CGFloat) {
        let wick = max(1, pixels.scale.rounded())
        var body = max(wick, (CGFloat(frame.viewport.spacing) * style.bodyWidthRatio * pixels.scale).rounded(.down))
        if Int(body - wick) % 2 != 0 {
            body -= 1
        }
        return (max(body, wick), wick)
    }

    static func compute(
        index: Int,
        frame: ChartFrame,
        style: CandleChartStyle,
        pixels: PixelGrid
    ) -> CandleGeometry {
        let (bodyWidth, wickWidth) = widthsInPixels(frame: frame, style: style, pixels: pixels)
        let scale = pixels.scale
        let candle = frame.candles[index]

        let center = (frame.centerX(ofCandle: index) * scale).rounded()
        let bodyLeft = (center - bodyWidth / 2).rounded(.down)
        let wickX = (bodyLeft + (bodyWidth - wickWidth) / 2) / scale
        let wickWidthPoints = wickWidth / scale

        let highY = pixels.snap(frame.y(forPrice: candle.high))
        let lowY = pixels.snap(frame.y(forPrice: candle.low))
        let openY = pixels.snap(frame.y(forPrice: candle.open))
        let closeY = pixels.snap(frame.y(forPrice: candle.close))
        let bodyTop = min(openY, closeY)
        let bodyHeight = max(abs(openY - closeY), pixels.hairline)

        let body = CGRect(x: bodyLeft / scale, y: bodyTop, width: bodyWidth / scale, height: bodyHeight)
        let wick = CGRect(x: wickX, y: highY, width: wickWidthPoints, height: max(lowY - highY, pixels.hairline))
        return CandleGeometry(body: body, wick: wick)
    }
}
#endif
