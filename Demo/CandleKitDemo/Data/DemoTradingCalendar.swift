import Foundation

/// When the simulated equities trade: weekdays, 04:00 to 20:00 New York time (pre-market, regular
/// session and after-hours), matching `TradingSession.usEquities`. Candles exist only inside it, so the
/// shaded regions line up with real-looking gaps overnight and at weekends.
enum DemoTradingCalendar {
    static let zone = TimeZone(identifier: "America/New_York") ?? .gmt

    /// The `count` most recent candle start times at or before `newest`, oldest first.
    static func tradingTimes(endingAtOrBefore newest: Date, interval: TimeInterval, count: Int) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var times: [Date] = []
        var time = newest
        var steps = 0
        // The bound only protects against a bad interval; real runs need about 2.2 steps per candle.
        while times.count < count, steps < count * 60 {
            if isTrading(time, interval: interval, calendar: calendar) { times.append(time) }
            time = time.addingTimeInterval(-interval)
            steps += 1
        }
        return times.reversed()
    }

    private static func isTrading(_ time: Date, interval: TimeInterval, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: time)
        guard let weekday = parts.weekday, (2...6).contains(weekday) else { return false }
        // Daily and 6-hour candles span the whole day, so only weekends are skipped.
        if interval >= 21_600 { return true }
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minute >= 4 * 60 && minute < 20 * 60
    }
}
