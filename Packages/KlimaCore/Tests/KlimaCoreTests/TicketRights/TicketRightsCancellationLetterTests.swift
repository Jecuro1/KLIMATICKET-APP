import XCTest
@testable import KlimaCore

final class TicketRightsCancellationLetterTests: XCTestCase {
    /// Ticket from 1 March 2026: validity month 6 = August 2026, month 7 = September 2026, month 12 = February 2027.
    private let month6 = TR.date(2026, 8, 15)
    private let month7 = TR.date(2026, 9, 15)
    private let month12 = TR.date(2027, 2, 15)

    private func status(_ ticket: AdvisorTicket = TR.ticket(), at now: Date) -> CancellationLetter.Status {
        CancellationLetter.status(for: ticket, now: now)
    }

    // MARK: Availability follows the advisor

    func testOrdinaryCancellationOnlyFromTheSeventhMonth() {
        XCTAssertEqual(status(at: month6).kind, .notYet)
        XCTAssertEqual(status(at: month6).currentMonth, 6)
        XCTAssertEqual(status(at: month7).kind, .ordinaryPossible)
        XCTAssertEqual(status(at: month7).currentMonth, 7)
        XCTAssertEqual(status(at: month12).kind, .ordinaryPossible)
        XCTAssertEqual(status(at: month12).currentMonth, 12)
        XCTAssertEqual(status(at: month6).possibleFromMonth, AdvisorRules.ordinaryCancellationMonth)
        XCTAssertEqual(status(at: month6).possibleFrom, TR.date(2026, 9, 1, 0), "from which date it is possible")
    }

    func testBeforeStartAndAfterExpiry() {
        XCTAssertEqual(status(at: TR.date(2026, 2, 1)).kind, .beforeStart)
        XCTAssertEqual(status(at: TR.date(2027, 3, 5)).kind, .expired)
        XCTAssertFalse(status(at: TR.date(2026, 2, 1)).canWriteExtraordinary)
        XCTAssertFalse(status(at: TR.date(2027, 3, 5)).canWriteExtraordinary)
    }

    func testStatusFollowsTheAdvisorPolicyAndQuote() {
        let ticket = TR.ticket()
        let months = AdvisorValidityMonths(start: ticket.start, end: ticket.end)
        let advice = TicketAdvisor.cancellationAdvice(ticket: ticket, months: months, pace: 0, now: month7)
        let s = status(at: month7)
        XCTAssertEqual(s.fee, advice.today?.fee)
        XCTAssertEqual(s.fee, 116.7, "AGB Anhang 4: € 116,70 for a Klassik")
        XCTAssertEqual(s.possibleFromMonth, advice.possibleFromMonth)
        XCTAssertEqual(TicketAdvisor.cancellationPolicy(for: ticket), .klimaTicketOe)
    }

    func testFeesMatchTheAGBTable() {
        // AGB Anhang 4: € 116,70 / € 87,50 / € 128,30 / € 99,20 (Klassik, Jugend-Senior-Spezial, Klassik Familie, ermäßigt Familie).
        XCTAssertEqual(status(TR.ticket(price: 1400), at: month7).fee, 116.7)
        XCTAssertEqual(status(TR.ticket(price: 1050), at: month7).fee, 87.5)
        XCTAssertEqual(status(TR.ticket(price: 1540), at: month7).fee, 128.3)
        XCTAssertEqual(status(TR.ticket(price: 1190), at: month7).fee, 99.2)
    }

    func testRegionalAndOtherTicketsRefuse() {
        let tirol = TR.ticket(productID: "tirol-klassik-202604", family: .regional)
        XCTAssertEqual(status(tirol, at: month7).kind, .regionalTicket)
        XCTAssertNil(CancellationLetter.make(TR.cancellation(.ordinary, ticket: tirol), now: month7))
        XCTAssertNil(CancellationLetter.make(TR.cancellation(.extraordinary(.illness, since: TR.date(2026, 9, 1)), ticket: tirol), now: month7))
        let own = TR.ticket(productID: "custom-1", family: .custom)
        XCTAssertEqual(status(own, at: month7).kind, .otherTicket)
        XCTAssertNil(CancellationLetter.make(TR.cancellation(.ordinary, ticket: own), now: month7))
        let heer = TR.ticket(productID: "oe-bundesheer", price: 0)
        XCTAssertEqual(status(heer, at: month7).kind, .otherTicket)
        XCTAssertNil(CancellationLetter.make(TR.cancellation(.ordinary, ticket: heer), now: month7))
    }

    // MARK: Early cancellation never becomes an ordinary letter

    func testNoOrdinaryLetterBeforeTheSeventhMonth() {
        for now in [TR.date(2026, 3, 1), TR.date(2026, 5, 10), TR.date(2026, 8, 31, 23)] {
            XCTAssertNil(CancellationLetter.make(TR.cancellation(.ordinary), now: now), "ordinary letter on \(now)")
        }
        XCTAssertNotNil(CancellationLetter.make(TR.cancellation(.ordinary), now: TR.date(2026, 9, 1, 0)))
    }

    func testNoLetterBeforeStartOrAfterExpiry() {
        XCTAssertNil(CancellationLetter.make(TR.cancellation(.ordinary), now: TR.date(2026, 2, 20)))
        XCTAssertNil(CancellationLetter.make(TR.cancellation(.extraordinary(.unemployment, since: TR.date(2026, 2, 1))), now: TR.date(2026, 2, 20)))
        XCTAssertNil(CancellationLetter.make(TR.cancellation(.ordinary), now: TR.date(2027, 3, 5)))
    }

    func testAnExtraordinaryLetterIsPossibleInTheFirstMonthsAndNeverSaysOrdinary() throws {
        var input = TR.cancellation(.extraordinary(.movedAbroad, since: TR.date(2026, 5, 20)))
        input.letterDate = TR.date(2026, 5, 28)   // dated on the day it is written
        let letter = try XCTUnwrap(CancellationLetter.make(input, now: TR.date(2026, 5, 28)))
        XCTAssertTrue(letter.isReady)
        XCTAssertTrue(letter.subject.hasPrefix("Außerordentliche Kündigung"))
        XCTAssertFalse(letter.plainText.contains("ohne Angabe von Gründen"))
        XCTAssertFalse(letter.plainText.contains("Punkt 17.1"))
    }

    // MARK: Ordinary letter

    func testOrdinaryLetterCitesClause171AndTheAdvisorFee() throws {
        let letter = try XCTUnwrap(CancellationLetter.make(TR.cancellation(.ordinary), now: month7))
        let text = letter.plainText
        XCTAssertTrue(text.contains("Punkt 17.1"))
        XCTAssertTrue(text.contains("ohne Angabe von Gründen"))
        XCTAssertTrue(text.contains("(€ 116,70, ein Zwölftel des Kaufpreises, Punkt 17.1 und Anhang 4)"), "the fee line")
        XCTAssertTrue(text.contains("Kündigungsformular"))
        XCTAssertTrue(text.contains("Servicestelle"), "returns the card at a Servicestelle")
        XCTAssertTrue(text.contains("KT-2026-48 31 07"))
        XCTAssertTrue(text.contains("1. März 2026 bis 28. Februar 2027"))
        XCTAssertTrue(text.contains("schriftlich"))
        XCTAssertEqual(letter.enclosures, ["Kündigungsformular (eigenhändig unterschrieben)"])
        XCTAssertTrue(letter.isReady)
    }

    func testTheFeeLineEqualsTheAdvisorQuote() throws {
        let ticket = TR.ticket(price: 1540)
        let months = AdvisorValidityMonths(start: ticket.start, end: ticket.end)
        let fee = try XCTUnwrap(TicketAdvisor.cancellationAdvice(ticket: ticket, months: months, pace: 0, now: month12).today?.fee)
        let letter = try XCTUnwrap(CancellationLetter.make(TR.cancellation(.ordinary, ticket: ticket), now: month12))
        XCTAssertTrue(letter.plainText.contains(LetterFormat.euro(fee)))
        XCTAssertTrue(letter.plainText.contains("€ 128,30"))
    }

    func testPaymentVariantsOfTheOrdinaryLetter() throws {
        let single = try XCTUnwrap(CancellationLetter.make(TR.cancellation(.ordinary), now: month7))
        XCTAssertTrue(single.plainText.contains("Einmalzahlung im Voraus"))
        XCTAssertTrue(single.plainText.contains("abzüglich des Kündigungsentgelts auf folgendes Konto"))
        XCTAssertTrue(single.plainText.contains("IBAN: \(LetterFormat.handwritingBlank)"), "the IBAN is written by hand")

        let monthly = try XCTUnwrap(CancellationLetter.make(TR.cancellation(.ordinary, ticket: TR.ticket(monthly: true)), now: month7))
        XCTAssertTrue(monthly.plainText.contains("SEPA-Lastschrift (monatliche Abbuchung)"))
        XCTAssertTrue(monthly.plainText.contains("als letzten Monatsbetrag ab"))
        XCTAssertFalse(monthly.plainText.contains("IBAN"))
        XCTAssertTrue(monthly.isReady, "the handwritten IBAN line is no missing field")
    }

    func testKennenlernAktionCancelsFromTheSecondMonthWithoutFee() throws {
        let ticket = TR.ticket(start: TR.date(2026, 5, 1, 0))
        XCTAssertEqual(TicketAdvisor.cancellationPolicy(for: ticket), .kennenlern)
        XCTAssertEqual(status(ticket, at: TR.date(2026, 5, 20)).kind, .notYet)
        XCTAssertEqual(status(ticket, at: TR.date(2026, 6, 10)).kind, .ordinaryPossible)
        XCTAssertEqual(status(ticket, at: TR.date(2026, 6, 10)).fee, 0)
        let letter = try XCTUnwrap(CancellationLetter.make(TR.cancellation(.ordinary, ticket: ticket), now: TR.date(2026, 6, 10)))
        XCTAssertTrue(letter.plainText.contains("Kennenlern-Aktion 2026"))
        XCTAssertTrue(letter.plainText.contains("Ein Kündigungsentgelt fällt dabei nicht an."))
        XCTAssertFalse(letter.plainText.contains("Punkt 17.1"), "the Kennenlern terms are not an AGB clause")
    }

    // MARK: Extraordinary reasons (AGB 17.2)

    func testExtraordinaryVariantsNameTheReasonTheWindowAndTheProof() throws {
        let since = TR.date(2026, 10, 20)
        let now = TR.date(2026, 11, 12)
        let expectations: [(CancellationLetter.Reason, String, String)] = [
            (.movedAbroad, "meines Umzugs von Österreich in das Ausland", "Nachweis der neuen Adresse im Ausland"),
            (.illness, "einer Erkrankung über einen Zeitraum von drei Monaten oder mehr", "Ärztliches Attest"),
            (.unemployment, "des Eintritts von Arbeitslosigkeit", "Arbeitslosenbestätigung"),
        ]
        for (reason, sentence, proof) in expectations {
            let letter = try XCTUnwrap(CancellationLetter.make(TR.cancellation(.extraordinary(reason, since: since)), now: now))
            let text = letter.plainText
            XCTAssertTrue(text.contains("außerordentlich gemäß Punkt 17.2"), "\(reason)")
            XCTAssertTrue(text.contains(sentence), "\(reason)")
            XCTAssertTrue(text.contains("Als Nachweis liegt bei: \(proof)."), "\(reason): Nachweis liegt bei")
            XCTAssertTrue(text.contains("innerhalb von vier Wochen nach Vorliegen des Kündigungsgrundes, also bis spätestens 17. November 2026"), "\(reason): the window")
            XCTAssertTrue(text.contains("Grund liegt vor seit: 20. Oktober 2026"))
            XCTAssertTrue(text.contains("entfällt das Kündigungsentgelt"))
            XCTAssertTrue(text.contains("Servicestelle"))
            XCTAssertEqual(letter.enclosures, [proof, "Kündigungsformular (eigenhändig unterschrieben)"])
            XCTAssertTrue(letter.isReady, "\(reason)")
            XCTAssertFalse(text.contains("Kündigungsentgelt von einem Monatsbetrag"), "no fee line for an extraordinary cancellation")
        }
    }

    func testTheFourWeekWindow() {
        let window = FilingWindow(since: TR.date(2026, 10, 20))
        XCTAssertEqual(window.lastDay, TR.date(2026, 11, 17, 0))
        XCTAssertEqual(window.status(now: TR.date(2026, 10, 19)), .notYet)
        XCTAssertEqual(window.status(now: TR.date(2026, 10, 20)), .open(days: 28))
        XCTAssertEqual(window.status(now: TR.date(2026, 11, 17, 20)), .open(days: 0))
        XCTAssertEqual(window.status(now: TR.date(2026, 11, 18)), .closed(days: 1))
    }

    func testReasonDateIsRequiredAndMustFitTheWindow() throws {
        let now = TR.date(2026, 11, 12)
        let missing = try XCTUnwrap(CancellationLetter.make(TR.cancellation(.extraordinary(.illness, since: nil)), now: now))
        XCTAssertEqual(missing.missingFields, [.reasonDate])
        XCTAssertFalse(missing.isReady)

        let closed = try XCTUnwrap(CancellationLetter.make(TR.cancellation(.extraordinary(.illness, since: TR.date(2026, 10, 1))), now: now))
        XCTAssertEqual(closed.issues, [.filingWindowClosed], "more than four weeks ago")

        let future = try XCTUnwrap(CancellationLetter.make(TR.cancellation(.extraordinary(.illness, since: TR.date(2026, 11, 20))), now: now))
        XCTAssertEqual(future.issues, [.reasonInFuture])
    }

    func testALetterDatedAfterTheFilingWindowIsBlocked() throws {
        // Reason since 20 Oct: the last day is 17 Nov. Today is 12 Nov (open), but the letter is dated 18 Nov.
        var input = TR.cancellation(.extraordinary(.illness, since: TR.date(2026, 10, 20)))
        input.letterDate = TR.date(2026, 11, 18)
        let late = try XCTUnwrap(CancellationLetter.make(input, now: TR.date(2026, 11, 12)))
        XCTAssertEqual(late.issues, [.letterDateAfterDeadline])
        XCTAssertFalse(late.isReady)
        input.letterDate = TR.date(2026, 11, 17)
        XCTAssertTrue(try XCTUnwrap(CancellationLetter.make(input, now: TR.date(2026, 11, 12))).isReady, "the last day itself still counts")
    }

    func testExtraordinaryPaymentVariants() throws {
        let since = TR.date(2026, 11, 1)
        let now = TR.date(2026, 11, 12)
        let single = try XCTUnwrap(CancellationLetter.make(TR.cancellation(.extraordinary(.unemployment, since: since)), now: now))
        XCTAssertTrue(single.plainText.contains("ohne Abzug eines Kündigungsentgelts auf folgendes Konto"))
        let monthly = try XCTUnwrap(CancellationLetter.make(
            TR.cancellation(.extraordinary(.unemployment, since: since), ticket: TR.ticket(monthly: true)), now: now))
        XCTAssertTrue(monthly.plainText.contains("keine Raten mehr ab"))
        XCTAssertFalse(monthly.plainText.contains("IBAN"))
    }

    // MARK: Hygiene

    func testNoPlaceholderLeftInAnyFinishedLetter() throws {
        let kinds: [(CancellationLetter.Kind, Date)] = [
            (.ordinary, month7),
            (.extraordinary(.movedAbroad, since: TR.date(2026, 11, 1)), TR.date(2026, 11, 12)),
            (.extraordinary(.illness, since: TR.date(2026, 11, 1)), TR.date(2026, 11, 12)),
            (.extraordinary(.unemployment, since: TR.date(2026, 11, 1)), TR.date(2026, 11, 12)),
        ]
        for (kind, now) in kinds {
            for monthly in [false, true] {
                let letter = try XCTUnwrap(CancellationLetter.make(TR.cancellation(kind, ticket: TR.ticket(monthly: monthly)), now: now))
                var text = letter.plainText.replacingOccurrences(of: "IBAN: \(LetterFormat.handwritingBlank)", with: "IBAN: –")
                text = text.replacingOccurrences(of: "Anlagen:", with: "")
                for mark in TR.placeholderMarks {
                    XCTAssertFalse(text.contains(mark), "\(mark) in \(kind) / monthly \(monthly)")
                }
                XCTAssertFalse(text.contains(LetterFormat.blank), "\(kind) / monthly \(monthly)")
            }
        }
    }

    func testIllnessLetterNamesNoDiagnosis() throws {
        let letter = try XCTUnwrap(CancellationLetter.make(
            TR.cancellation(.extraordinary(.illness, since: TR.date(2026, 11, 1))), now: TR.date(2026, 11, 12)))
        // Only the duration the AGB name, no medical detail.
        XCTAssertTrue(letter.plainText.contains("Erkrankung über einen Zeitraum von drei Monaten oder mehr"))
        XCTAssertEqual(CancellationLetter.Reason.allCases.count, 3)
    }

    func testMissingSenderFieldsAreListed() throws {
        let letter = try XCTUnwrap(CancellationLetter.make(TR.cancellation(.ordinary, sender: LetterSender(name: "Maria Beispiel"), number: ""), now: month7))
        XCTAssertEqual(letter.missingFields, [.street, .postcode, .place, .ticketNumber, .letterPlace])
    }
}
