import XCTest
@testable import KlimaCore

final class CSVImportTests: XCTestCase {
    let cal = Calendar.vienna

    private func parts(_ date: Date?) -> [Int]? {
        guard let date else { return nil }
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return [c.year!, c.month!, c.day!, c.hour!, c.minute!]
    }

    // MARK: Encoding

    func testDecodeUTF8WithAndWithoutBOM() {
        let text = "Datum;Von;Nach\n09.10.2026;Wien;St. Pölten\n"
        let plain = CSVImport.decode(Data(text.utf8))
        XCTAssertEqual(plain.encoding, .utf8)
        XCTAssertEqual(plain.text, text)
        let bom = CSVImport.decode(Data([0xEF, 0xBB, 0xBF] + Array(text.utf8)))
        XCTAssertEqual(bom.encoding, .utf8BOM)
        XCTAssertEqual(bom.text, text)
        XCTAssertFalse(bom.text.hasPrefix("\u{FEFF}"))
    }

    func testDecodeWindows1252AndLatin1Fallback() {
        // "Pölten;€ 13,40" in Windows-1252: ö = 0xF6, € = 0x80
        let bytes: [UInt8] = Array("P".utf8) + [0xF6] + Array("lten;".utf8) + [0x80] + Array(" 13,40".utf8)
        let decoded = CSVImport.decode(Data(bytes))
        XCTAssertEqual(decoded.encoding, .windows1252)
        XCTAssertEqual(decoded.text, "Pölten;€ 13,40")
        let latin = CSVImport.decode(Data(Array("Gm".utf8) + [0xFC] + Array("nd".utf8)))   // "Gmünd"
        XCTAssertEqual(latin.encoding, .latin1)
        XCTAssertEqual(latin.text, "Gmünd")
    }

    func testDecodeUTF16LittleEndianExcelUnicodeText() {
        let text = "Datum\tVon\n09.10.2026\tWien"
        var data = Data([0xFF, 0xFE])
        data.append(text.data(using: .utf16LittleEndian)!)
        let decoded = CSVImport.decode(data)
        XCTAssertEqual(decoded.encoding, .utf16LE)
        XCTAssertEqual(decoded.text, text)
        XCTAssertEqual(CSVImport.sniffDelimiter(decoded.text), .tab)
    }

    // MARK: Delimiter sniffing

    func testSniffSemicolonWithDecimalCommas() {
        let text = """
        Datum;Von;Nach;Preis;Distanz
        09.10.2026;Wien Hbf;Salzburg Hbf;65,90;312,5
        10.10.2026;Salzburg Hbf;Wien Hbf;65,90;312,5
        11.10.2026;Linz Hbf;Wels Hbf;7,20;25,1
        """
        XCTAssertEqual(CSVImport.sniffDelimiter(text), .semicolon)
    }

    func testSniffSemicolonWithoutHeaderAndCommasEverywhere() {
        let text = "09.10.2026;13,40;101,5;26,80\n10.10.2026;13,40;101,5;26,80\n"
        XCTAssertEqual(CSVImport.sniffDelimiter(text), .semicolon)
    }

    func testSniffCommaAndTab() {
        XCTAssertEqual(CSVImport.sniffDelimiter("date,from,to,price\n2026-10-09,Vienna,Salzburg,65.90\n2026-10-10,Linz,Wels,7.20\n"), .comma)
        XCTAssertEqual(CSVImport.sniffDelimiter("Datum\tVon\tNach\n09.10.2026\tWien\tLinz\n"), .tab)
    }

    func testSniffIgnoresDelimitersInsideQuotes() {
        let text = """
        date,from,to,note
        2026-10-09,Wien,Linz,"Meeting; danach Essen; spät"
        2026-10-10,Linz,Wien,"zurück; müde"
        """
        XCTAssertEqual(CSVImport.sniffDelimiter(text), .comma)
    }

    func testExcelSepHint() {
        let text = "sep=,\nDatum,Preis\n09.10.2026,\"13,40\"\n"
        XCTAssertEqual(CSVImport.sniffDelimiter(text), .comma)
        let rows = CSVImport.parse(text, delimiter: .comma)
        XCTAssertEqual(rows, [["Datum", "Preis"], ["09.10.2026", "13,40"]])
    }

    // MARK: RFC 4180

    func testQuotedFieldsWithDelimitersNewlinesAndQuotes() {
        let text = "Von;Nach;Notiz\r\n\"Wien; Hbf\";Linz;\"Zeile 1\nZeile 2\"\r\nGraz;\"Klagenfurt \"\"Hbf\"\"\";\"\"\r\n"
        let rows = CSVImport.parse(text, delimiter: .semicolon)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1], ["Wien; Hbf", "Linz", "Zeile 1\nZeile 2"])
        XCTAssertEqual(rows[2], ["Graz", "Klagenfurt \"Hbf\"", ""])
    }

    func testParseHandlesCRLineEndingsBlankLinesAndMissingTrailingNewline() {
        let rows = CSVImport.parse("a;b\r\r1;2\r\n\n  \n3;4", delimiter: .semicolon)
        XCTAssertEqual(rows, [["a", "b"], ["1", "2"], ["3", "4"]])
    }

    func testParseTrimsUnquotedButKeepsQuotedWhitespace() {
        let rows = CSVImport.parse(" Wien ; \" Linz \" ;3", delimiter: .semicolon)
        XCTAssertEqual(rows, [["Wien", " Linz ", "3"]])
    }

    // MARK: Numbers (the competitor's decimal-comma bug: 1,50 € became 150 €)

    func testGermanDecimalCommaIsNeverMultiplied() {
        XCTAssertEqual(CSVImport.number("1,50"), 1.5)
        XCTAssertEqual(CSVImport.number("2,6"), 2.6)
        XCTAssertEqual(CSVImport.number("49,20"), 49.2)
        XCTAssertEqual(CSVImport.number("13,40"), 13.4)
        XCTAssertEqual(CSVImport.number("€ 13,40"), 13.4)
        XCTAssertEqual(CSVImport.number("13,40 €"), 13.4)
        XCTAssertEqual(CSVImport.number("EUR 13,40"), 13.4)
        XCTAssertEqual(CSVImport.number("0,90"), 0.9)
        XCTAssertEqual(CSVImport.number(",50"), 0.5)
        XCTAssertEqual(CSVImport.number("1,500"), 1.5)          // de-AT: decimal comma, not 1500
    }

    func testThousandsSeparators() {
        XCTAssertEqual(CSVImport.number("1.234,50"), 1234.5)
        XCTAssertEqual(CSVImport.number("€ 1.234,50"), 1234.5)
        XCTAssertEqual(CSVImport.number("1,234.50"), 1234.5)
        XCTAssertEqual(CSVImport.number("1.234.567,89"), 1_234_567.89)
        XCTAssertEqual(CSVImport.number("1 234,50"), 1234.5)
        XCTAssertEqual(CSVImport.number("1\u{00A0}234,50"), 1234.5)
        XCTAssertEqual(CSVImport.number("1'234.50"), 1234.5)
        XCTAssertEqual(CSVImport.number("1.400"), 1400)          // de-AT thousands group
        XCTAssertEqual(CSVImport.number("1.400", style: .dot), 1.4)
        XCTAssertEqual(CSVImport.number("1,234", style: .dot), 1234)
    }

    func testEnglishDecimalPoint() {
        XCTAssertEqual(CSVImport.number("13.40"), 13.4)
        XCTAssertEqual(CSVImport.number("13.4"), 13.4)
        XCTAssertEqual(CSVImport.number("0.500"), 0.5)          // leading zero: cannot be a thousands group
        XCTAssertEqual(CSVImport.number("€13.40"), 13.4)
        XCTAssertEqual(CSVImport.number("13.40", style: .comma), 13.4)
    }

    func testIntegersSignsAndAustrianDash() {
        XCTAssertEqual(CSVImport.number("23"), 23)
        XCTAssertEqual(CSVImport.number("-4,50"), -4.5)
        XCTAssertEqual(CSVImport.number("−4,50"), -4.5)
        XCTAssertEqual(CSVImport.number("(4,50)"), -4.5)
        XCTAssertEqual(CSVImport.number("+4,50"), 4.5)
        XCTAssertEqual(CSVImport.number("13,–"), 13)
        XCTAssertEqual(CSVImport.number("€ 13,-"), 13)
        XCTAssertEqual(CSVImport.number("101 km"), 101)
    }

    func testInvalidNumbers() {
        XCTAssertNil(CSVImport.number(""))
        XCTAssertNil(CSVImport.number("abc"))
        XCTAssertNil(CSVImport.number("12,34,5"))
        XCTAssertNil(CSVImport.number("1.2.3"))
        XCTAssertNil(CSVImport.number("1,2.3,4"))
        XCTAssertNil(CSVImport.number("gratis"))
        XCTAssertNil(CSVImport.number("09.10.2026"))
        XCTAssertNil(CSVImport.number("12/5"))
    }

    func testInferDecimalStyle() {
        XCTAssertEqual(CSVImport.inferDecimalStyle(["13,40", "1.234,50", "7"]), .comma)
        XCTAssertEqual(CSVImport.inferDecimalStyle(["13.40", "1,234.50", "7"]), .dot)
        XCTAssertEqual(CSVImport.inferDecimalStyle(["7", "12"]), .unknown)
        XCTAssertEqual(CSVImport.inferDecimalStyle(["1.400", "13,40"]), .comma)
    }

    // MARK: Dates

    func testGermanAndISODates() {
        XCTAssertEqual(parts(CSVImport.date("09.10.2026")), [2026, 10, 9, 12, 0])
        XCTAssertEqual(parts(CSVImport.date("9.10.2026")), [2026, 10, 9, 12, 0])
        XCTAssertEqual(parts(CSVImport.date("09.10.26")), [2026, 10, 9, 12, 0])
        XCTAssertEqual(parts(CSVImport.date("2026-10-09")), [2026, 10, 9, 12, 0])
        XCTAssertEqual(parts(CSVImport.date("09/10/2026")), [2026, 10, 9, 12, 0])
        XCTAssertEqual(parts(CSVImport.date("10/31/2026")), [2026, 10, 31, 12, 0])   // US order only when unambiguous
        XCTAssertEqual(parts(CSVImport.date("2026/10/09")), [2026, 10, 9, 12, 0])
        XCTAssertEqual(parts(CSVImport.date("20261009")), [2026, 10, 9, 12, 0])
    }

    func testDatesWithTime() {
        XCTAssertEqual(parts(CSVImport.date("09.10.2026 07:12")), [2026, 10, 9, 7, 12])
        XCTAssertEqual(parts(CSVImport.date("09.10.2026, 07:12 Uhr")), [2026, 10, 9, 7, 12])
        XCTAssertEqual(parts(CSVImport.date("2026-10-09 07:12:30")), [2026, 10, 9, 7, 12])
        XCTAssertEqual(parts(CSVImport.date("2026-10-09T07:12")), [2026, 10, 9, 7, 12])
        XCTAssertEqual(parts(CSVImport.date("2026-10-09T05:12:00Z")), [2026, 10, 9, 7, 12])        // UTC → CEST
        XCTAssertEqual(parts(CSVImport.date("2026-10-09T07:12:00.000+02:00")), [2026, 10, 9, 7, 12])
        XCTAssertEqual(parts(CSVImport.date("09.10.2026", time: "7:05")), [2026, 10, 9, 7, 5])
        XCTAssertEqual(parts(CSVImport.date("09.10.2026", time: "")), [2026, 10, 9, 12, 0])
    }

    func testTextualAndSerialDates() {
        XCTAssertEqual(parts(CSVImport.date("9. Okt. 2026")), [2026, 10, 9, 12, 0])
        XCTAssertEqual(parts(CSVImport.date("9. Oktober 2026")), [2026, 10, 9, 12, 0])
        XCTAssertEqual(parts(CSVImport.date("Fr., 9. Okt. 2026")), [2026, 10, 9, 12, 0])
        XCTAssertEqual(parts(CSVImport.date("3. Jänner 2027")), [2027, 1, 3, 12, 0])
        XCTAssertEqual(parts(CSVImport.date("14. März 2026")), [2026, 3, 14, 12, 0])
        XCTAssertEqual(parts(CSVImport.date("46304")), [2026, 10, 9, 12, 0])                       // Excel serial
    }

    func testInvalidDates() {
        XCTAssertNil(CSVImport.date("31.02.2026"))
        XCTAssertNil(CSVImport.date("2026-13-01"))
        XCTAssertNil(CSVImport.date("morgen"))
        XCTAssertNil(CSVImport.date("13,40"))
        XCTAssertNil(CSVImport.date("09.10.2026 25:00"))
        XCTAssertNil(CSVImport.date(""))
    }

    func testDSTDayStaysOnTheSameCalendarDay() {
        // 29 March 2026 (clocks jump) – noon default keeps the day.
        XCTAssertEqual(parts(CSVImport.date("29.03.2026")), [2026, 3, 29, 12, 0])
    }

    // MARK: Vocabulary

    func testModesCategoriesAndBooleans() {
        XCTAssertEqual(CSVImport.mode("Zug"), .train)
        XCTAssertEqual(CSVImport.mode("RJX 662"), .train)
        XCTAssertEqual(CSVImport.mode("ÖBB"), .train)
        XCTAssertEqual(CSVImport.mode("S-Bahn"), .sBahn)
        XCTAssertEqual(CSVImport.mode("S1"), .sBahn)
        XCTAssertEqual(CSVImport.mode("U4"), .metro)
        XCTAssertEqual(CSVImport.mode("Bim"), .tram)
        XCTAssertEqual(CSVImport.mode("Straßenbahn"), .tram)
        XCTAssertEqual(CSVImport.mode("Postbus 4130"), .bus)
        XCTAssertEqual(CSVImport.mode("Fähre"), .ferry)
        XCTAssertEqual(CSVImport.mode("Standseilbahn"), .cableCar)
        XCTAssertEqual(CSVImport.mode("cableCar"), .cableCar)
        XCTAssertNil(CSVImport.mode("Teleporter"))

        XCTAssertEqual(CSVImport.category("Arbeitsweg"), .commute)
        XCTAssertEqual(CSVImport.category("Arbeit"), .commute)
        XCTAssertEqual(CSVImport.category("Dienstreise"), .business)
        XCTAssertEqual(CSVImport.category("Uni"), .education)
        XCTAssertEqual(CSVImport.category("holiday"), .holiday)
        XCTAssertNil(CSVImport.category("xyz"))

        XCTAssertEqual(CSVImport.bool("ja"), true)
        XCTAssertEqual(CSVImport.bool("H+R"), true)
        XCTAssertEqual(CSVImport.bool("Hin & Retour"), true)
        XCTAssertEqual(CSVImport.bool("✓"), true)
        XCTAssertEqual(CSVImport.bool("nein"), false)
        XCTAssertEqual(CSVImport.bool(""), false)
        XCTAssertNil(CSVImport.bool("vielleicht"))
    }

    func testRouteSplitting() {
        XCTAssertEqual(CSVImport.splitRoute("Salzburg Hbf – Wien Hbf")?.from, "Salzburg Hbf")
        XCTAssertEqual(CSVImport.splitRoute("Salzburg Hbf – Wien Hbf")?.to, "Wien Hbf")
        XCTAssertEqual(CSVImport.splitRoute("Landeck-Zams -> Innsbruck")?.from, "Landeck-Zams")
        XCTAssertEqual(CSVImport.splitRoute("Linz → Wels")?.to, "Wels")
        XCTAssertEqual(CSVImport.splitRoute("Graz nach Leoben")?.to, "Leoben")
        let round = CSVImport.splitRoute("Wien ↔ St. Pölten")
        XCTAssertEqual(round?.isRoundTrip, true)
        XCTAssertEqual(CSVImport.splitRoute("Bregenz - Dornbirn (H+R)")?.to, "Dornbirn")
        XCTAssertEqual(CSVImport.splitRoute("Bregenz - Dornbirn (H+R)")?.isRoundTrip, true)
        XCTAssertNil(CSVImport.splitRoute("Landeck-Zams"))
    }

    // MARK: Mapping

    func testGuessMappingGermanHeader() {
        let rows = CSVImport.parse("""
        Datum;Uhrzeit;Von;Nach;Preis (€);Verkehrsmittel;Hin & Retour;Kategorie;Bemerkung;Entfernung (km)
        09.10.2026;07:12;St. Anton;Innsbruck;23,50;Zug;ja;Arbeit;;101
        """, delimiter: .semicolon)
        let guess = CSVImport.guessMapping(rows: rows)
        XCTAssertTrue(guess.hasHeader)
        XCTAssertEqual(guess.fields, [.date, .time, .from, .to, .price, .mode, .roundTrip, .category, .note, .distance])
        XCTAssertEqual(guess.format, .generic)
    }

    func testGuessMappingEnglishHeader() {
        let rows = CSVImport.parse("Date,Origin,Destination,Fare,Mode,Return,Notes\n2026-10-09,Wien,Linz,35.90,Train,no,\n", delimiter: .comma)
        let guess = CSVImport.guessMapping(rows: rows)
        XCTAssertEqual(guess.fields, [.date, .from, .to, .price, .mode, .roundTrip, .note])
    }

    func testGuessMappingKlimaTicketTrackerStyle() {
        let rows = CSVImport.parse("Datum,Name,Preis,Kategorie,Ticket\n09.10.2026,Salzburg - Wien,\"65,90\",Freizeit,KlimaTicket Ö\n", delimiter: .comma)
        let guess = CSVImport.guessMapping(rows: rows)
        XCTAssertEqual(guess.format, .klimaTicketTracker)
        XCTAssertEqual(guess.fields, [.date, .route, .price, .category, nil])
        let parsed = CSVImport.parseRows(rows, fields: guess.fields, hasHeader: guess.hasHeader)
        XCTAssertEqual(parsed.first?.fromName, "Salzburg")
        XCTAssertEqual(parsed.first?.toName, "Wien")
        XCTAssertEqual(parsed.first?.fare, 65.9)
        XCTAssertEqual(parsed.first?.category, .leisure)
        XCTAssertTrue(parsed.first?.isValid == true)
    }

    func testGuessMappingWithoutHeaderFromContent() {
        let rows = CSVImport.parse("09.10.2026;Wien Hbf;Linz Hbf;35,90;189\n10.10.2026;Linz Hbf;Wien Hbf;35,90;189\n", delimiter: .semicolon)
        let guess = CSVImport.guessMapping(rows: rows)
        XCTAssertFalse(guess.hasHeader)
        XCTAssertEqual(guess.fields, [.date, .from, .to, .price, .distance])
    }

    func testOldKlimaBilanzExportDistanceIsTotal() {
        // v1 export (CSVExport.trips): "Distanz (km)" = all legs.
        let start = cal.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 7, minute: 12))!
        let record = TripRecord(date: start, fromName: "St. Anton am Arlberg", toName: "Innsbruck Hauptbahnhof", mode: .train,
                                distanceKm: 101, fareEUR: 23.5, isRoundTrip: true)
        let csv = CSVExport.trips([record])
        let decoded = CSVImport.decode(Data(csv.utf8))
        let rows = CSVImport.parse(decoded.text, delimiter: CSVImport.sniffDelimiter(decoded.text))
        let guess = CSVImport.guessMapping(rows: rows)
        XCTAssertEqual(guess.format, .klimaBilanz)
        let parsed = CSVImport.parseRows(rows, fields: guess.fields, hasHeader: true)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].distanceKm, 101)
        XCTAssertEqual(parsed[0].fare, 23.5)
        XCTAssertTrue(parsed[0].isRoundTrip)
        XCTAssertEqual(parts(parsed[0].date), [2026, 3, 1, 7, 12])
    }

    // MARK: Round trip with our own export

    func testExportImportRoundTrip() {
        let d1 = cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 7, minute: 12))!
        let d2 = cal.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 18, minute: 5))!
        let a = TripRecord(date: d1, fromName: "St. Anton am Arlberg", toName: "Innsbruck Hauptbahnhof", mode: .train,
                           distanceKm: 101, fareEUR: 23.5, isRoundTrip: true, category: .commute)
        let b = TripRecord(date: d2, fromName: "Wien \"Hbf\"; Ost", toName: "=cmd", mode: .metro, distanceKm: 4.5, fareEUR: 3.2,
                           isRoundTrip: false, category: nil, isInduced: true)
        let csv = TripCSVExport.trips([b, a], notes: [a.id: "Pendeln;\nmit Rad"])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        let decoded = CSVImport.decode(Data(csv.utf8))
        XCTAssertEqual(decoded.encoding, .utf8BOM)
        let delimiter = CSVImport.sniffDelimiter(decoded.text)
        XCTAssertEqual(delimiter, .semicolon)
        let rows = CSVImport.parse(decoded.text, delimiter: delimiter)
        let guess = CSVImport.guessMapping(rows: rows)
        XCTAssertEqual(guess.format, .klimaBilanz)
        XCTAssertEqual(guess.fields, [.date, .time, .from, .to, .via, .mode, .roundTrip, .category, .induced, .totalDistance, .price,
                                      .totalValue, .note])
        let parsed = CSVImport.parseRows(rows, fields: guess.fields, hasHeader: guess.hasHeader)
        XCTAssertEqual(parsed.count, 2)
        let first = parsed[0], second = parsed[1]
        XCTAssertEqual(first.date, d1)
        XCTAssertEqual(first.fromName, "St. Anton am Arlberg")
        XCTAssertEqual(first.mode, .train)
        XCTAssertEqual(first.fare, 23.5)
        XCTAssertEqual(first.distanceKm, 101)
        XCTAssertTrue(first.isRoundTrip)
        XCTAssertEqual(first.category, .commute)
        XCTAssertEqual(first.note, "Pendeln;\nmit Rad")
        XCTAssertFalse(first.isInduced)
        XCTAssertEqual(second.date, d2)
        XCTAssertEqual(second.fromName, "Wien \"Hbf\"; Ost")
        XCTAssertEqual(second.toName, "=cmd")
        XCTAssertEqual(second.mode, .metro)
        XCTAssertEqual(second.fare, 3.2)
        XCTAssertEqual(second.distanceKm, 4.5)
        XCTAssertTrue(second.isInduced)
        XCTAssertNil(second.category)
        XCTAssertTrue(parsed.allSatisfy(\.isValid))
        // Same key → duplicate on re-import.
        XCTAssertEqual(CSVImport.duplicateKey(date: first.date!, fromName: first.fromName, toName: first.toName, fare: first.fare!),
                       CSVImport.duplicateKey(date: a.date, fromName: a.fromName, toName: a.toName, fare: a.fareEUR))
    }

    func testTemplateParsesCleanly() {
        let text = CSVImport.decode(Data(TripCSVExport.template().utf8)).text
        let rows = CSVImport.parse(text, delimiter: CSVImport.sniffDelimiter(text))
        let guess = CSVImport.guessMapping(rows: rows)
        let parsed = CSVImport.parseRows(rows, fields: guess.fields, hasHeader: guess.hasHeader)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertTrue(parsed.allSatisfy(\.isValid))
        XCTAssertNil(parsed[0].fare)            // to be estimated
        XCTAssertEqual(parsed[1].fare, 65.9)
        XCTAssertTrue(parsed[1].isInduced)
    }

    // MARK: Validation

    func testRowValidation() {
        let rows = CSVImport.parse("""
        Datum;Von;Nach;Preis;Verkehrsmittel
        31.02.2026;Wien;Linz;10,00;Zug
        ;Wien;Linz;10,00;Zug
        09.10.2026;Wien;wien;10,00;Zug
        09.10.2026;Wien;Linz;zehn;Zug
        09.10.2026;Wien;Linz;-3,00;Zug
        09.10.2026;Wien;Linz;1.234,50;Zug
        09.10.2026;Wien;Linz;;Hubschrauber
        09.10.2026;;Linz;5;Zug
        """, delimiter: .semicolon)
        let guess = CSVImport.guessMapping(rows: rows)
        let parsed = CSVImport.parseRows(rows, fields: guess.fields, hasHeader: true)
        XCTAssertEqual(parsed.map(\.line), [2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(parsed[0].errors, [.invalidDate("31.02.2026")])
        XCTAssertEqual(parsed[1].errors, [.missingDate])
        XCTAssertEqual(parsed[2].errors, [.sameStations])
        XCTAssertEqual(parsed[3].errors, [.invalidPrice("zehn")])
        XCTAssertEqual(parsed[4].errors, [.negativePrice])
        XCTAssertTrue(parsed[5].isValid)
        XCTAssertEqual(parsed[5].fare, 1234.5)
        XCTAssertEqual(parsed[5].warnings, [.implausiblePrice(1234.5)])
        XCTAssertTrue(parsed[6].isValid)
        XCTAssertNil(parsed[6].fare)
        XCTAssertEqual(parsed[6].warnings, [.unknownMode("Hubschrauber")])
        XCTAssertEqual(parsed[7].errors, [.missingFrom])
        XCTAssertFalse(CSVImport.Issue.missingDate.message.isEmpty)
    }

    func testPlaceholderCellsCountAsEmpty() {
        let rows = CSVImport.parse("""
        Datum;Von;Nach;Preis;Hin & Retour;Notiz
        09.10.2026;Wien;Linz;-;–;n/a
        10.10.2026;Wien;Linz;k. A.;ja;-
        """, delimiter: .semicolon)
        let guess = CSVImport.guessMapping(rows: rows)
        let parsed = CSVImport.parseRows(rows, fields: guess.fields, hasHeader: true)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertTrue(parsed.allSatisfy(\.isValid))
        XCTAssertTrue(parsed.allSatisfy { $0.fare == nil && $0.note.isEmpty })
        XCTAssertEqual(parsed.map(\.isRoundTrip), [false, true])
        // A real value that merely starts with a dash is still a number.
        XCTAssertEqual(CSVImport.number("-3,00"), -3)
        XCTAssertFalse(CSVImport.isPlaceholder("Wien"))
    }

    func testTotalValueSplitsIntoLegsWhenNoPrice() {
        let rows = CSVImport.parse("Datum;Strecke;Gesamtpreis;Retour\n09.10.2026;Wien – Linz;71,80;ja\n", delimiter: .semicolon)
        let guess = CSVImport.guessMapping(rows: rows)
        XCTAssertEqual(guess.fields, [.date, .route, .totalValue, .roundTrip])
        let row = CSVImport.parseRows(rows, fields: guess.fields, hasHeader: true)[0]
        XCTAssertEqual(row.fare, 35.9)
        XCTAssertTrue(row.isRoundTrip)
    }

    func testDuplicateKeyIgnoresTimeAndSpelling() {
        let morning = cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 7))!
        let evening = cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 21))!
        XCTAssertEqual(CSVImport.duplicateKey(date: morning, fromName: "Innsbruck Hauptbahnhof", toName: "St. Anton", fare: 23.5),
                       CSVImport.duplicateKey(date: evening, fromName: "innsbruck hbf", toName: "St.Anton", fare: 23.50000001))
        XCTAssertNotEqual(CSVImport.duplicateKey(date: morning, fromName: "A", toName: "B", fare: 23.5),
                          CSVImport.duplicateKey(date: morning, fromName: "B", toName: "A", fare: 23.5))
    }

    // MARK: Report pagination

    func testReportPaginationKeepsHeadersWithTrips() {
        var trips: [TripRecord] = []
        for month in 1...3 {
            for day in 1...10 {
                let d = cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: 8))!
                trips.append(TripRecord(date: d, fromName: "A", toName: "B", mode: .train, distanceKm: 10, fareEUR: 2))
            }
        }
        let pages = ReportPagination.pages(trips: trips, firstPageCapacity: 120, pageCapacity: 200, monthHeight: 20, tripHeight: 10)
        // Every trip appears exactly once, in order.
        let flat = pages.flatMap { $0 }.compactMap { line -> TripRecord? in if case .trip(let t) = line { return t } else { return nil } }
        XCTAssertEqual(flat.map(\.id), trips.map(\.id))
        for page in pages {
            // Never ends with a month header.
            if case .month = page.last! { XCTFail("orphaned month header") }
            // Height fits.
            let height = page.reduce(0.0) { sum, line in if case .month = line { return sum + 20 } else { return sum + 10 } }
            XCTAssertLessThanOrEqual(height, pages.first == page ? 120 : 200)
        }
        // Page 1: Jän header + 10 trips = 120 → February starts on page 2.
        XCTAssertEqual(pages[0].count, 11)
        if case .month(_, let count, let value, _, let continued) = pages[1][0] {
            XCTAssertEqual(count, 10)
            XCTAssertEqual(value, 20)
            XCTAssertFalse(continued)
        } else { XCTFail("expected month header") }
        XCTAssertTrue(ReportPagination.pages(trips: [], firstPageCapacity: 100, pageCapacity: 100, monthHeight: 10, tripHeight: 10).isEmpty)
    }

    func testReportPaginationContinuedHeader() {
        let trips = (1...30).map { day in
            TripRecord(date: cal.date(from: DateComponents(year: 2026, month: 5, day: day, hour: 8))!, fromName: "A", toName: "B",
                       mode: .bus, distanceKm: 5, fareEUR: 2)
        }
        let pages = ReportPagination.pages(trips: trips, firstPageCapacity: 100, pageCapacity: 100, monthHeight: 10, tripHeight: 10)
        XCTAssertGreaterThan(pages.count, 1)
        if case .month(_, _, _, _, let continued) = pages[1][0] { XCTAssertTrue(continued) } else { XCTFail("expected continued header") }
    }
}
