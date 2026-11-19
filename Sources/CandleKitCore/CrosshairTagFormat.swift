import Foundation

/// Formats the crosshair bottom tag's candle-range line.
///
/// This is the canonical, UI-independent implementation behind
/// `ChartFormat.rangeTime(low:high:time:interval:digits:locale:timeZone:)` (see
/// `Sources/CandleKit/ChartFrame.swift`), which only forwards here. It lives in Core — not in
/// the iOS-only UI layer — so `swift test` covers it on macOS and Linux.
///
/// Example (Spanish locale): `"132,43 - 138,83 · 20 oct, 14:30"`.
public enum CrosshairTagFormat {
    /// The value with exactly `digits` fraction digits in `locale` (negative clamps to 0).
    public static func price(_ value: Double, digits: Int, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(max(0, digits))).locale(locale))
    }

    /// Intraday intervals (`< 86_400` s) render month/day/hour/minute, longer ones
    /// year/month/day, in `locale` and `timeZone`.
    public static func detailedTime(_ date: Date, interval: TimeInterval, locale: Locale, timeZone: TimeZone) -> String {
        var style: Date.FormatStyle
        if interval < 86_400 {
            style = .dateTime.month(.abbreviated).day().hour().minute()
        } else {
            style = .dateTime.year().month(.abbreviated).day()
        }
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// `"min - max · fecha, hora"`: the focused candle's low–high range plus its detailed time.
    public static func rangeTime(
        low: Double, high: Double, time: Date, interval: TimeInterval, digits: Int, locale: Locale, timeZone: TimeZone
    ) -> String {
        "\(price(low, digits: digits, locale: locale)) - \(price(high, digits: digits, locale: locale)) · \(detailedTime(time, interval: interval, locale: locale, timeZone: timeZone))"
    }
}
