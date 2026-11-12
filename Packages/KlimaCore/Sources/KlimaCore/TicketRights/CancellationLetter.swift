import Foundation

/// „Kündigungsschreiben“ of a KlimaTicket Ö – ordinary (from the 7th validity month, fee = one monthly amount, AGB 17.1) or
/// extraordinary (moving abroad, illness of three months or more, unemployment; no fee; ticket and form within four weeks
/// after the reason arose, AGB 17.2).
///
/// What counts is decided by the Ticket-Ratgeber (`TicketAdvisor.cancellationPolicy` and the quote of
/// `cancellationAdvice`) – the letters never recompute the rules or the fee. AGB 17.1 asks for a signed Kündigungsformular
/// and the proven return of the card at a Servicestelle: the letter accompanies them, it does not replace them.
public enum CancellationLetter {
    public static let ordinaryClause = "17.1"
    public static let extraordinaryClause = "17.2"

    // MARK: Reasons (AGB 17.2)

    public enum Reason: String, CaseIterable, Sendable, Hashable, Identifiable {
        case movedAbroad, illness, unemployment

        public var id: String { rawValue }

        /// Picker title.
        public var title: String {
            switch self {
            case .movedAbroad: "Umzug ins Ausland"
            case .illness: "Krankheit ab 3 Monaten"
            case .unemployment: "Arbeitslosigkeit"
            }
        }

        /// What the holder has to attach (AGB 17.2).
        public var proof: String {
            switch self {
            case .movedAbroad: "Nachweis der neuen Adresse im Ausland"
            case .illness: "Ärztliches Attest"
            case .unemployment: "Arbeitslosenbestätigung"
            }
        }

        /// A hint for the date picker.
        public var sinceHint: String {
            switch self {
            case .movedAbroad: "Ab wann wohnst du im Ausland?"
            case .illness: "Ab wann dauert die Krankheit drei Monate?"
            case .unemployment: "Ab wann bist du arbeitslos?"
            }
        }

        public var symbol: String {
            switch self {
            case .movedAbroad: "airplane.departure"
            case .illness: "cross.case.fill"
            case .unemployment: "briefcase.fill"
            }
        }

        /// The grounds as the letter words them (no medical detail).
        var sentence: String {
            switch self {
            case .movedAbroad: "meines Umzugs von Österreich in das Ausland"
            case .illness: "einer Erkrankung über einen Zeitraum von drei Monaten oder mehr"
            case .unemployment: "des Eintritts von Arbeitslosigkeit"
            }
        }

        var factValue: String {
            switch self {
            case .movedAbroad: "Umzug von Österreich in das Ausland"
            case .illness: "Erkrankung über einen Zeitraum von drei Monaten oder mehr"
            case .unemployment: "Eintritt von Arbeitslosigkeit"
            }
        }
    }

    public enum Kind: Equatable, Sendable {
        /// Without a reason, from the 7th validity month (AGB 17.1).
        case ordinary
        /// With a reason, no fee (AGB 17.2); `since` = the day the reason arose, nil until the holder has chosen it.
        case extraordinary(Reason, since: Date?)
    }

    // MARK: Status

    /// What the screen can offer for a ticket right now.
    public struct Status: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// KlimaTicket Ö in or after its 7th validity month (2nd for the Kennenlern-Aktion): an ordinary letter is possible.
            case ordinaryPossible
            /// KlimaTicket Ö before that month: only the extraordinary reasons apply.
            case notYet
            case beforeStart
            case expired
            /// Regional ticket: other conditions apply.
            case regionalTicket
            /// Own ticket or a KlimaTicket Ö under other conditions (Bundesheer, Jobticket …).
            case otherTicket
        }

        public var kind: Kind
        public var currentMonth: Int
        public var possibleFromMonth: Int
        /// First day of the month from which an ordinary cancellation is possible.
        public var possibleFrom: Date
        /// The cancellation fee: one monthly amount from the advisor's quote (0 for the Kennenlern-Aktion).
        public var fee: Double
        public var isKennenlern: Bool

        public var canWriteOrdinary: Bool { kind == .ordinaryPossible }
        /// The extraordinary reasons need a running ticket.
        public var canWriteExtraordinary: Bool { kind == .ordinaryPossible || kind == .notYet }
    }

    public static func status(for ticket: AdvisorTicket, now: Date = Date(), calendar: Calendar = .vienna) -> Status {
        let months = AdvisorValidityMonths(start: ticket.start, end: ticket.end, calendar: calendar)
        let advice = TicketAdvisor.cancellationAdvice(ticket: ticket, months: months, pace: 0, now: now)
        let isKennenlern = advice.policy == .kennenlern
        func result(_ kind: Status.Kind) -> Status {
            Status(kind: kind, currentMonth: advice.currentMonth, possibleFromMonth: advice.possibleFromMonth,
                   possibleFrom: advice.possibleFrom, fee: advice.today?.fee ?? advice.fee, isKennenlern: isKennenlern)
        }
        guard TicketRights.appliesAGB(to: ticket) else {
            return result(ticket.family == .regional ? .regionalTicket : .otherTicket)
        }
        switch advice.verdict {
        case .expired: return result(.expired)
        case .beforeStart: return result(.beforeStart)
        case .notYet: return result(.notYet)
        case .keep, .consider, .notWorthwhile: return result(.ordinaryPossible)
        case .unsupported: return result(.otherTicket)
        }
    }

    // MARK: Letter

    public struct Input: Equatable, Sendable {
        public var ticket: AdvisorTicket
        public var ticketNumber: String
        public var sender: LetterSender
        public var recipient: LetterRecipient
        public var kind: Kind
        public var place: String
        public var letterDate: Date

        public init(ticket: AdvisorTicket, ticketNumber: String, sender: LetterSender, recipient: LetterRecipient = .kundenservice,
                    kind: Kind, place: String, letterDate: Date) {
            self.ticket = ticket
            self.ticketNumber = ticketNumber
            self.sender = sender
            self.recipient = recipient
            self.kind = kind
            self.place = place
            self.letterDate = letterDate
        }
    }

    /// Builds the letter, or nil when this kind of letter is not possible for the ticket at `now`: not a KlimaTicket Ö, not
    /// running, or an ordinary cancellation before the 7th validity month. An ordinary letter never exists before that.
    public static func make(_ input: Input, now: Date = Date(), calendar: Calendar = .vienna) -> LetterContent? {
        let status = status(for: input.ticket, now: now, calendar: calendar)
        var issues: [LetterIssue] = input.sender.missingFields.map { .missing($0) }
        let number = LetterFormat.filled(input.ticketNumber)
        if number == LetterFormat.blank { issues.append(.missing(.ticketNumber)) }
        if input.recipient.isEmpty { issues.append(.missing(.recipient)) }
        let place = LetterFormat.filled(input.place)
        if place == LetterFormat.blank { issues.append(.missing(.letterPlace)) }

        let ticket = input.ticket
        let paymentFact = ticket.isMonthlyPayment ? "SEPA-Lastschrift (monatliche Abbuchung)" : "Einmalzahlung im Voraus"
        var facts: [LetterContent.Fact] = [
            .init("Produkt", LetterFormat.filled(ticket.name)),
            .init("Ticket-/Vertragsnummer", number),
            .init("Gültig", "\(LetterFormat.date(ticket.start, calendar: calendar)) bis \(LetterFormat.date(ticket.end, calendar: calendar))"),
            .init("Zahlung", paymentFact),
        ]
        let agb = "\(TicketRights.agbDative) (Stand \(TicketRights.agbStand))"
        var blocks: [LetterContent.Block] = []
        var enclosures: [String] = []
        let subject: String
        let title: String

        switch input.kind {
        case .ordinary:
            guard status.canWriteOrdinary else { return nil }
            title = "Kündigung des KlimaTicket Ö"
            subject = "Kündigung meines KlimaTicket Ö – Ticketnummer \(number)"
            let clause = status.isKennenlern
                ? "im Rahmen der Kennenlern-Aktion 2026 (gebührenfreie Kündigung ab dem zweiten Gültigkeitsmonat)"
                : "gemäß Punkt \(ordinaryClause) der \(agb) ohne Angabe von Gründen"
            blocks.append(.paragraph("hiermit kündige ich mein unten genanntes KlimaTicket Ö schriftlich \(clause)."))
            blocks.append(.facts(facts))
            if status.isKennenlern {
                blocks.append(.paragraph("Ein Kündigungsentgelt fällt dabei nicht an."))
            } else {
                blocks.append(.paragraph("Das Kündigungsentgelt von einem Monatsbetrag (\(LetterFormat.euro(status.fee)), ein Zwölftel des Kaufpreises, Punkt \(ordinaryClause)) ist mir bekannt."))
            }
            if ticket.isMonthlyPayment {
                blocks.append(.paragraph(status.isKennenlern
                    ? "Bitte buchen Sie für die nicht angefangenen Gültigkeitsmonate keine Raten mehr ab."
                    : "Bitte buchen Sie dieses Entgelt als letzten Monatsbetrag ab und für die nicht angefangenen Gültigkeitsmonate keine Raten mehr."))
            } else {
                blocks.append(.paragraph(status.isKennenlern
                    ? "Bitte überweisen Sie mir für jeden nicht angefangenen Gültigkeitsmonat den entsprechenden Monatsbetrag auf folgendes Konto:"
                    : "Bitte überweisen Sie mir für jeden nicht angefangenen Gültigkeitsmonat den entsprechenden Monatsbetrag abzüglich des Kündigungsentgelts auf folgendes Konto:"))
                blocks.append(.facts([.init("IBAN", LetterFormat.handwritingBlank)]))
            }
            blocks.append(.paragraph("Meine Karte gebe ich gemeinsam mit diesem Schreiben und dem eigenhändig unterschriebenen Kündigungsformular nachweislich bei einer Servicestelle zurück."))
            blocks.append(.paragraph("Bitte bestätigen Sie mir die Kündigung schriftlich."))
            enclosures = ["Kündigungsformular (eigenhändig unterschrieben)"]

        case .extraordinary(let reason, let since):
            guard status.canWriteExtraordinary else { return nil }
            title = "Außerordentliche Kündigung des KlimaTicket Ö"
            subject = "Außerordentliche Kündigung – Ticketnummer \(number)"
            facts.append(.init("Kündigungsgrund", reason.factValue))
            let deadlineText: String
            if let since {
                facts.append(.init("Grund liegt vor seit", LetterFormat.date(since, calendar: calendar)))
                let window = FilingWindow(since: since, calendar: calendar)
                deadlineText = LetterFormat.date(window.lastDay, calendar: calendar)
                switch window.status(now: now) {
                case .notYet: issues.append(.reasonInFuture)
                case .closed: issues.append(.filingWindowClosed)
                case .open: break
                }
            } else {
                facts.append(.init("Grund liegt vor seit", LetterFormat.blank))
                deadlineText = LetterFormat.blank
                issues.append(.missing(.reasonDate))
            }
            blocks.append(.paragraph("hiermit kündige ich mein unten genanntes KlimaTicket Ö außerordentlich gemäß Punkt \(extraordinaryClause) der \(agb) wegen \(reason.sentence)."))
            blocks.append(.facts(facts))
            blocks.append(.paragraph("Ich gebe mein Ticket gemeinsam mit dem eigenhändig unterschriebenen Kündigungsformular innerhalb von vier Wochen nach Vorliegen des Kündigungsgrundes, also bis spätestens \(deadlineText), nachweislich bei einer Servicestelle ab."))
            blocks.append(.paragraph("Als Nachweis liegt bei: \(reason.proof)."))
            blocks.append(.paragraph("Bei der außerordentlichen Kündigung entfällt das Kündigungsentgelt (Punkt \(extraordinaryClause))."))
            if ticket.isMonthlyPayment {
                blocks.append(.paragraph("Bitte buchen Sie für die nicht angefangenen Gültigkeitsmonate keine Raten mehr ab."))
            } else {
                blocks.append(.paragraph("Bitte erstatten Sie mir die Monatsbeträge der nicht angefangenen Gültigkeitsmonate ohne Abzug eines Kündigungsentgelts auf folgendes Konto:"))
                blocks.append(.facts([.init("IBAN", LetterFormat.handwritingBlank)]))
            }
            blocks.append(.paragraph("Bitte bestätigen Sie mir die Kündigung schriftlich."))
            enclosures = [reason.proof, "Kündigungsformular (eigenhändig unterschrieben)"]
        }

        return LetterContent(
            documentTitle: title,
            senderLines: input.sender.letterLines,
            recipientLines: input.recipient.isEmpty ? [LetterFormat.blank] : input.recipient.lines,
            dateLine: "\(place), \(LetterFormat.date(input.letterDate, calendar: calendar))",
            subject: subject,
            blocks: blocks,
            signatureName: LetterFormat.filled(input.sender.trimmed.name),
            enclosures: enclosures,
            issues: issues)
    }
}
