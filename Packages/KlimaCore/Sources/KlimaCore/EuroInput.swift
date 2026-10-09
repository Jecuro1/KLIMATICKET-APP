import Foundation

/// Typing and pasting euro amounts the Austrian way ("24,90") – the trip editor's price field.
///
/// - Comma **and** dot work as the decimal separator: the decimal pad shows the device region's key ("," in Austria,
///   "." elsewhere), and pasted prices come in every spelling.
/// - Grouping is recognised when it cannot be a decimal: "1.024,50", "1 024,50", "1,024.50", "1.500" (a single dot followed
///   by exactly three digits after a non-zero integer part is the Austrian thousands separator).
/// - While typing (`live`), the text is normalised at once: "." becomes ",", at most two decimals, no leading zeros, at most
///   `maxIntegerDigits` before the comma (a further digit simply does not go in).
public enum EuroInput {
    /// The field takes up to € 9.999,99 per direction.
    public static let maxIntegerDigits = 4

    /// The digits of an amount, split at its decimal separator.
    public struct Parts: Equatable, Sendable {
        public var integer: String
        public var fraction: String
        /// A decimal separator was typed ("12," while typing counts).
        public var hasDecimalSeparator: Bool
    }

    /// Value of typed or pasted text, rounded to cents. Nil when empty, not a number, ≤ 0 or above the field's range.
    public static func parse(_ text: String) -> Double? {
        let parts = split(text)
        guard !parts.integer.isEmpty || !parts.fraction.isEmpty else { return nil }
        let integer = parts.integer.isEmpty ? "0" : parts.integer
        let fraction = parts.fraction.isEmpty ? "0" : parts.fraction
        guard let value = Double(integer + "." + fraction), value.isFinite, value > 0, value < 10_000 else { return nil }
        return (value * 100).rounded() / 100
    }

    /// Normalised field text after an edit: "23.5" → "23,5", "007" → "7", "1,505" → "1,50", ",5" → "0,5", "€ 12" → "12".
    /// Returns `previous` when the edit would exceed `maxIntegerDigits` (the extra digit does not go in).
    public static func live(_ text: String, previous: String = "") -> String {
        let parts = split(text)
        var integer = String(parts.integer.drop { $0 == "0" })
        if integer.isEmpty && (parts.hasDecimalSeparator || !parts.integer.isEmpty) { integer = "0" }
        guard integer.count <= maxIntegerDigits else { return previous }
        guard parts.hasDecimalSeparator else { return integer }
        return integer + "," + parts.fraction.prefix(2)
    }

    /// "24,90" for the field (no grouping – it never holds more than four integer digits); "" for 0.
    public static func editableText(_ value: Double) -> String {
        guard value > 0, value.isFinite else { return "" }
        let cents = Int((value * 100).rounded())
        return "\(cents / 100),\(String(format: "%02d", cents % 100))"
    }

    /// Splits text into the integer digits and the decimal digits (see the type's rules). Everything but ASCII digits,
    /// "," and "." is ignored (€, spaces, no-break spaces, letters).
    public static func split(_ text: String) -> Parts {
        let chars = text.filter { ($0.isASCII && $0.isNumber) || $0 == "," || $0 == "." }.map { $0 }
        let separators = chars.indices.filter { chars[$0] == "," || chars[$0] == "." }
        guard let last = separators.last else {
            return Parts(integer: String(chars), fraction: "", hasDecimalSeparator: false)
        }
        let trailing = chars.count - last - 1
        let leading = chars[..<last].filter(\.isNumber)
        let kinds = Set(separators.map { chars[$0] })
        let decimal: Int?
        if kinds.count > 1 {
            decimal = last                                              // "1.234,50" · "1,234.50"
        } else if separators.count > 1 {
            decimal = trailing == 3 ? nil : last                        // "1.234.567" · "1,234,567" vs. "1.234.5"
        } else if chars[last] == "." && trailing == 3 && !leading.isEmpty && leading.first != "0" {
            decimal = nil                                               // "1.500" = € 1.500 (de-AT grouping)
        } else {
            decimal = last                                              // "12,5" · "12.5" · "12," · "0.500"
        }
        guard let decimal else {
            return Parts(integer: String(chars.filter(\.isNumber)), fraction: "", hasDecimalSeparator: false)
        }
        return Parts(integer: String(chars[..<decimal].filter(\.isNumber)),
                     fraction: String(chars[(decimal + 1)...].filter(\.isNumber)),
                     hasDecimalSeparator: true)
    }
}

/// Plausibility of an own price against the estimate for the same route – a friendly hint, never a block
/// ("€ 150 für Wien → Mödling? Das wirkt hoch.").
public enum FarePlausibility: Equatable, Sendable {
    /// About twice the one-way estimate: probably the price for there and back (the field is per direction).
    case looksLikeReturn(oneWay: Double)
    /// Far above the estimate (`reference`), or above `ceiling` when there is no estimate.
    case high(reference: Double?)
    /// Far below the estimate.
    case low(reference: Double)

    /// Above this a one-way fare within Austria is implausible even without an estimate (1st class Bregenz → Wien is
    /// well below it).
    public static let ceiling: Double = 250

    /// Nil when the price is plausible (or there is nothing to compare).
    public static func check(entered: Double, estimate: Double?) -> FarePlausibility? {
        guard entered > 0, entered.isFinite else { return nil }
        guard let estimate, estimate > 0, estimate.isFinite else {
            return entered > ceiling ? .high(reference: nil) : nil
        }
        if estimate >= 3, abs(entered - 2 * estimate) <= max(0.08 * 2 * estimate, 0.5) {
            return .looksLikeReturn(oneWay: (entered / 2 * 100).rounded() / 100)
        }
        if entered > max(estimate * 3, estimate + 15) { return .high(reference: estimate) }
        if entered < estimate / 3 && estimate - entered >= 3 { return .low(reference: estimate) }
        return nil
    }
}
