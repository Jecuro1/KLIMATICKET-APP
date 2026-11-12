import Foundation

/// „Widerspruchsbrief“: the written objection to the automatic renewal of a KlimaTicket Ö that was paid by SEPA direct debit.
///
/// AGB (Stand 1.1.2026): 20.1 – the contract renews by 12 months unless it is objected to in writing within the deadline of the
/// invitation letter; then no new contract comes about and the SEPA mandate is cancelled. 17.4 – the written objection with
/// the holder's own signature goes by post (registered mail is recommended) to the Kundenservice, through the contact form
/// (with a scanned signature) or is handed in at a Servicestelle.
public enum RenewalObjectionLetter {
    /// The clauses the letter is based on.
    public static let clauses = "17.4 und 20.1"

    public enum Eligibility: Equatable, Sendable {
        /// KlimaTicket Ö with a SEPA mandate that renews by itself: the letter makes sense.
        case available
        /// KlimaTicket Ö paid once: it only renews when the Zahlschein is paid – there is nothing to object to.
        case nothingToDo
        /// A regional or own ticket: other conditions apply.
        case notApplicable
    }

    public static func eligibility(for ticket: AdvisorTicket) -> Eligibility {
        guard TicketRights.appliesAGB(to: ticket) else { return .notApplicable }
        return ticket.autoRenews ? .available : .nothingToDo
    }

    /// The hint under the preview. It says only what the AGB say: written, signed, within the deadline of the letter.
    /// Whether the day of posting or the day of arrival counts is not stated there – so the advice is to be early.
    public static let deliveryHint = "Laut AGB (Stand \(TicketRights.agbStandShort), Punkte 17.4 und 20.1) muss der Widerspruch schriftlich und mit deiner eigenhändigen Unterschrift innerhalb der Frist in deinem Brief erfolgen. Ob das Absende- oder das Eingangsdatum zählt, steht dort nicht: Am besten eingeschrieben senden, so früh, dass er sicher vor Fristende ankommt, und den Beleg aufheben."

    /// The other ways the AGB (17.4) allow.
    public static let alternativeWaysHint = "Laut AGB auch möglich: das Kontaktformular auf klimaticket.at/kontakt (mit eingescannter Unterschrift) oder die Abgabe bei einer Servicestelle."

    public struct Input: Equatable, Sendable {
        public var sender: LetterSender
        public var recipient: LetterRecipient
        public var ticketNumber: String
        /// „KlimaTicket Ö Klassik“.
        public var productName: String
        /// Last day of validity.
        public var validUntil: Date
        /// Deadline from the renewal letter; nil until the holder has entered it.
        public var deadline: Date?
        /// „Musterstadt“ – the place in the date line.
        public var place: String
        public var letterDate: Date

        public init(sender: LetterSender, recipient: LetterRecipient = .kundenservice, ticketNumber: String, productName: String,
                    validUntil: Date, deadline: Date?, place: String, letterDate: Date) {
            self.sender = sender
            self.recipient = recipient
            self.ticketNumber = ticketNumber
            self.productName = productName
            self.validUntil = validUntil
            self.deadline = deadline
            self.place = place
            self.letterDate = letterDate
        }
    }

    /// Builds the letter. Fields that are still empty show as blank lines and are listed in `issues`; a deadline that already
    /// passed is an issue as well (the letter would say it is within the deadline).
    public static func make(_ input: Input, now: Date = Date(), calendar: Calendar = .vienna) -> LetterContent {
        var issues: [LetterIssue] = input.sender.missingFields.map { .missing($0) }
        let number = LetterFormat.filled(input.ticketNumber)
        if number == LetterFormat.blank { issues.append(.missing(.ticketNumber)) }

        let deadlineText: String
        if let deadline = input.deadline {
            deadlineText = LetterFormat.date(deadline, calendar: calendar)
            let letterDeadline = LetterDeadline(day: deadline, calendar: calendar)
            if letterDeadline.isPassed(now: now) {
                issues.append(.deadlinePassed)
            } else if letterDeadline.isPassed(now: input.letterDate) {
                issues.append(.letterDateAfterDeadline)   // the letter claims to be within the deadline but is dated after it
            }
        } else {
            deadlineText = LetterFormat.blank
            issues.append(.missing(.deadline))
        }
        if input.recipient.isEmpty { issues.append(.missing(.recipient)) }

        let place = LetterFormat.filled(input.place)
        if place == LetterFormat.blank { issues.append(.missing(.letterPlace)) }

        let sender = input.sender.trimmed
        let blocks: [LetterContent.Block] = [
            .paragraph("hiermit widerspreche ich der automatischen Erneuerung meines Vertrags über das unten genannte KlimaTicket Ö. Mein Vertrag soll mit dem Ablauf der Gültigkeit enden und nicht um weitere zwölf Monate verlängert werden."),
            .facts([
                .init("Produkt", LetterFormat.filled(input.productName)),
                .init("Ticket-/Vertragsnummer", number),
                .init("Gültig bis", LetterFormat.date(input.validUntil, calendar: calendar)),
                .init("Zahlung", "SEPA-Lastschrift"),
            ]),
            .paragraph("Der Widerspruch erfolgt gemäß den Punkten 17.4 und 20.1 der \(TicketRights.agbDative) (Stand \(TicketRights.agbStand)) schriftlich und innerhalb der in Ihrem Einladungsschreiben zur Vertragserneuerung angegebenen Frist, die am \(deadlineText) endet."),
            .paragraph("Nach Punkt 20.1 kommt damit kein neuer Vertrag zustande, und das SEPA-Mandat wird storniert. Bitte buchen Sie für ein Folgeticket nichts von meinem Konto ab."),
            .paragraph("Ich bitte Sie, mir den Eingang dieses Widerspruchs und die Stornierung des SEPA-Mandats schriftlich zu bestätigen."),
        ]
        return LetterContent(
            documentTitle: "Widerspruch gegen die Vertragserneuerung – KlimaTicket Ö",
            senderLines: input.sender.letterLines,
            recipientLines: input.recipient.isEmpty ? [LetterFormat.blank] : input.recipient.lines,
            dateLine: "\(place), \(LetterFormat.date(input.letterDate, calendar: calendar))",
            subject: "Widerspruch gegen die Vertragserneuerung – Ticketnummer \(number)",
            blocks: blocks,
            signatureName: LetterFormat.filled(sender.name),
            issues: issues)
    }
}
