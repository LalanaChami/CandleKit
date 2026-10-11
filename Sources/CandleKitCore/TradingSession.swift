import Foundation

/// A recurring window of the trading day, such as US pre-market or after-hours, that a chart can
/// shade so people can tell extended-hours candles from regular-session ones.
///
/// CandleKit has no idea what market a series belongs to, so the app describes the sessions it cares
/// about. ``TradingSession/usEquities`` covers the common US case.
///
/// ```swift
/// CandlestickChart(candles)
///     .tradingSessions(TradingSession.usEquities)
/// ```
public struct TradingSession: Hashable, Sendable {
    /// What kind of window this is. Only the non-regular kinds are shaded; a regular session exists
    /// so a list of sessions can describe the whole day (and so a later feature can use it).
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case regular
        case preMarket
        case afterHours
        case overnight
    }

    public var kind: Kind
    /// First minute of the window, as minutes since local midnight (`0..<1440`).
    public var startMinute: Int
    /// End of the window, exclusive, as minutes since local midnight (`0...1440`).
    ///
    /// When this is not after `startMinute` the window runs past midnight into the next day, for
    /// example 20:00 to 04:00. Equal values mean the whole day.
    public var endMinute: Int
    /// The days the window *starts* on, using `Calendar`'s numbering: 1 is Sunday, 2 is Monday and
    /// 7 is Saturday. A window that runs past midnight belongs to the day it started on, so a
    /// Friday 20:00 to 04:00 session still covers early Saturday morning.
    public var weekdays: Set<Int>
    /// The zone `startMinute` and `endMinute` are measured in.
    public var timeZone: TimeZone

    public init(
        kind: Kind,
        startMinute: Int,
        endMinute: Int,
        weekdays: Set<Int> = [2, 3, 4, 5, 6],
        timeZone: TimeZone = .current
    ) {
        self.kind = kind
        self.startMinute = min(max(startMinute, 0), 1_439)
        self.endMinute = min(max(endMinute, 0), 1_440)
        self.weekdays = weekdays
        self.timeZone = timeZone
    }

    /// Minutes since midnight for a clock time, for readable call sites: `.minute(hour: 9, minute: 30)`.
    public static func minute(hour: Int, minute: Int = 0) -> Int {
        hour * 60 + minute
    }

    /// US equities, Monday to Friday in New York: pre-market 04:00–09:30, regular 09:30–16:00 and
    /// after-hours 16:00–20:00.
    public static var usEquities: [TradingSession] {
        let zone = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: -5 * 3_600) ?? .gmt
        return [
            TradingSession(kind: .preMarket, startMinute: minute(hour: 4), endMinute: minute(hour: 9, minute: 30), timeZone: zone),
            TradingSession(kind: .regular, startMinute: minute(hour: 9, minute: 30), endMinute: minute(hour: 16), timeZone: zone),
            TradingSession(kind: .afterHours, startMinute: minute(hour: 16), endMinute: minute(hour: 20), timeZone: zone),
        ]
    }
}

/// A run of consecutive candles that fall in one kind of session.
public struct SessionRegion: Hashable, Sendable {
    public let kind: TradingSession.Kind
    /// Candle indices, half-open: `range.lowerBound` is the first candle in the region.
    public let range: Range<Int>

    public init(kind: TradingSession.Kind, range: Range<Int>) {
        self.kind = kind
        self.range = range
    }
}

public enum SessionClassifier {
    /// The longest candle interval sessions are applied to. A 4-hour candle can straddle a session
    /// boundary, so shading it by its opening time would mislead, and daily candles have no session.
    public static let longestInterval: TimeInterval = 3_600

    /// Groups a series into regions by the session each candle opens in, oldest first.
    ///
    /// Candles that open outside every session are left out, so gaps between regions are normal.
    /// When sessions overlap, the one listed first wins. Returns no regions for an empty series, no
    /// sessions, or a series whose typical interval is longer than ``longestInterval``.
    ///
    /// This is O(candles) and meant to run when the data changes, not on every frame; use
    /// ``regions(_:intersecting:)`` to pick out what's on screen. It does no calendar arithmetic per
    /// candle: the zone's UTC offset is only looked up again after a daylight-saving transition.
    public static func regions(for candles: [Candle], sessions: [TradingSession]) -> [SessionRegion] {
        guard !sessions.isEmpty, !candles.isEmpty else { return [] }
        guard TimeScale.estimatedInterval(of: candles) <= longestInterval else { return [] }

        var trackers = sessions.map { OffsetTracker(zone: $0.timeZone) }
        var regions: [SessionRegion] = []
        var currentKind: TradingSession.Kind?
        var runStart = 0

        for index in candles.indices {
            let seconds = candles[index].time.timeIntervalSince1970
            var kind: TradingSession.Kind?
            if seconds.isFinite, abs(seconds) < 4_000_000_000_000 {
                let whole = Int(seconds.rounded(.down))
                for sessionIndex in sessions.indices {
                    let local = whole + trackers[sessionIndex].offset(at: candles[index].time)
                    let days = floorDivide(local, 86_400)
                    let minute = (local - days * 86_400) / 60
                    // 1970-01-01 was a Thursday, which is weekday 5 in `Calendar`'s numbering.
                    let weekday = (days + 4 - 7 * floorDivide(days + 4, 7)) + 1
                    if contains(sessions[sessionIndex], minute: minute, weekday: weekday) {
                        kind = sessions[sessionIndex].kind
                        break
                    }
                }
            }
            if kind != currentKind {
                if let currentKind, runStart < index {
                    regions.append(SessionRegion(kind: currentKind, range: runStart..<index))
                }
                currentKind = kind
                runStart = index
            }
        }
        if let currentKind, runStart < candles.count {
            regions.append(SessionRegion(kind: currentKind, range: runStart..<candles.count))
        }
        return regions
    }

    /// The regions that overlap `visible`, found by binary search, so a renderer can ask for just
    /// what's on screen without scanning the whole list. `regions` must come from
    /// ``regions(for:sessions:)`` (sorted, non-overlapping).
    public static func regions(_ regions: [SessionRegion], intersecting visible: Range<Int>) -> ArraySlice<SessionRegion> {
        guard !visible.isEmpty, !regions.isEmpty else { return [] }
        var low = 0
        var high = regions.count
        while low < high {
            let mid = (low + high) / 2
            if regions[mid].range.upperBound <= visible.lowerBound {
                low = mid + 1
            } else {
                high = mid
            }
        }
        var end = low
        while end < regions.count, regions[end].range.lowerBound < visible.upperBound {
            end += 1
        }
        return regions[low..<end]
    }

    private static func contains(_ session: TradingSession, minute: Int, weekday: Int) -> Bool {
        if session.endMinute > session.startMinute {
            return minute >= session.startMinute
                && minute < session.endMinute
                && session.weekdays.contains(weekday)
        }
        // Runs past midnight: the evening part belongs to the day it starts on, the morning part
        // to the day before.
        let previous = weekday == 1 ? 7 : weekday - 1
        return (minute >= session.startMinute && session.weekdays.contains(weekday))
            || (minute < session.endMinute && session.weekdays.contains(previous))
    }

    /// Division that rounds toward negative infinity, so times before 1970 still land in the right day.
    private static func floorDivide(_ value: Int, _ divisor: Int) -> Int {
        let quotient = value / divisor
        return (value % divisor != 0 && (value < 0) != (divisor < 0)) ? quotient - 1 : quotient
    }

    /// A zone's UTC offset, re-read only after a daylight-saving transition. Candles arrive in time
    /// order, so one lookup covers months of them.
    private struct OffsetTracker {
        let zone: TimeZone
        var current = 0
        var validUntil = Date.distantPast

        init(zone: TimeZone) {
            self.zone = zone
        }

        mutating func offset(at date: Date) -> Int {
            if date >= validUntil {
                current = zone.secondsFromGMT(for: date)
                validUntil = zone.nextDaylightSavingTimeTransition(after: date) ?? .distantFuture
            }
            return current
        }
    }
}
