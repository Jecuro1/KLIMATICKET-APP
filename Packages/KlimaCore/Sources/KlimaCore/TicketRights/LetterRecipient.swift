import Foundation

/// Who the letter is addressed to: the Kundenservice of the KlimaTicket Ö.
///
/// The address is copied from the AGB (Stand 1.1.2026), where it stands the same way in 15.4, 17.4, 18.3, 18.5 and 20.1:
/// „KlimaTicket Kundenservice, Postfach 100, 1020 Wien“. The holder's own renewal letter may name another address – then that
/// one wins, so the recipient is an editable field that starts with this constant (docs/TICKET_LETTERS.md §3).
public struct LetterRecipient: Equatable, Sendable {
    public var lines: [String]

    public init(lines: [String]) {
        self.lines = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// „KlimaTicket Kundenservice, Postfach 100, 1020 Wien“ – AGB 15.4, 17.4, 18.3, 18.5, 20.1 (Stand 1.1.2026).
    public static let kundenservice = LetterRecipient(lines: ["KlimaTicket Kundenservice", "Postfach 100", "1020 Wien"])

    /// The clauses the constant above is copied from.
    public static let kundenserviceClauses = "AGB 17.4 und 20.1"

    /// What the field shows while it is empty.
    public static let placeholder = "Adresse laut deinem Verlängerungsbrief"

    /// Parses the text of the editable field (one line per address line).
    public static func parse(_ text: String) -> LetterRecipient {
        LetterRecipient(lines: text.components(separatedBy: .newlines))
    }

    /// The editable text of the field.
    public var text: String { lines.joined(separator: "\n") }

    public var isEmpty: Bool { lines.isEmpty }

    /// True when the address is the one from the AGB.
    public var isKundenservice: Bool { self == .kundenservice }
}

/// Who writes: the holder. Kept on the device only (the Keychain, if the holder switches „Name und Adresse merken“ on).
public struct LetterSender: Equatable, Sendable, Codable {
    public var name: String
    public var street: String
    public var postcode: String
    public var place: String

    public init(name: String = "", street: String = "", postcode: String = "", place: String = "") {
        self.name = name
        self.street = street
        self.postcode = postcode
        self.place = place
    }

    public var trimmed: LetterSender {
        func clean(_ text: String) -> String {
            text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
        return LetterSender(name: clean(name), street: clean(street), postcode: clean(postcode), place: clean(place))
    }

    /// The fields that are still empty, in form order.
    public var missingFields: [LetterField] {
        let s = trimmed
        var result: [LetterField] = []
        if s.name.isEmpty { result.append(.name) }
        if s.street.isEmpty { result.append(.street) }
        if s.postcode.isEmpty { result.append(.postcode) }
        if s.place.isEmpty { result.append(.place) }
        return result
    }

    public var isEmpty: Bool {
        let s = trimmed
        return s.name.isEmpty && s.street.isEmpty && s.postcode.isEmpty && s.place.isEmpty
    }

    /// Three lines for the letter head: name, street, „PLZ Ort“ – blank lines for what is still missing.
    public var letterLines: [String] {
        let s = trimmed
        let town = [s.postcode, s.place].filter { !$0.isEmpty }.joined(separator: " ")
        return [LetterFormat.filled(s.name), LetterFormat.filled(s.street), LetterFormat.filled(town)]
    }
}
