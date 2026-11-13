import XCTest
@testable import KlimaCore

final class CalendarSuggestionsPlannerTests: XCTestCase {
    private typealias F = CalendarFixtures
    private let stAnton = CalendarFixtures.station("at:47:1222")

    private func plan(_ events: [CalendarEventInput], prefs: CalendarSuggestionPrefs = CalendarFixtures.prefs(),
                      trips: [TripRecord] = [], origin: Station? = nil, now: String = "2026-11-19 08:12") -> [CalendarSuggestion] {
        CalendarSuggestionPlanner.plan(events: events, matcher: F.matcher, prefs: prefs, trips: trips, origin: origin, now: F.date(now))
    }

    // MARK: Acceptance

    /// The demo calendar: twelve occurrences, exactly three cards (by start), the rest filtered for a reason each.
    func testDemoCalendarYieldsTheThreeExpectedCards() {
        let prefs = F.prefs(calendars: [CalendarDemoEvents.workCalendarID, CalendarDemoEvents.homeCalendarID])
        let events = CalendarDemoEvents.events()
        XCTAssertEqual(events.count, 12)
        let cards = CalendarSuggestionPlanner.plan(events: events, matcher: F.matcher, prefs: prefs, trips: [],
                                                   origin: F.station(CalendarDemoEvents.originStationID), now: CalendarDemoEvents.now,
                                                   limit: 10)
        XCTAssertEqual(cards.map(\.title), ["Meeting Linz Hbf", "Konzert Salzburg", "Familienbesuch Bregenz"])
        XCTAssertEqual(cards.map(\.match.station.id), ["at:44:41164", "at:45:50002", "at:48:452"])
        XCTAssertEqual(cards.map(\.match.precision), [.station, .town, .station])
        XCTAssertEqual(cards.map { F.hm($0.arrival) }, ["09:40", "19:10", "11:40"])
    }

    // MARK: Window, all-day, multi-day

    func testWindowAndAllDay() {
        let cards = plan([
            F.event("a", location: "Linz Hbf", start: "2026-11-20 10:00"),
            F.event("b", location: "Graz Hbf", start: "2026-12-03 08:13"),        // 14 days + 1 minute
            F.event("c", location: "Graz Hbf", start: "2026-12-03 08:12"),        // exactly 14 days
            F.event("d", location: "Salzburg Hbf", start: "2026-11-21 00:00", minutes: 1440, allDay: true),
            F.event("e", location: "Wien Hbf", start: "2026-11-18 10:00"),         // yesterday
        ])
        XCTAssertEqual(cards.map(\.eventID), ["a", "c"])
    }

    func testMultiDayEvents() {
        let cards = plan([
            // Starts tomorrow evening, ends Sunday: one card, by its start.
            F.event("weekend", location: "Innsbruck Hbf", start: "2026-11-20 18:00", minutes: 46 * 60),
            // Started yesterday, still running: too late.
            F.event("fair", location: "Wels Hbf", start: "2026-11-18 09:00", minutes: 3 * 24 * 60),
        ])
        XCTAssertEqual(cards.map(\.eventID), ["weekend"])
        XCTAssertEqual(cards.first.map { F.hm($0.arrival) }, "17:40")
    }

    func testArrivalAlreadyPassedGivesNoCard() {
        // Starts in 25 minutes: arriving 20 minutes early would be 5 minutes from now – still possible.
        XCTAssertEqual(plan([F.event("soon", location: "Linz Hbf", start: "2026-11-19 08:37")]).count, 1)
        // Starts in 15 minutes: the arrival would be in the past.
        XCTAssertEqual(plan([F.event("late", location: "Linz Hbf", start: "2026-11-19 08:27")]).count, 0)
    }

    // MARK: Series, cap, duplicates

    func testRecurringEventsSuggestOnlyTheNextOccurrence() {
        let weekly = (0..<3).map { week in
            F.event("weekly", "Chorprobe", location: "Innsbruck Hbf", start: "2026-11-\(20 + 7 * week) 19:00", series: "series-1")
        }.filter { $0.start < F.date("2026-12-03 08:12") }
        XCTAssertEqual(weekly.count, 2)
        let cards = plan(weekly.reversed())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.start, F.date("2026-11-20 19:00"))

        // An occurrence too close to reach is not the "next" one: the following week's takes its place.
        let today = F.event("weekly", "Chorprobe", location: "Innsbruck Hbf", start: "2026-11-19 08:25", series: "series-1")
        XCTAssertEqual(plan([today] + weekly).first?.start, F.date("2026-11-20 19:00"))

        // "Kein Zug" for the next occurrence does not bring the one after it forward.
        var prefs = F.prefs()
        prefs.dismiss(key: weekly[0].key, eventStart: weekly[0].start)
        XCTAssertTrue(plan(weekly, prefs: prefs).isEmpty)
    }

    func testCapAndOneCardPerStationAndDay() {
        let events = [
            F.event("1", location: "Linz Hbf", start: "2026-11-20 10:00"),
            F.event("2", location: "Linz Hauptbahnhof", start: "2026-11-20 15:00"),   // same station, same day
            F.event("3", location: "Salzburg Hbf", start: "2026-11-21 10:00"),
            F.event("4", location: "Graz Hbf", start: "2026-11-22 10:00"),
            F.event("5", location: "Wien Mitte", start: "2026-11-23 10:00"),
        ]
        XCTAssertEqual(plan(events).map(\.eventID), ["1", "3", "4"])
    }

    func testOnlySelectedCalendars() {
        let events = [F.event("1", location: "Linz Hbf", start: "2026-11-20 10:00", calendarID: "work"),
                      F.event("2", location: "Graz Hbf", start: "2026-11-21 10:00", calendarID: "birthdays")]
        XCTAssertEqual(plan(events, prefs: F.prefs(calendars: ["work"])).map(\.eventID), ["1"])
        XCTAssertTrue(plan(events, prefs: F.prefs(calendars: [])).isEmpty)
    }

    // MARK: Trips and origin

    func testEventsAlreadyCoveredByATrip() {
        let events = [F.event("1", location: "Linz Hbf", start: "2026-11-20 10:00"),
                      F.event("2", location: "Mirabellplatz 4, 5020 Salzburg", start: "2026-11-21 19:30")]
        let trips = [F.trip(to: "at:44:41164", name: "Linz Hauptbahnhof", on: "2026-11-20 06:30"),
                     F.trip(to: nil, name: "Salzburg Süd", on: "2026-11-21 17:00")]   // a trip into the town covers a town match
        XCTAssertTrue(plan(events, trips: trips).isEmpty)
        // A trip on another day does not.
        XCTAssertEqual(plan(events, trips: [F.trip(to: "at:44:41164", name: "Linz Hauptbahnhof", on: "2026-11-19 06:30")]).count, 2)
    }

    func testTownYouStartFromNeedsNoCard() {
        let meidling = F.stations.first { $0.name == "Wien Meidling" && $0.kind == .rail }!
        let events = [F.event("doctor", location: "Mariahilfer Straße 1, 1060 Wien", start: "2026-11-20 10:00"),
                      F.event("station", location: "Wien Mitte", start: "2026-11-21 10:00")]
        // From Wien Meidling: the town match is at home, the named station is a ride worth suggesting.
        XCTAssertEqual(plan(events, origin: meidling).map(\.eventID), ["station"])
        // From St. Anton both are trips.
        XCTAssertEqual(plan(events, origin: stAnton).map(\.eventID), ["doctor", "station"])
        // The origin station itself never.
        XCTAssertTrue(plan([F.event("x", location: "Bahnhof St. Anton am Arlberg", start: "2026-11-20 10:00")], origin: stAnton).isEmpty)
    }

    func testMostFrequentOrigin() {
        let trips = [
            F.trip(to: "a", name: "A", on: "2026-11-10 08:00", from: "at:47:1222", fromName: "St. Anton am Arlberg"),
            F.trip(to: "b", name: "B", on: "2026-11-11 08:00", from: "at:47:1187", fromName: "Innsbruck Hauptbahnhof"),
            F.trip(to: "c", name: "C", on: "2026-11-12 08:00", from: "at:47:1222", fromName: "St. Anton am Arlberg"),
            F.trip(to: "d", name: "D", on: "2026-11-13 08:00", from: nil, fromName: "Irgendwo"),
        ]
        XCTAssertEqual(CalendarOrigin.mostFrequent(trips: trips)?.stationID, "at:47:1222")
        // A tie goes to the origin used last.
        let tie = Array(trips.prefix(2))
        XCTAssertEqual(CalendarOrigin.mostFrequent(trips: tie)?.stationID, "at:47:1187")
        XCTAssertNil(CalendarOrigin.mostFrequent(trips: []))
    }

    // MARK: Dismissed, snoozed

    func testDismissedAndSnoozedEventsAreHidden() {
        let events = [F.event("1", location: "Linz Hbf", start: "2026-11-20 10:00"),
                      F.event("2", location: "Graz Hbf", start: "2026-11-21 10:00")]
        var prefs = F.prefs()
        prefs.dismiss(key: events[0].key, eventStart: events[0].start)
        prefs.snooze(key: events[1].key, until: F.date("2026-11-20 07:00"))
        XCTAssertTrue(plan(events, prefs: prefs).isEmpty)
        // The snooze has run out the next morning; the dismissal stays.
        XCTAssertEqual(plan(events, prefs: prefs, now: "2026-11-20 07:01").map(\.eventID), ["2"])
        prefs.undoDismiss(key: events[0].key)
        XCTAssertEqual(plan(events, prefs: prefs, now: "2026-11-20 07:01").map(\.eventID), ["1", "2"])
    }

    // MARK: Time

    func testBufferArithmeticInViennaTime() {
        // 18:30 UTC is 19:30 in Vienna (CET, UTC+1).
        let start = Date(timeIntervalSince1970: 1_795_199_400)   // 2026-11-20T18:30:00Z
        XCTAssertEqual(F.hm(start), "19:30")
        XCTAssertEqual(F.hm(CalendarBuffer.arrival(eventStart: start, bufferMinutes: 10)), "19:20")
        XCTAssertEqual(F.hm(CalendarBuffer.arrival(eventStart: start, bufferMinutes: 20)), "19:10")
        XCTAssertEqual(F.hm(CalendarBuffer.arrival(eventStart: start, bufferMinutes: 30)), "19:00")
        XCTAssertEqual(F.hm(CalendarBuffer.arrival(eventStart: start, bufferMinutes: 45)), "18:45")
        // An unknown buffer falls back to 20 minutes.
        XCTAssertEqual(F.hm(CalendarBuffer.arrival(eventStart: start, bufferMinutes: 7)), "19:10")
    }

    func testBufferAcrossTheDaylightSavingChanges() {
        // 28 March 2027: clocks go from 02:00 to 03:00. An event at 03:20 CEST with 30 minutes buffer → 01:50 CET.
        let spring = F.date("2027-03-28 03:20")
        let arrival = CalendarBuffer.arrival(eventStart: spring, bufferMinutes: 30)
        XCTAssertEqual(spring.timeIntervalSince(arrival), 1800)
        XCTAssertEqual(F.hm(arrival), "01:50")
        // 25 October 2026: 03:00 → 02:00. An event at 02:30 CET (the second 02:30) minus 45 minutes is 02:45 CEST (the first pass).
        let autumn = Date(timeIntervalSince1970: 1_792_891_800)   // 2026-10-25T01:30:00Z = 02:30 CET
        XCTAssertEqual(F.hm(autumn), "02:30")
        let back = CalendarBuffer.arrival(eventStart: autumn, bufferMinutes: 45)
        XCTAssertEqual(autumn.timeIntervalSince(back), 2700)
        XCTAssertEqual(F.hm(back), "02:45")   // 00:45Z = 02:45 CEST, before the clocks went back
    }

    func testSnoozeComesBackNextMorningOrBeforeTheArrival() {
        let now = F.date("2026-11-19 20:00")
        // Arrival in three days: tomorrow 07:00.
        XCTAssertEqual(CalendarSnooze.until(now: now, arrival: F.date("2026-11-22 10:00")), F.date("2026-11-20 07:00"))
        // Arrival tomorrow 08:00: three hours before it (05:00).
        XCTAssertEqual(CalendarSnooze.until(now: now, arrival: F.date("2026-11-20 08:00")), F.date("2026-11-20 05:00"))
        // Arrival tonight 22:30: never sooner than in one hour.
        XCTAssertEqual(CalendarSnooze.until(now: now, arrival: F.date("2026-11-19 22:30")), F.date("2026-11-19 21:00"))
    }

    // MARK: Speed

    func testFiveHundredEventsInUnderFiftyMilliseconds() {
        let locations = ["Linz Hbf", "Zoom", "Mirabellplatz 4, 5020 Salzburg", "Büro", "Wien", "Neumarkt", "Hauptbahnhof Salzburg",
                         "Großes Festspielhaus, Hofstallgasse 1, 5020 Salzburg, Österreich", "Lech am Arlberg", "",
                         "Westbahnhof, 1150 Wien", "Microsoft Teams-Besprechung"]
        let start = F.date("2026-11-19 09:00")
        var events: [CalendarEventInput] = []
        for i in 0..<500 {
            let begin = start.addingTimeInterval(Double(i) * 1700)
            let series: String? = i % 7 == 0 ? "s\(i % 21)" : nil
            // A third of the places are written only once (a new address each time), the rest repeat like a real calendar.
            let location = i % 3 == 0 ? "Musterweg \(i), \(4000 + i) Ort \(i)" : locations[i % locations.count]
            events.append(CalendarEventInput(id: "e\(i)", title: "Termin \(i)", location: location, start: begin,
                                             end: begin.addingTimeInterval(3600), calendarID: "cal", seriesID: series))
        }
        _ = plan(Array(events.prefix(20)))   // warm up the catalog and the formatters
        var best = Double.infinity
        for _ in 0..<3 {
            let t0 = Date()
            _ = CalendarSuggestionPlanner.plan(events: events, matcher: F.matcher, prefs: F.prefs(), trips: [], origin: stAnton,
                                               now: F.date("2026-11-19 08:12"), limit: 500)
            best = min(best, Date().timeIntervalSince(t0))
        }
        print("calendar suggestions: 500 events in \(Int(best * 1000)) ms")
        XCTAssertLessThan(best, 0.05, "500 events took \(Int(best * 1000)) ms")
    }
}
