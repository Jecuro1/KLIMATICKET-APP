import XCTest
@testable import KlimaCore

final class TicketRightsObjectionLetterTests: XCTestCase {
    private let now = TR.date(2026, 11, 12)

    /// The letter of the demo ticket, word for word. A change to the text must be a conscious one: review it against the AGB
    /// (clauses 17.4 and 20.1) and update this text together with docs/TICKET_LETTERS.md.
    func testGoldenLetterOfTheDemoTicket() {
        let letter = RenewalObjectionLetter.make(TR.objection(), now: now)
        let expected = """
        Maria Beispiel
        Musterweg 1
        1234 Musterstadt

        KlimaTicket Kundenservice
        Postfach 100
        1020 Wien

        Musterstadt, 12. November 2026

        Widerspruch gegen die Vertragserneuerung – Ticketnummer KT-2026-48 31 07

        Sehr geehrte Damen und Herren,

        hiermit widerspreche ich der automatischen Erneuerung meines Vertrags über das unten genannte KlimaTicket Ö. Mein Vertrag soll mit dem Ablauf der Gültigkeit enden und nicht um weitere zwölf Monate verlängert werden.

        Produkt: KlimaTicket Ö Klassik
        Ticket-/Vertragsnummer: KT-2026-48 31 07
        Gültig bis: 28. Februar 2027
        Zahlung: SEPA-Lastschrift

        Der Widerspruch erfolgt gemäß den Punkten 17.4 und 20.1 der Allgemeinen Geschäftsbedingungen für den Kauf des KlimaTicket Ö (Stand 1. Jänner 2026) schriftlich und innerhalb der in Ihrem Einladungsschreiben zur Vertragserneuerung angegebenen Frist, die am 15. Jänner 2027 endet.

        Nach Punkt 20.1 kommt damit kein neuer Vertrag zustande, und das SEPA-Mandat wird storniert. Bitte buchen Sie für ein Folgeticket nichts von meinem Konto ab.

        Ich bitte Sie, mir den Eingang dieses Widerspruchs und die Stornierung des SEPA-Mandats schriftlich zu bestätigen.

        Mit freundlichen Grüßen


        Maria Beispiel
        """
        XCTAssertEqual(letter.plainText, expected)
        XCTAssertTrue(letter.isReady)
        XCTAssertEqual(letter.documentTitle, "Widerspruch gegen die Vertragserneuerung – KlimaTicket Ö")
    }

    func testStatesTicketNumberEndDateAndDeadline() {
        let text = RenewalObjectionLetter.make(TR.objection(), now: now).plainText
        XCTAssertTrue(text.contains("KT-2026-48 31 07"))
        XCTAssertTrue(text.contains("28. Februar 2027"), "the end of validity")
        XCTAssertTrue(text.contains("15. Jänner 2027"), "the deadline from the renewal letter")
        XCTAssertTrue(text.contains("widerspreche"))
        XCTAssertTrue(text.contains("schriftlich zu bestätigen"), "asks for written confirmation")
        XCTAssertTrue(text.contains("KlimaTicket Ö Klassik"))
    }

    func testNoPlaceholderLeftInAFinishedLetter() {
        let text = RenewalObjectionLetter.make(TR.objection(), now: now).plainText
        for mark in TR.placeholderMarks {
            XCTAssertFalse(text.contains(mark), "\(mark) in the finished letter")
        }
        XCTAssertFalse(text.contains(LetterFormat.blank), "no blank line when everything is filled in")
    }

    func testEmptyFieldsShowBlanksAndAreListed() {
        let letter = RenewalObjectionLetter.make(TR.objection(deadline: nil, sender: LetterSender(), number: ""), now: now)
        XCTAssertFalse(letter.isReady)
        XCTAssertEqual(letter.missingFields, [.name, .street, .postcode, .place, .ticketNumber, .deadline, .letterPlace])
        XCTAssertTrue(letter.plainText.contains(LetterFormat.blank))
        XCTAssertEqual(letter.senderLines, [LetterFormat.blank, LetterFormat.blank, LetterFormat.blank])
    }

    func testAPassedDeadlineBlocksTheLetter() {
        let letter = RenewalObjectionLetter.make(TR.objection(deadline: TR.date(2026, 11, 11)), now: now)
        XCTAssertEqual(letter.issues, [.deadlinePassed])
        XCTAssertFalse(letter.isReady)
    }

    func testTheDeadlineDayItselfStillCounts() {
        let letter = RenewalObjectionLetter.make(TR.objection(deadline: TR.date(2026, 11, 12, 0)), now: TR.date(2026, 11, 12, 18))
        XCTAssertTrue(letter.isReady)
    }

    func testALetterDatedAfterTheDeadlineIsBlocked() {
        // The deadline (15 Jan 2027) is still ahead today, but the letter is dated the day after it.
        var input = TR.objection()
        input.letterDate = TR.date(2027, 1, 16)
        let late = RenewalObjectionLetter.make(input, now: now)
        XCTAssertEqual(late.issues, [.letterDateAfterDeadline])
        XCTAssertFalse(late.isReady)
        input.letterDate = TR.date(2027, 1, 15, 20)
        XCTAssertTrue(RenewalObjectionLetter.make(input, now: now).isReady, "dated on the deadline day: still within it")
    }

    func testAnEditedRecipientIsPrinted() {
        let recipient = LetterRecipient.parse("Beispiel Kundenservice GmbH\n\n Musterstraße 5 \n1030 Wien")
        let letter = RenewalObjectionLetter.make(TR.objection(recipient: recipient), now: now)
        XCTAssertEqual(letter.recipientLines, ["Beispiel Kundenservice GmbH", "Musterstraße 5", "1030 Wien"])
        XCTAssertTrue(letter.isReady)
    }

    func testAnEmptyRecipientIsAnIssue() {
        let letter = RenewalObjectionLetter.make(TR.objection(recipient: LetterRecipient(lines: [])), now: now)
        XCTAssertEqual(letter.missingFields, [.recipient])
    }

    // MARK: Who gets the letter

    func testOnlyAKlimaTicketOeWithAutoRenewalGetsTheLetter() {
        XCTAssertEqual(RenewalObjectionLetter.eligibility(for: TR.ticket(autoRenews: true)), .available)
        XCTAssertEqual(RenewalObjectionLetter.eligibility(for: TR.ticket(autoRenews: false)), .nothingToDo)
        XCTAssertEqual(RenewalObjectionLetter.eligibility(for: TR.ticket(productID: "tirol-klassik-202604", family: .regional, autoRenews: true)),
                       .notApplicable)
        XCTAssertEqual(RenewalObjectionLetter.eligibility(for: TR.ticket(productID: "x", family: .custom, autoRenews: true)), .notApplicable)
        for id in ["oe-bundesheer", "oe-zivildienst", "oe-freiwilligendienst", "oe-18-gratis", "oe-jobticket"] {
            XCTAssertEqual(RenewalObjectionLetter.eligibility(for: TR.ticket(productID: id, price: 0, autoRenews: true)), .notApplicable, id)
        }
    }

    func testTheHintNamesTheClausesAndTheVersion() {
        let hint = RenewalObjectionLetter.deliveryHint
        XCTAssertTrue(hint.contains("17.4 und 20.1"))
        XCTAssertTrue(hint.contains("1.1.2026"))
        XCTAssertTrue(hint.contains("eingeschrieben"))
        XCTAssertTrue(hint.contains("Beleg"))
    }

    // MARK: Recipient constant

    func testTheKundenserviceAddressIsTheOneFromTheAGB() {
        XCTAssertEqual(LetterRecipient.kundenservice.lines, ["KlimaTicket Kundenservice", "Postfach 100", "1020 Wien"])
        XCTAssertTrue(LetterRecipient.kundenservice.isKundenservice)
        XCTAssertEqual(LetterRecipient.parse(LetterRecipient.kundenservice.text), .kundenservice)
        XCTAssertFalse(LetterRecipient.parse("Anderswo 1\n1010 Wien").isKundenservice)
        XCTAssertEqual(LetterRecipient.placeholder, "Adresse laut deinem Verlängerungsbrief")
    }

    // MARK: Formatting

    func testDatesAndAmountsAreAustrian() {
        XCTAssertEqual(LetterFormat.date(TR.date(2027, 1, 5)), "5. Jänner 2027")
        XCTAssertEqual(LetterFormat.date(TR.date(2026, 3, 1, 0)), "1. März 2026")
        XCTAssertEqual(LetterFormat.euro(116.7), "€ 116,70")
        XCTAssertEqual(LetterFormat.euro(1400), "€ 1.400,00")
        XCTAssertEqual(LetterFormat.euro(0.05), "€ 0,05")
        XCTAssertEqual(LetterFormat.euro(1_234_567.8), "€ 1.234.567,80")
        // A broken value must not crash the letter (Int(.nan) traps).
        XCTAssertEqual(LetterFormat.euro(.nan), "€ –")
        XCTAssertEqual(LetterFormat.euro(.infinity), "€ –")
    }

    func testAnEarlierAGBVersionIsMentionedForTicketsThatBeganBefore2026() {
        XCTAssertNotNil(TicketRights.earlierVersionNote(ticketStart: TR.date(2025, 12, 31, 23)))
        XCTAssertTrue(TicketRights.earlierVersionNote(ticketStart: TR.date(2025, 6, 1))?.contains("1.1.2026") == true)
        XCTAssertNil(TicketRights.earlierVersionNote(ticketStart: TR.date(2026, 1, 1, 0)))
        XCTAssertNil(TicketRights.earlierVersionNote(ticketStart: TR.date(2026, 3, 1)))
    }
}
