import XCTest
@testable import KlimaCore

// MARK: data – the calendar files, the Monatsübersicht, the Jahresbilanz text and the range (docs/DATA_HUB.md §2).

private func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    var c = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    c.timeZone = Calendar.vienna.timeZone
    return Calendar.vienna.date(from: c)!
}

private func trip(_ date: Date, _ from: String = "Innsbruck Hbf", _ to: String = "St. Anton am Arlberg", km: Double = 100,
                  fare: Double = 20, roundTrip: Bool = false, mode: TransportMode = .train, journey: UUID? = nil) -> TripRecord {
    TripRecord(date: date, fromName: from, toName: to, mode: mode, distanceKm: km, fareEUR: fare, isRoundTrip: roundTrip,
               journeyID: journey)
}

private let stamp = day(2026, 11, 19, 18, 3)

final class DataHubICSTests: XCTestCase {
    private func assertWellFormed(_ ics: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR\r\n"), file: file, line: line)
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR\r\n"), file: file, line: line)
        XCTAssertFalse(ics.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "only CRLF line ends", file: file, line: line)
        for physical in ics.components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(physical.utf8.count, 75, physical, file: file, line: line)
        }
    }

    /// Unfolds RFC 5545 content lines (a CRLF followed by a space continues the line).
    private func unfolded(_ ics: String) -> [String] {
        ics.replacingOccurrences(of: "\r\n ", with: "").components(separatedBy: "\r\n")
    }

    func testAllDayWithoutDurationTimedWithIt() {
        let withTime = trip(day(2026, 11, 19, 7, 12))
        let withoutTime = trip(day(2026, 11, 20, 18, 30), roundTrip: true)
        let ics = DataHubICS.trips([withoutTime, withTime], durations: [withTime.id: 75], stamp: stamp)
        assertWellFormed(ics)
        let lines = unfolded(ics)
        XCTAssertTrue(lines.contains("DTSTART:20261119T061200Z"))
        XCTAssertTrue(lines.contains("DTEND:20261119T072700Z"))
        XCTAssertTrue(lines.contains("DTSTART;VALUE=DATE:20261120"))
        XCTAssertTrue(lines.contains("DTEND;VALUE=DATE:20261121"))
        XCTAssertTrue(lines.contains("SUMMARY:Zug: Innsbruck Hbf → St. Anton am Arlberg"))
        XCTAssertTrue(lines.contains("SUMMARY:Zug: Innsbruck Hbf → St. Anton am Arlberg (hin und retour)"))
        XCTAssertEqual(lines.filter { $0 == "BEGIN:VEVENT" }.count, 2)
        // Sorted by date: the 19th comes first.
        XCTAssertLessThan(lines.firstIndex(of: "DTSTART:20261119T061200Z")!, lines.firstIndex(of: "DTSTART;VALUE=DATE:20261120")!)
        XCTAssertTrue(lines.contains("UID:trip-\(withTime.id.uuidString.lowercased())@klimabilanz"))
    }

    func testEscapingAndFoldingWithUmlauts() {
        let odd = trip(day(2026, 12, 3, 9), "Wien Hbf, Bahnsteig 7; Süd", "Ötztal Bahnhof – Längenfeld über Sölden und Obergurgl\\Hochgurgl",
                       mode: .bus)
        let ics = DataHubICS.trips([odd], stamp: stamp)
        assertWellFormed(ics)
        let summary = unfolded(ics).first { $0.hasPrefix("SUMMARY:") }!
        XCTAssertEqual(summary, "SUMMARY:Bus: Wien Hbf\\, Bahnsteig 7\\; Süd → Ötztal Bahnhof – Längenfeld über Sölden und Obergurgl\\\\Hochgurgl")
        // Folding never cuts a multi-byte character: every physical line is valid UTF-8 on its own.
        for physical in ics.components(separatedBy: "\r\n") {
            XCTAssertNotNil(String(data: Data(physical.utf8), encoding: .utf8))
        }
        XCTAssertTrue(ics.contains("\r\n "), "the long summary is folded")
        let description = unfolded(ics).first { $0.hasPrefix("DESCRIPTION:") }!
        XCTAssertTrue(description.contains("\\nAus KlimaBilanz exportiert."), "newline escaped")
    }

    func testDeadlinesAreAllDayWithAReminder() {
        let deadline = DataHubDeadline(id: "ticket-end-1", day: day(2027, 9, 30, 23, 59), title: "KlimaTicket Ö Classic endet",
                                       note: "Letzter gültiger Tag, laut deinem Ticket.")
        let ics = DataHubICS.deadlines([deadline], stamp: stamp)
        assertWellFormed(ics)
        let lines = unfolded(ics)
        XCTAssertTrue(lines.contains("DTSTART;VALUE=DATE:20270930"))
        XCTAssertTrue(lines.contains("DTEND;VALUE=DATE:20271001"))
        XCTAssertTrue(lines.contains("TRIGGER;RELATED=START:-PT15H"))
        XCTAssertTrue(lines.contains("SUMMARY:KlimaTicket Ö Classic endet"))
        XCTAssertTrue(lines.contains("X-WR-CALNAME:KlimaBilanz – Fristen"))
    }

    func testEmptyCalendarIsStillValid() {
        let ics = DataHubICS.trips([], stamp: stamp)
        assertWellFormed(ics)
        XCTAssertFalse(ics.contains("BEGIN:VEVENT"))
    }
}

final class DataHubMonthlyCSVTests: XCTestCase {
    func testMonthsNumbersAndExcelFormat() {
        let journey = UUID()
        let trips = [
            trip(day(2026, 10, 2), km: 108.4, fare: 23.4, roundTrip: true),
            trip(day(2026, 10, 3), km: 10, fare: 2.4, mode: .bus, journey: journey),
            trip(day(2026, 10, 3, 13), km: 50, fare: 11, journey: journey),
            trip(day(2027, 1, 5), km: 1234.5, fare: 1000.25),
        ]
        let interval = DataHubRange.ticketYear.interval(
            ticket: TicketPeriod(productID: "classic", name: "KlimaTicket Ö Classic", price: 1400, start: day(2026, 10, 1, 0),
                                 end: TicketPeriod.standardEnd(for: day(2026, 10, 1, 0))), now: stamp)
        let rows = DataHubMonthlyCSV.rows(trips, interval: interval)
        XCTAssertEqual(rows.count, 12, "every month of the ticket year, also the empty ones")
        XCTAssertEqual(rows.first?.label, "Oktober 2026")
        XCTAssertEqual(rows[3].label, "Jänner 2027")
        XCTAssertEqual(rows.first?.trips, 2, "the two legs of one journey are one Fahrt")
        XCTAssertEqual(rows.first!.value, 23.4 * 2 + 2.4 + 11, accuracy: 0.001)
        XCTAssertEqual(rows.first!.distanceKm, 108.4 * 2 + 60, accuracy: 0.001)
        let expectedCO2 = EmissionFactors.fallback.savedKg(km: 216.8, mode: .train) + EmissionFactors.fallback.savedKg(km: 10, mode: .bus)
            + EmissionFactors.fallback.savedKg(km: 50, mode: .train)
        XCTAssertEqual(rows.first!.co2SavedKg, expectedCO2, accuracy: 0.001)
        XCTAssertEqual(rows[1].trips, 0)

        let csv = DataHubMonthlyCSV.csv(rows)
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}Monat;Fahrten;Wert (€);Distanz (km);CO₂ gespart (kg)\r\n"))
        XCTAssertTrue(csv.contains("\r\nOktober 2026;2;60,20;276,8;\(TripCSVExport.decimal(expectedCO2, 1))\r\n"))
        XCTAssertTrue(csv.contains("\r\nNovember 2026;0;0,00;0,0;0,0\r\n"))
        XCTAssertTrue(csv.contains("\r\nJänner 2027;1;1000,25;1234,5;"))
        XCTAssertTrue(csv.contains("\r\nGesamt;3;1060,45;1511,3;"))
        XCTAssertTrue(csv.hasSuffix("\r\n"))
        XCTAssertFalse(csv.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
    }

    /// MARK: review-daten – a ticket year that runs on ends with today's month (or a later trip's): months to come are not „0 Fahrten“.
    func testMonthsToComeAreLeftOut() {
        let ticket = TicketPeriod(productID: "classic", name: "T", price: 1400, start: day(2026, 10, 1, 0),
                                  end: TicketPeriod.standardEnd(for: day(2026, 10, 1, 0)))
        let interval = DataHubRange.ticketYear.interval(ticket: ticket, now: stamp)
        let trips = [trip(day(2026, 10, 2))]
        XCTAssertEqual(DataHubMonthlyCSV.rows(trips, interval: interval, until: stamp).map(\.label), ["Oktober 2026", "November 2026"])
        let planned = trips + [trip(day(2027, 1, 5))]
        XCTAssertEqual(DataHubMonthlyCSV.rows(planned, interval: interval, until: stamp).last?.label, "Jänner 2027")
        let over = DataHubMonthlyCSV.rows(trips, interval: interval, until: day(2028, 1, 1))
        XCTAssertEqual(over.count, 12, "a past ticket year keeps all its months")
        XCTAssertEqual(DataHubMonthlyCSV.rows(trips, interval: nil, until: stamp).map(\.label), ["Oktober 2026"])
    }

    func testAllRangeRunsFromFirstToLastTrip() {
        let rows = DataHubMonthlyCSV.rows([trip(day(2025, 11, 30)), trip(day(2026, 2, 1))], interval: nil)
        XCTAssertEqual(rows.map(\.label), ["November 2025", "Dezember 2025", "Jänner 2026", "Februar 2026"])
        XCTAssertEqual(DataHubMonthlyCSV.rows([], interval: nil), [])
        XCTAssertEqual(DataHubMonthlyCSV.csv([]), "\u{FEFF}Monat;Fahrten;Wert (€);Distanz (km);CO₂ gespart (kg)\r\n")
    }
}

final class DataHubYearTextTests: XCTestCase {
    private let ticket = TicketPeriod(productID: "classic", name: "KlimaTicket Ö Classic", price: 1400, start: day(2026, 10, 1, 0),
                                      end: TicketPeriod.standardEnd(for: day(2026, 10, 1, 0)))

    func testTicketYearComparesWithThePrice() {
        var trips = (0..<10).map { trip(day(2026, 10, 1 + $0, 7), km: 100, fare: 50, roundTrip: true) }
        trips.append(trip(day(2026, 9, 30), fare: 999))   // before the ticket year: not counted
        let text = DataHubYearText.markdown(trips: trips, range: .ticketYear, ticket: ticket, now: stamp)
        XCTAssertTrue(text.hasPrefix("# Meine KlimaBilanz – Ticketjahr 2026/27\n"))
        XCTAssertTrue(text.contains("KlimaTicket Ö Classic · 1. Oktober 2026 bis 30. September 2027"))
        XCTAssertTrue(text.contains("**€ 1.000,00 Wert** bei € 1.400,00 Ticketpreis – noch € 400,00, bis es sich rentiert."))
        XCTAssertTrue(text.contains("- Fahrten: 10 an 10 Tagen"))
        XCTAssertTrue(text.contains("- Strecke: 2.000 km"))
        XCTAssertTrue(text.contains("| Oktober 2026 | 10 | € 1.000,00 | 2.000 |"))
        XCTAssertTrue(text.contains("1. Innsbruck Hbf ↔ St. Anton am Arlberg – 10 Fahrten"))
        XCTAssertTrue(text.contains("Werte sind Normalpreise"))
        XCTAssertFalse(text.contains("Prognose"), "no forecast in a balance")
    }

    /// MARK: review-daten – routes ranked like Statistik: a journey is one route from its first stop to its last (it counted legs).
    func testRoutesCountJourneysLikeStatistik() {
        var trips: [TripRecord] = []
        for index in 0..<3 {
            let journey = UUID()
            trips.append(trip(day(2026, 10, 1 + index, 7), "Lech", "Langen am Arlberg", mode: .bus, journey: journey))
            trips.append(trip(day(2026, 10, 1 + index, 8), "Langen am Arlberg", "Innsbruck Hbf", journey: journey))
        }
        trips += [trip(day(2026, 10, 20)), trip(day(2026, 10, 21))]
        let text = DataHubYearText.markdown(trips: trips, range: .calendarYear, ticket: nil, now: stamp)
        XCTAssertTrue(text.contains("1. Lech ↔ Innsbruck Hbf – 3 Fahrten"), text)
        XCTAssertTrue(text.contains("2. Innsbruck Hbf ↔ St. Anton am Arlberg – 2 Fahrten"), text)
        XCTAssertFalse(text.contains("Langen am Arlberg ↔"), "a leg is not a route of its own")
        XCTAssertTrue(text.contains("- Fahrten: 5 an 5 Tagen"))
    }

    func testPaidOffAndOtherRanges() {
        let trips = (0..<30).map { trip(day(2026, 10, 1 + $0, 7), fare: 50) }
        let paid = DataHubYearText.markdown(trips: trips, range: .ticketYear, ticket: ticket, now: stamp)
        XCTAssertTrue(paid.contains("rentiert, € 100,00 im Plus."))
        let calendarYear = DataHubYearText.markdown(trips: trips, range: .calendarYear, ticket: ticket, now: stamp)
        XCTAssertTrue(calendarYear.hasPrefix("# Meine KlimaBilanz – Kalenderjahr 2026\n"))
        XCTAssertTrue(calendarYear.contains("**€ 1.500,00 Wert** zu Normalpreisen."))
        let empty = DataHubYearText.markdown(trips: [], range: .all, ticket: nil, now: stamp)
        XCTAssertTrue(empty.contains("Noch keine Fahrten in diesem Zeitraum."))
    }
}

final class DataHubRangeTests: XCTestCase {
    func testRangesAndLabels() {
        let ticket = TicketPeriod(productID: "c", name: "T", price: 1, start: day(2026, 10, 1, 0), end: TicketPeriod.standardEnd(for: day(2026, 10, 1, 0)))
        XCTAssertEqual(DataHubRange.ticketYear.label(ticket: ticket, now: stamp), "Ticketjahr 2026/27")
        XCTAssertEqual(DataHubRange.ticketYear.fileTag(ticket: ticket, now: stamp), "Ticketjahr-2026-27")
        XCTAssertEqual(DataHubRange.calendarYear.label(ticket: ticket, now: stamp), "Kalenderjahr 2026")
        XCTAssertEqual(DataHubRange.all.fileTag(ticket: nil, now: stamp), "Alles")
        let year = DataHubRange.calendarYear.interval(ticket: nil, now: stamp)!
        XCTAssertEqual(year.start, day(2026, 1, 1, 0))
        XCTAssertEqual(year.end, day(2027, 1, 1, 0).addingTimeInterval(-1))
        XCTAssertNil(DataHubRange.all.interval(ticket: ticket, now: stamp))
        XCTAssertEqual(DataHubRange.ticketYear.interval(ticket: nil, now: stamp)?.duration, 0)
        let trips = [trip(day(2025, 12, 31, 23, 59)), trip(day(2026, 1, 1, 0, 0)), trip(day(2026, 12, 31, 23, 59))]
        XCTAssertEqual(DataHubRange.filter(trips, interval: year).count, 2)
    }

    func testFormats() {
        XCTAssertEqual(DataHubFormat.bytes(840), "840 Byte")
        XCTAssertEqual(DataHubFormat.bytes(18_400), "18 KB")
        XCTAssertEqual(DataHubFormat.bytes(1_234_567), "1,2 MB")
        XCTAssertEqual(DataHubFormat.bytes(999_499), "999 KB")
        XCTAssertEqual(DataHubFormat.bytes(999_700), "1,0 MB", "never „1000 KB“")
        XCTAssertEqual(DataHubFormat.integer(1_234_567), "1.234.567")
        XCTAssertEqual(DataHubFormat.decimal(1234.56, digits: 1), "1.234,6")
        XCTAssertEqual(DataHubFormat.count(1, "Fahrt", "Fahrten"), "1 Fahrt")
        XCTAssertEqual(DataHubFormat.count(1234, "Fahrt", "Fahrten"), "1.234 Fahrten")
        XCTAssertEqual(DataHubFormat.dayTime(day(2026, 11, 19, 18, 3)), "19.11.2026, 18:03")
    }
}
