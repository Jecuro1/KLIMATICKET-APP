import XCTest
@testable import KlimaCore

/// Fixtures of the Ticket-Schreiben tests. All persons and addresses are obviously fictional.
enum TR {
    static let cal = Calendar.vienna

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static let maria = LetterSender(name: "Maria Beispiel", street: "Musterweg 1", postcode: "1234", place: "Musterstadt")

    /// A KlimaTicket Ö Klassik started 1 March 2026 (validity month 1 = March 2026, month 7 = September 2026, month 12 = February 2027).
    static func ticket(productID: String = "oe-klassik", family: TicketFamily = .oe, variant: TicketVariant = .klassik,
                       price: Double = 1400, start: Date? = nil, monthly: Bool = false, autoRenews: Bool = true,
                       name: String = "KlimaTicket Ö Klassik") -> AdvisorTicket {
        let s = start ?? date(2026, 3, 1, 0)
        return AdvisorTicket(productID: productID, name: name, family: family, variant: variant, price: price, start: s,
                             end: TicketPeriod.standardEnd(for: s, calendar: cal), isMonthlyPayment: monthly, autoRenews: autoRenews)
    }

    static let ticketNumber = "KT-2026-48 31 07"

    static func objection(deadline: Date? = date(2027, 1, 15), sender: LetterSender = maria,
                          recipient: LetterRecipient = .kundenservice, number: String = ticketNumber) -> RenewalObjectionLetter.Input {
        RenewalObjectionLetter.Input(sender: sender, recipient: recipient, ticketNumber: number, productName: "KlimaTicket Ö Klassik",
                                     validUntil: ticket().end, deadline: deadline, place: sender.place, letterDate: date(2026, 11, 12))
    }

    static func cancellation(_ kind: CancellationLetter.Kind, ticket t: AdvisorTicket? = nil, sender: LetterSender = maria,
                             number: String = ticketNumber) -> CancellationLetter.Input {
        CancellationLetter.Input(ticket: t ?? ticket(), ticketNumber: number, sender: sender, kind: kind, place: sender.place,
                                 letterDate: date(2026, 11, 12))
    }

    /// Characters that would mean a template placeholder was left in a finished letter.
    static let placeholderMarks = ["{", "}", "%@", "%d", "<", ">", "[", "]", "$("]
}
