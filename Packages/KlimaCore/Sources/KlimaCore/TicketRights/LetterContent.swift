import Foundation

// Ticket-Schreiben (docs/TICKET_LETTERS.md): the letters of a KlimaTicket Ö holder to the Kundenservice – the objection to the
// automatic renewal and the cancellation – as pure, structured text. The app draws the same `LetterContent` as the live
// A4 preview and as the PDF, so what you see is what you print. Letters to a company use the formal "Sie" form, the app
// itself talks to the holder with "du".

/// What the AGB of the KlimaTicket Ö (the letters' source) say about itself – cited in every letter and in the hints.
public enum TicketRights {
    /// Version of the Allgemeine Geschäftsbedingungen the clauses below were read from.
    public static let agbStand = "1. Jänner 2026"
    /// The same, short, for hints ("Stand 1.1.2026").
    public static let agbStandShort = "1.1.2026"
    public static let agbURL = "https://www.klimaticket.at/wp-content/uploads/2026/01/KTOE_AGB_260101.pdf"
    public static let agbTitle = "Allgemeine Geschäftsbedingungen für den Kauf des KlimaTicket Ö"
    /// „… gemäß Punkt 17.1 der <agbDative> (Stand …)“.
    public static let agbDative = "Allgemeinen Geschäftsbedingungen für den Kauf des KlimaTicket Ö"

    /// Products of the "KlimaTicket Ö" family that are sold under other conditions than the AGB above
    /// (Bundesheer / Zivildienst / Freiwilligendienst, the closed KlimaTicket Ö 18, the 2021 pre-sale, a Jobticket).
    private static let otherConditions = ["oe-bundesheer", "oe-zivildienst", "oe-freiwilligendienst", "oe-18", "oe-fruehbucher", "oe-jobticket"]

    /// True for the KlimaTicket Ö (Klassik, Jugend, Senior, Spezial, Familie) the AGB above apply to.
    public static func appliesAGB(to ticket: AdvisorTicket) -> Bool {
        guard ticket.family == .oe else { return false }
        return !otherConditions.contains { ticket.productID.hasPrefix($0) }
    }
}

/// Something a letter still needs, or a reason why it must not be sent yet.
public enum LetterField: String, CaseIterable, Sendable, Hashable {
    case name, street, postcode, place, ticketNumber, deadline, reasonDate, letterPlace, recipient

    /// German label as shown next to the field.
    public var title: String {
        switch self {
        case .name: "Name"
        case .street: "Straße und Hausnummer"
        case .postcode: "Postleitzahl"
        case .place: "Ort"
        case .ticketNumber: "Ticketnummer"
        case .deadline: "Frist laut deinem Brief"
        case .reasonDate: "Seit wann der Grund vorliegt"
        case .letterPlace: "Ort des Schreibens"
        case .recipient: "Empfängeradresse"
        }
    }
}

public enum LetterIssue: Equatable, Sendable {
    /// A required field is empty.
    case missing(LetterField)
    /// The deadline from the holder's renewal letter is in the past: the letter would claim something untrue.
    case deadlinePassed
    /// The reason for an extraordinary cancellation cannot lie in the future.
    case reasonInFuture
    /// More than four weeks since the reason arose (AGB 17.2).
    case filingWindowClosed

    /// Quiet German explanation (du-form, it is addressed to the holder).
    public var message: String {
        switch self {
        case .missing(let field): "Es fehlt noch: \(field.title)."
        case .deadlinePassed: "Die Frist ist schon vorbei. Stimmt das Datum nicht, ändere es – sonst frag beim Kundenservice nach."
        case .reasonInFuture: "Der Grund kann erst ab heute zählen – wähle ein Datum bis heute."
        case .filingWindowClosed: "Seit dem Grund sind mehr als vier Wochen vergangen. Frag beim Kundenservice, ob eine Ausnahme möglich ist."
        }
    }
}

/// A finished letter: blocks of text in print order, plus what is still missing.
public struct LetterContent: Equatable, Sendable {
    public struct Fact: Equatable, Sendable {
        public var label: String
        public var value: String

        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    public enum Block: Equatable, Sendable {
        case paragraph(String)
        case facts([Fact])
        case bullets([String])

        public var plainText: String {
            switch self {
            case .paragraph(let text): text
            case .facts(let facts): facts.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
            case .bullets(let items): items.map { "• \($0)" }.joined(separator: "\n")
            }
        }
    }

    /// PDF document title.
    public var documentTitle: String
    public var senderLines: [String]
    public var recipientLines: [String]
    /// "Musterstadt, 12. November 2026".
    public var dateLine: String
    public var subject: String
    public var salutation: String
    public var blocks: [Block]
    public var closing: String
    /// Typed name under the space for the handwritten signature.
    public var signatureName: String
    public var enclosures: [String]
    public var issues: [LetterIssue]

    public init(documentTitle: String, senderLines: [String], recipientLines: [String], dateLine: String, subject: String,
                salutation: String = "Sehr geehrte Damen und Herren,", blocks: [Block],
                closing: String = "Mit freundlichen Grüßen", signatureName: String, enclosures: [String] = [],
                issues: [LetterIssue] = []) {
        self.documentTitle = documentTitle
        self.senderLines = senderLines
        self.recipientLines = recipientLines
        self.dateLine = dateLine
        self.subject = subject
        self.salutation = salutation
        self.blocks = blocks
        self.closing = closing
        self.signatureName = signatureName
        self.enclosures = enclosures
        self.issues = issues
    }

    /// Nothing missing and nothing untrue: the letter may be shared or printed.
    public var isReady: Bool { issues.isEmpty }

    /// The fields that are still empty.
    public var missingFields: [LetterField] {
        issues.compactMap { if case .missing(let field) = $0 { field } else { nil } }
    }

    /// The whole letter as plain text (tests, copying, the accessibility value of the preview).
    public var plainText: String {
        var parts: [String] = []
        parts.append(senderLines.joined(separator: "\n"))
        parts.append(recipientLines.joined(separator: "\n"))
        parts.append(dateLine)
        parts.append(subject)
        parts.append(salutation)
        parts += blocks.map(\.plainText)
        parts.append("\(closing)\n\n\n\(signatureName)")
        if !enclosures.isEmpty {
            parts.append("Anlagen:\n" + enclosures.map { "• \($0)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Formatting

/// Dates and amounts as they stand in an Austrian letter. Independent from the device locale and from ICU (the tests run on
/// Linux): "12. November 2026", "€ 116,70".
public enum LetterFormat {
    /// A blank line to fill in by hand (also stands in for a field that is still empty in the preview).
    public static let blank = "________________"
    /// A line that is meant to be written by hand (the IBAN of a refund) – no missing field, so it stays unmarked in the preview.
    public static let handwritingBlank = String(repeating: "_ ", count: 14).trimmingCharacters(in: .whitespaces)

    static let monthNames = ["Jänner", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober",
                             "November", "Dezember"]

    public static func date(_ date: Date, calendar: Calendar = .vienna) -> String {
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        guard let day = parts.day, let month = parts.month, let year = parts.year, (1...12).contains(month) else { return blank }
        return "\(day). \(monthNames[month - 1]) \(year)"
    }

    /// "€ 116,70", "€ 1.400,00" (always two decimals, point as thousands separator).
    public static func euro(_ value: Double) -> String {
        let cents = Int((value * 100).rounded())
        let absolute = abs(cents)
        let whole = String(absolute / 100)
        var grouped = ""
        for (index, digit) in whole.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped.append(".") }
            grouped.append(digit)
        }
        let fraction = absolute % 100
        return "\(cents < 0 ? "−" : "")€ \(String(grouped.reversed())),\(fraction < 10 ? "0" : "")\(fraction)"
    }

    /// The text if it has content, else the blank line.
    static func filled(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? blank : trimmed
    }
}
