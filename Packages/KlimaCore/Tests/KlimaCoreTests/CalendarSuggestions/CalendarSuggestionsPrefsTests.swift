import XCTest
@testable import KlimaCore

final class CalendarSuggestionsPrefsTests: XCTestCase {
    private typealias F = CalendarFixtures

    func testSHA256KnownVectors() {
        XCTAssertEqual(SHA256Hex.digest(Array("".utf8)), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256Hex.digest(Array("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let long = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
        XCTAssertEqual(SHA256Hex.digest(Array(long.utf8)), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    func testEventKeyIsAHashOfIdAndStart() {
        let start = F.date("2026-11-20 10:00")
        let key = CalendarEventKey.make(eventID: "ABC-123", start: start)
        XCTAssertEqual(key.count, 64)
        XCTAssertFalse(key.contains("ABC"))
        XCTAssertEqual(key, CalendarEventKey.make(eventID: "ABC-123", start: start))
        XCTAssertNotEqual(key, CalendarEventKey.make(eventID: "ABC-123", start: start.addingTimeInterval(7 * 86_400)))
        XCTAssertNotEqual(key, CalendarEventKey.make(eventID: "ABC-124", start: start))
    }

    func testPrefsRoundTripAndDefaults() throws {
        var prefs = F.prefs(calendars: ["a", "b"], buffer: 45)
        prefs.dismiss(key: "k1", eventStart: F.date("2026-11-20 10:00"))
        prefs.snooze(key: "k2", until: F.date("2026-11-21 07:00"))
        prefs.followUps["k3"] = CalendarFollowUpEntry(stationID: "at:44:41164", stationName: "Linz Hauptbahnhof", arrival: F.date("2026-11-20 09:40"))
        let data = try JSONEncoder().encode(prefs)
        XCTAssertEqual(try JSONDecoder().decode(CalendarSuggestionPrefs.self, from: data), prefs)
        // Event text never ends up in the stored JSON.
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("Meeting"))

        let empty = try JSONDecoder().decode(CalendarSuggestionPrefs.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.isEnabled)
        XCTAssertEqual(empty.bufferMinutes, 20)
        XCTAssertTrue(empty.calendarIDs.isEmpty)
        let odd = try JSONDecoder().decode(CalendarSuggestionPrefs.self, from: Data(#"{"bufferMinutes": 17}"#.utf8))
        XCTAssertEqual(odd.bufferMinutes, 20)
    }

    func testDismissedEntriesArePrunedSixtyDaysAfterTheEvent() {
        var prefs = F.prefs()
        prefs.dismiss(key: "old", eventStart: F.date("2026-09-15 10:00"))
        prefs.dismiss(key: "recent", eventStart: F.date("2026-10-01 10:00"))
        prefs.snooze(key: "gone", until: F.date("2026-11-19 07:00"))
        prefs.snooze(key: "running", until: F.date("2026-11-20 07:00"))
        prefs.followUps["stale"] = CalendarFollowUpEntry(stationID: "s", stationName: "S", arrival: F.date("2026-11-15 10:00"))
        prefs.followUps["fresh"] = CalendarFollowUpEntry(stationID: "s", stationName: "S", arrival: F.date("2026-11-18 10:00"))
        prefs.prune(now: F.date("2026-11-19 08:00"))
        XCTAssertEqual(Set(prefs.dismissed.keys), ["recent"])
        XCTAssertEqual(Set(prefs.snoozed.keys), ["running"])
        XCTAssertEqual(Set(prefs.followUps.keys), ["fresh"])
        // 60 days after 1 October.
        prefs.prune(now: F.date("2026-11-30 10:01"))
        XCTAssertTrue(prefs.dismissed.isEmpty)
    }

    func testDismissClearsSnoozeAndFollowUp() {
        var prefs = F.prefs()
        prefs.snooze(key: "k", until: F.date("2026-11-21 07:00"))
        prefs.followUps["k"] = CalendarFollowUpEntry(stationID: "s", stationName: "S", arrival: F.date("2026-11-20 10:00"))
        prefs.dismiss(key: "k", eventStart: F.date("2026-11-20 10:20"))
        XCTAssertNil(prefs.snoozed["k"])
        XCTAssertNil(prefs.followUps["k"])
        XCTAssertTrue(prefs.isHidden(key: "k", now: F.date("2026-11-19 08:00")))
    }

    func testSetupStates() {
        typealias S = CalendarSetupState
        XCTAssertEqual(S.make(isEnabled: false, access: .fullAccess, offeredCalendars: 3, selectedCalendars: 1), .off)
        XCTAssertEqual(S.make(isEnabled: true, access: .notDetermined, offeredCalendars: 0, selectedCalendars: 0), .needsPermission)
        XCTAssertEqual(S.make(isEnabled: true, access: .denied, offeredCalendars: 3, selectedCalendars: 1), .denied)
        XCTAssertEqual(S.make(isEnabled: true, access: .restricted, offeredCalendars: 3, selectedCalendars: 1), .restricted)
        XCTAssertEqual(S.make(isEnabled: true, access: .writeOnly, offeredCalendars: 3, selectedCalendars: 1), .writeOnly)
        XCTAssertEqual(S.make(isEnabled: true, access: .fullAccess, offeredCalendars: 0, selectedCalendars: 0), .noCalendars)
        XCTAssertEqual(S.make(isEnabled: true, access: .fullAccess, offeredCalendars: 2, selectedCalendars: 0), .noneSelected)
        XCTAssertEqual(S.make(isEnabled: true, access: .fullAccess, offeredCalendars: 2, selectedCalendars: 1), .active)
        XCTAssertTrue(S.active.showsSuggestions)
        XCTAssertFalse(S.denied.showsSuggestions)
    }

    // MARK: Follow-up

    func testFollowUpAsksTheDayAfterWhenNoTripWasLogged() {
        var prefs = F.prefs()
        let arrival = F.date("2026-11-20 09:40")
        prefs.followUps["k"] = CalendarFollowUpEntry(stationID: "at:44:41164", stationName: "Linz Hauptbahnhof", arrival: arrival)
        // Not on the event's day itself.
        XCTAssertTrue(CalendarFollowUpPlanner.pending(prefs: prefs, trips: [], now: F.date("2026-11-20 20:00")).isEmpty)
        // The day after and the day after that.
        XCTAssertEqual(CalendarFollowUpPlanner.pending(prefs: prefs, trips: [], now: F.date("2026-11-21 08:00")).map(\.key), ["k"])
        XCTAssertEqual(CalendarFollowUpPlanner.pending(prefs: prefs, trips: [], now: F.date("2026-11-22 23:00")).map(\.key), ["k"])
        // Then never again.
        XCTAssertTrue(CalendarFollowUpPlanner.pending(prefs: prefs, trips: [], now: F.date("2026-11-23 00:01")).isEmpty)
        // A trip to Linz that day answers it.
        let trip = F.trip(to: "at:44:41164", name: "Linz Hauptbahnhof", on: "2026-11-20 07:05")
        XCTAssertTrue(CalendarFollowUpPlanner.pending(prefs: prefs, trips: [trip], now: F.date("2026-11-21 08:00")).isEmpty)
        // "Kein Zug" before the day: no question afterwards.
        prefs.dismissed["k"] = F.date("2026-11-20 10:00")
        XCTAssertTrue(CalendarFollowUpPlanner.pending(prefs: prefs, trips: [], now: F.date("2026-11-21 08:00")).isEmpty)
    }
}
