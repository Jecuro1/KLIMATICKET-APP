import XCTest
@testable import KlimaCore

// MARK: calendarsuggestions – the review's cases (docs/CALENDAR_SUGGESTIONS.md §11): midnight, both ends of a trip, a follow-up only
// for an event still in the calendar, the clock-driven refresh, „Alle Daten löschen“, entries written before the review.

final class CalendarSuggestionsReviewTests: XCTestCase {
    private typealias F = CalendarFixtures
    private let linz = "at:44:41164"

    private func plan(_ events: [CalendarEventInput], prefs: CalendarSuggestionPrefs = CalendarFixtures.prefs(),
                      trips: [TripRecord] = [], now: String = "2026-11-19 08:12") -> [CalendarSuggestion] {
        CalendarSuggestionPlanner.plan(events: events, matcher: F.matcher, prefs: prefs, trips: trips, origin: nil, now: F.date(now))
    }

    // MARK: Midnight

    func testEventJustAfterMidnightIsCoveredByATripTheEveningBefore() {
        // 00:10 on Saturday, 20 minutes buffer: the train arrives at 23:50 on Friday.
        let late = F.event("late", location: "Linz Hbf", start: "2026-11-21 00:10")
        let card = plan([late]).first
        XCTAssertEqual(card.map { F.hm($0.arrival) }, "23:50")
        XCTAssertTrue(card.map { Calendar.vienna.isDate($0.arrival, inSameDayAs: F.date("2026-11-20 12:00")) } ?? false)
        // Logged on Friday evening (the day of the arrival): no card.
        XCTAssertTrue(plan([late], trips: [F.trip(to: linz, name: "Linz Hauptbahnhof", on: "2026-11-20 22:40")]).isEmpty)
        // Logged on Saturday (the day of the event): no card either.
        XCTAssertTrue(plan([late], trips: [F.trip(to: linz, name: "Linz Hauptbahnhof", on: "2026-11-21 00:05")]).isEmpty)
        // A trip on Thursday does not cover it.
        XCTAssertEqual(plan([late], trips: [F.trip(to: linz, name: "Linz Hauptbahnhof", on: "2026-11-19 22:40")]).count, 1)
    }

    func testFollowUpDayIsTheEventsDayNotTheArrivalsDay() {
        var prefs = F.prefs()
        prefs.followUps["k"] = CalendarFollowUpEntry(stationID: linz, stationName: "Linz Hauptbahnhof", arrival: F.date("2026-11-20 23:50"),
                                                     eventStart: F.date("2026-11-21 00:10"))
        // Saturday is the event's day: no question yet.
        XCTAssertTrue(CalendarFollowUpPlanner.pending(prefs: prefs, trips: [], now: F.date("2026-11-21 20:00")).isEmpty)
        // Sunday and Monday ask, Tuesday no more.
        XCTAssertEqual(CalendarFollowUpPlanner.pending(prefs: prefs, trips: [], now: F.date("2026-11-22 08:00")).map(\.key), ["k"])
        XCTAssertEqual(CalendarFollowUpPlanner.pending(prefs: prefs, trips: [], now: F.date("2026-11-23 22:00")).map(\.key), ["k"])
        XCTAssertTrue(CalendarFollowUpPlanner.pending(prefs: prefs, trips: [], now: F.date("2026-11-24 00:01")).isEmpty)
        // The trip logged on Friday evening answers it.
        let friday = F.trip(to: linz, name: "Linz Hauptbahnhof", on: "2026-11-20 22:40")
        XCTAssertTrue(CalendarFollowUpPlanner.pending(prefs: prefs, trips: [friday], now: F.date("2026-11-22 08:00")).isEmpty)
        // Pruning keeps it while it may still ask (by the event's day).
        var pruned = prefs
        pruned.prune(now: F.date("2026-11-23 22:00"))
        XCTAssertNotNil(pruned.followUps["k"])
        pruned.prune(now: F.date("2026-11-24 00:01"))
        XCTAssertNil(pruned.followUps["k"])
    }

    // MARK: Both ends of a trip

    func testATripFromTheStationThatDayAnswersTheFollowUp() {
        var prefs = F.prefs()
        prefs.followUps["k"] = CalendarFollowUpEntry(stationID: linz, stationName: "Linz Hauptbahnhof", arrival: F.date("2026-11-20 09:40"),
                                                     eventStart: F.date("2026-11-20 10:00"))
        // Only the way home was logged: Linz → St. Anton.
        let home = F.trip(to: "at:47:1222", name: "St. Anton am Arlberg", on: "2026-11-20 17:00", from: linz, fromName: "Linz Hauptbahnhof")
        XCTAssertTrue(CalendarFollowUpPlanner.pending(prefs: prefs, trips: [home], now: F.date("2026-11-21 08:00")).isEmpty)
        // A trip between two other places does not.
        let other = F.trip(to: "at:47:1222", name: "St. Anton am Arlberg", on: "2026-11-20 17:00", from: "at:47:1187",
                           fromName: "Innsbruck Hauptbahnhof")
        XCTAssertEqual(CalendarFollowUpPlanner.pending(prefs: prefs, trips: [other], now: F.date("2026-11-21 08:00")).count, 1)
    }

    // MARK: Event still in the calendar

    func testFollowUpsAreKeptOnlyForEventsStillInTheCalendar() {
        var prefs = F.prefs()
        let entry = CalendarFollowUpEntry(stationID: linz, stationName: "Linz Hauptbahnhof", arrival: F.date("2026-11-18 09:40"))
        prefs.followUps = ["kept": entry, "deleted": entry, "moved": entry]
        prefs.keepFollowUps(eventKeys: ["kept", "unrelated"])
        XCTAssertEqual(Set(prefs.followUps.keys), ["kept"])
        // Nothing read (calendar unticked or emptied): nothing to ask about.
        prefs.keepFollowUps(eventKeys: [])
        XCTAssertTrue(prefs.followUps.isEmpty)
    }

    func testMovingAnEventChangesItsKey() {
        // The key is the hash of identifier and start: the old follow-up does not match the moved event.
        let before = F.event("e", location: "Linz Hbf", start: "2026-11-18 10:00")
        var after = before
        after.start = F.date("2026-11-25 10:00")
        XCTAssertNotEqual(before.key, after.key)
    }

    func testReadStartCoversEveryEventAFollowUpMayAskAbout() {
        let now = F.date("2026-11-19 08:12")
        let start = CalendarFollowUpPlanner.readStart(now: now)
        XCTAssertEqual(start, F.date("2026-11-16 00:00"))
        // The oldest follow-up still asked about: an event at 00:00 two days ago.
        XCTAssertLessThanOrEqual(start, F.date("2026-11-17 00:00"))
    }

    // MARK: Demo

    func testDemoFollowUpEventIsNoCardAndKeepsItsFollowUp() {
        let prefs = F.prefs(calendars: [CalendarDemoEvents.workCalendarID, CalendarDemoEvents.homeCalendarID])
        let past = CalendarDemoEvents.followUpEvent()
        let events = CalendarDemoEvents.events() + [past]
        XCTAssertGreaterThanOrEqual(past.start, CalendarFollowUpPlanner.readStart(now: CalendarDemoEvents.now))
        let cards = CalendarSuggestionPlanner.plan(events: events, matcher: F.matcher, prefs: prefs, trips: [],
                                                   origin: F.station(CalendarDemoEvents.originStationID), now: CalendarDemoEvents.now)
        XCTAssertEqual(cards.map(\.title), ["Meeting Linz Hbf", "Konzert Salzburg", "Familienbesuch Bregenz"])

        var withFollowUp = prefs
        let demo = CalendarDemoEvents.followUp()
        withFollowUp.followUps[demo.key] = demo.entry
        withFollowUp.keepFollowUps(eventKeys: Set(events.map(\.key)))
        let pending = CalendarFollowUpPlanner.pending(prefs: withFollowUp, trips: [], now: CalendarDemoEvents.now)
        XCTAssertEqual(pending.map(\.key), [demo.key])
        XCTAssertEqual(pending.first.map { F.hm($0.entry.arrival) }, "09:40")
        XCTAssertEqual(F.hm(demo.entry.day), "10:00")
    }

    // MARK: Clock

    func testNextChangeIsTheEarliestArrivalSnoozeOrMidnight() {
        let now = F.date("2026-11-19 08:12")
        var prefs = F.prefs()
        // Nothing on the cards: midnight in Vienna.
        XCTAssertEqual(CalendarSuggestionPlanner.nextChange(suggestions: [], prefs: prefs, now: now), F.date("2026-11-20 00:00"))
        // A card arriving at 09:40 today.
        let cards = plan([F.event("a", location: "Linz Hbf", start: "2026-11-19 10:00"),
                          F.event("b", location: "Graz Hbf", start: "2026-11-20 10:00")])
        XCTAssertEqual(CalendarSuggestionPlanner.nextChange(suggestions: cards, prefs: prefs, now: now), F.date("2026-11-19 09:40"))
        // A „Später“ that runs out earlier.
        prefs.snooze(key: "x", until: F.date("2026-11-19 09:00"))
        XCTAssertEqual(CalendarSuggestionPlanner.nextChange(suggestions: cards, prefs: prefs, now: now), F.date("2026-11-19 09:00"))
        // Never sooner than a minute (an arrival a few seconds away).
        let soon = F.date("2026-11-19 09:39").addingTimeInterval(50)
        XCTAssertEqual(CalendarSuggestionPlanner.nextChange(suggestions: cards, prefs: F.prefs(), now: soon), soon.addingTimeInterval(60))
        // Across the change to summer time: midnight is still the next Vienna midnight.
        let spring = F.date("2027-03-27 20:00")
        XCTAssertEqual(CalendarSuggestionPlanner.nextChange(suggestions: [], prefs: F.prefs(), now: spring), F.date("2027-03-28 00:00"))
    }

    // MARK: Reset and old entries

    func testForgetEventsKeepsTheSettings() {
        var prefs = F.prefs(calendars: ["a"], buffer: 30)
        prefs.dismiss(key: "d", eventStart: F.date("2026-11-20 10:00"))
        prefs.snooze(key: "s", until: F.date("2026-11-20 07:00"))
        prefs.followUps["f"] = CalendarFollowUpEntry(stationID: linz, stationName: "Linz Hauptbahnhof", arrival: F.date("2026-11-18 09:40"))
        prefs.forgetEvents()
        XCTAssertTrue(prefs.dismissed.isEmpty && prefs.snoozed.isEmpty && prefs.followUps.isEmpty)
        XCTAssertTrue(prefs.isEnabled)
        XCTAssertEqual(prefs.calendarIDs, ["a"])
        XCTAssertEqual(prefs.bufferMinutes, 30)
    }

    func testFollowUpWrittenBeforeTheReviewDecodesWithoutEventStart() throws {
        let json = #"{"followUps":{"k":{"stationID":"at:44:41164","stationName":"Linz Hauptbahnhof","arrival":785000000}}}"#
        let prefs = try JSONDecoder().decode(CalendarSuggestionPrefs.self, from: Data(json.utf8))
        let entry = try XCTUnwrap(prefs.followUps["k"])
        XCTAssertNil(entry.eventStart)
        XCTAssertEqual(entry.day, entry.arrival)
        // And the new field round-trips.
        var next = prefs
        next.followUps["k"]?.eventStart = F.date("2026-11-20 10:00")
        XCTAssertEqual(try JSONDecoder().decode(CalendarSuggestionPrefs.self, from: JSONEncoder().encode(next)), next)
    }
}
