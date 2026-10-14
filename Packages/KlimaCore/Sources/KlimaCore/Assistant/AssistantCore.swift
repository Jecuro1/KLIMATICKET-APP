import Foundation

// MARK: - Availability (docs/LOCAL_AI.md §2)

/// What the on-device model reports about itself. The app maps `SystemLanguageModel.Availability` onto this, so every
/// branch of `AssistantAvailabilityResolver` runs on Linux too.
public enum AssistantSystemState: Equatable, Sendable {
    case available
    /// Apple Intelligence is switched off in the iOS settings.
    case appleIntelligenceNotEnabled
    /// The model is still being prepared (first start, download).
    case modelNotReady
    /// This device or iOS version cannot run the on-device model.
    case deviceNotEligible
}

/// The states the Settings page shows. `available` is the only state in which the model is asked.
public enum AssistantAvailability: Equatable, Sendable {
    case available
    /// Apple Intelligence is off on the device (iOS Einstellungen).
    case notEnabled
    /// The device or the iOS version has no on-device model.
    case unsupportedDevice
    /// The model runs, but not in German (Österreich).
    case languageUnsupported
    case modelNotReady
    /// Switched off in KlimaBilanz itself (Einstellungen › KI).
    case switchedOff
}

public enum AssistantAvailabilityResolver {
    /// Priority: the app switch first, then the device, then the language. The rule-based fallbacks work in every state.
    public static func resolve(system: AssistantSystemState, supportsGerman: Bool, switchedOn: Bool) -> AssistantAvailability {
        guard switchedOn else { return .switchedOff }
        switch system {
        case .deviceNotEligible: return .unsupportedDevice
        case .appleIntelligenceNotEnabled: return .notEnabled
        case .modelNotReady: return .modelNotReady
        case .available: return supportsGerman ? .available : .languageUnsupported
        }
    }
}

/// Where a shown text or a parsed query came from. Shown next to every AI result, so the user always knows.
public enum AssistantSource: Equatable, Sendable {
    /// Written by the on-device model and checked by `AssistantNumberGuard` / `TripQueryValidator`.
    case model
    /// Built by the deterministic rules in this module (the fallback, always available).
    case rules
    /// Deterministic demo text for `-KBDemo` and screenshots: no model is asked.
    case demo
}

/// A short German text for the UI, with its origin.
public struct AssistantText: Equatable, Sendable {
    public var text: String
    public var source: AssistantSource

    public init(text: String, source: AssistantSource) {
        self.text = text
        self.source = source
    }
}

// MARK: - German display format for facts

/// The numbers the model may use, formatted the way the app shows them (`€ 1.400`, `€ 23,50`, `1.240 km`).
/// Only formatting lives here; no new figure is computed.
public enum AssistantFormat {
    public static func integer(_ value: Int) -> String {
        let digits = Array(String(abs(value)))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append(".") }
            out.append(digit)
        }
        return (value < 0 ? "-" : "") + out
    }

    /// `decimals` digits after a decimal comma, rounded half away from zero.
    public static func decimal(_ value: Double, decimals: Int) -> String {
        let factor = pow(10, Double(decimals))
        let rounded = (abs(value) * factor).rounded() / factor
        let whole = Int(rounded.rounded(.down))
        var text = integer(whole)
        if decimals > 0 {
            let fraction = Int(((rounded - Double(whole)) * factor).rounded())
            text += "," + String(format: "%0\(decimals)ld", fraction)
        }
        return (value < 0 && rounded > 0 ? "-" : "") + text
    }

    /// Whole euros for amounts from 100 € up and for whole amounts, cents otherwise: `€ 1.400`, `€ 23,50`.
    public static func euro(_ value: Double) -> String {
        let cents = (abs(value) * 100).rounded()
        let wholeAmount = cents.truncatingRemainder(dividingBy: 100) == 0
        let decimals = (abs(value) >= 100 || wholeAmount) ? 0 : 2
        return "€ " + decimal(value, decimals: decimals)
    }

    public static func kilometres(_ value: Double) -> String { integer(Int(value.rounded())) + " km" }

    /// `04.10.` – day and month with a trailing dot, the way German dates are written.
    public static func dayMonth(_ date: Date, calendar: Calendar = .vienna) -> String {
        let parts = calendar.dateComponents([.day, .month], from: date)
        return String(format: "%02ld.%02ld.", parts.day ?? 0, parts.month ?? 0)
    }
}

// MARK: - Number guard (the model must not invent numbers)

/// Every number a generated text contains must also occur in the facts the model was given (docs/LOCAL_AI.md §4).
/// Numbers are compared in one normal form: `1.400` and `1400` are the same, `23,50` and `23.5` are the same,
/// `18.10.` is `18.1` on both sides. A text that fails the check is never shown; the rule-based text is used instead.
public enum AssistantNumberGuard {
    /// The normal forms of all numbers in `text`, in order of appearance.
    public static func tokens(in text: String) -> [String] {
        let chars = Array(text)
        var out: [String] = []
        var index = 0
        while index < chars.count {
            guard isDigit(chars[index]) else { index += 1; continue }
            var integerPart = digits(chars, from: &index)
            var fraction: String?
            // "1.400" (thousands group) and "23,50" (decimal comma) and "18.10" (day.month, read as a decimal).
            while index + 1 < chars.count, chars[index] == "." || chars[index] == ",", isDigit(chars[index + 1]) {
                let separator = chars[index]
                index += 1
                let group = digits(chars, from: &index)
                if separator == ".", group.count == 3, !(index < chars.count && isDigit(chars[index])) {
                    integerPart += group
                    continue
                }
                fraction = group
                break
            }
            if let fraction {
                out.append(normal(integer: integerPart, fraction: fraction))
            } else {
                out.append(normal(integer: integerPart, fraction: nil))
            }
        }
        return out
    }

    /// `true` when every number in `text` occurs in `facts`.
    public static func accepts(_ text: String, facts: [String]) -> Bool {
        unknown(in: text, facts: facts).isEmpty
    }

    /// The numbers of `text` that do not occur in `facts` (empty when the text is accepted).
    public static func unknown(in text: String, facts: [String]) -> [String] {
        let allowed = Set(facts.flatMap(tokens(in:)))
        return tokens(in: text).filter { !allowed.contains($0) }
    }

    private static func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }

    private static func digits(_ chars: [Character], from index: inout Int) -> String {
        var out = ""
        while index < chars.count, isDigit(chars[index]) {
            out.append(chars[index])
            index += 1
        }
        return out
    }

    private static func normal(integer: String, fraction: String?) -> String {
        guard let fraction, !fraction.isEmpty else {
            return String(Int(integer) ?? 0)
        }
        // Trailing zeros carry no value ("18.10" == "18.1", "23,50" == "23.5").
        var trimmed = fraction
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.isEmpty { return String(Int(integer) ?? 0) }
        return String(Int(integer) ?? 0) + "." + trimmed
    }
}
