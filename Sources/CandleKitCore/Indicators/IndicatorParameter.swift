import Foundation

// Indicator parameters are modelled explicitly, rather than being stored as fields on each
// indicator type, for two reasons that both matter:
//
//  1. The picker UI can render a settings form for *any* indicator — including one an app defines
//     itself — without knowing anything about it. A period becomes a stepper with a valid range, a
//     choice becomes a segmented control. Without this, every new indicator needs hand-written UI.
//  2. A saved chart layout serialises to `identifier + [key: value]`, which is stable across
//     releases. Storing a Swift enum with associated values instead would make every new indicator
//     a potential decoding break for layouts users have already saved.

/// A parameter's current value.
public enum IndicatorParameterValue: Hashable, Sendable, Codable {
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case choice(String)

    public var intValue: Int? {
        if case let .integer(value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case let .number(value): return value
        case let .integer(value): return Double(value)
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case let .boolean(value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case let .choice(value) = self { return value }
        return nil
    }

    // Encoded as a tagged object so a stored layout stays readable and can gain cases later
    // without invalidating what's already on disk.
    private enum CodingKeys: String, CodingKey { case type, value }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "integer": self = .integer(try container.decode(Int.self, forKey: .value))
        case "number": self = .number(try container.decode(Double.self, forKey: .value))
        case "boolean": self = .boolean(try container.decode(Bool.self, forKey: .value))
        case "choice": self = .choice(try container.decode(String.self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown indicator parameter type '\(type)'"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .integer(value):
            try container.encode("integer", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .number(value):
            try container.encode("number", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .boolean(value):
            try container.encode("boolean", forKey: .type)
            try container.encode(value, forKey: .value)
        case let .choice(value):
            try container.encode("choice", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

/// What kind of control a parameter should get, and what values are valid.
public enum IndicatorParameterKind: Hashable, Sendable {
    case integer(range: ClosedRange<Int>, step: Int = 1)
    case number(range: ClosedRange<Double>, step: Double = 0.1)
    case boolean
    case choice(options: [String])
}

/// One configurable input to an indicator.
public struct IndicatorParameter: Hashable, Sendable, Identifiable {
    /// Stable key used in saved layouts — `"period"`, `"multiplier"`.
    public let key: String
    /// Shown in the settings form — `"Period"`, `"Std. deviations"`.
    public let name: String
    public let kind: IndicatorParameterKind
    public var value: IndicatorParameterValue

    public var id: String { key }

    public init(key: String, name: String, kind: IndicatorParameterKind, value: IndicatorParameterValue) {
        self.key = key
        self.name = name
        self.kind = kind
        self.value = value
    }

    /// Convenience for the common integer-period case.
    public static func period(
        _ value: Int,
        key: String = "period",
        name: String = "Period",
        range: ClosedRange<Int> = 1...500
    ) -> IndicatorParameter {
        IndicatorParameter(key: key, name: name, kind: .integer(range: range), value: .integer(value))
    }

    /// Clamps `value` into the kind's valid range, and rejects values of the wrong type by keeping
    /// the existing one. A picker binding can therefore never put an indicator into a state that
    /// would crash or produce nonsense — a period of 0 or -3 is the classic way to divide by zero.
    public mutating func setValue(_ newValue: IndicatorParameterValue) {
        switch (kind, newValue) {
        case let (.integer(range, _), .integer(raw)):
            value = .integer(min(max(raw, range.lowerBound), range.upperBound))
        case let (.number(range, _), .number(raw)):
            guard raw.isFinite else { return }
            value = .number(min(max(raw, range.lowerBound), range.upperBound))
        case let (.number(range, _), .integer(raw)):
            value = .number(min(max(Double(raw), range.lowerBound), range.upperBound))
        case (.boolean, .boolean):
            value = newValue
        case let (.choice(options), .choice(raw)):
            guard options.contains(raw) else { return }
            value = newValue
        default:
            return
        }
    }
}

extension Array where Element == IndicatorParameter {
    /// Integer value for `key`, or `fallback` when absent.
    public func integer(_ key: String, default fallback: Int) -> Int {
        first { $0.key == key }?.value.intValue ?? fallback
    }

    /// Double value for `key`, or `fallback` when absent.
    public func number(_ key: String, default fallback: Double) -> Double {
        first { $0.key == key }?.value.doubleValue ?? fallback
    }

    public func boolean(_ key: String, default fallback: Bool) -> Bool {
        first { $0.key == key }?.value.boolValue ?? fallback
    }

    public func choice(_ key: String, default fallback: String) -> String {
        first { $0.key == key }?.value.stringValue ?? fallback
    }

    /// Applies stored values onto these parameters, keeping each one's kind and valid range.
    /// Unknown keys are ignored, so a layout saved by a newer version that added a parameter still
    /// loads in an older one.
    public func applying(_ stored: [String: IndicatorParameterValue]) -> [IndicatorParameter] {
        map { parameter in
            guard let newValue = stored[parameter.key] else { return parameter }
            var updated = parameter
            updated.setValue(newValue)
            return updated
        }
    }

    /// The key/value pairs a saved layout stores.
    public var storedValues: [String: IndicatorParameterValue] {
        Dictionary(uniqueKeysWithValues: map { ($0.key, $0.value) })
    }
}
