import Foundation

// MARK: calendarsuggestions – the fictional calendar of the demo and the CI scenes (`-KBDemo YES`), shared with the Linux tests so both
// see the same twelve events: three become cards, nine show why the others do not (docs/CALENDAR_SUGGESTIONS.md §6).
// The demo traveller starts in St. Anton am Arlberg (the demo trips' most frequent origin).

public enum CalendarDemoEvents {
    public static let workCalendarID = "demo.calendar.work"
    public static let homeCalendarID = "demo.calendar.home"
    public static let birthdaysCalendarID = "demo.calendar.birthdays"

    /// Thursday, 19 November 2026, 08:12 in Vienna – the pinned clock of the CI scenes.
    public static let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 19; c.hour = 8; c.minute = 12
        return Calendar.vienna.date(from: c) ?? Date(timeIntervalSince1970: 1_795_072_320)
    }()

    /// The calendars the picker offers (birthdays and subscriptions are left out by the source) and the default one.
    public static let calendars: [CalendarInfo] = [
        CalendarInfo(id: workCalendarID, title: "Arbeit", sourceTitle: "iCloud", colorHex: "#2A7BD4", isDefault: true),
        CalendarInfo(id: homeCalendarID, title: "Privat", sourceTitle: "iCloud", colorHex: "#E86C8A"),
        CalendarInfo(id: "demo.calendar.club", title: "Skiclub", sourceTitle: "Auf meinem iPhone", colorHex: "#23876A"),
    ]

    /// Twelve occurrences around `now` (the weekly Jour fixe twice). Cards: Meeting Linz Hbf (station), Konzert Salzburg (town),
    /// Familienbesuch Bregenz (station).
    public static func events(now: Date = now, calendar: Calendar = .vienna) -> [CalendarEventInput] {
        func at(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let work = workCalendarID, home = homeCalendarID
        return [
            CalendarEventInput(id: "demo-1", title: "Meeting Linz Hbf", location: "Linz Hbf",
                               start: at(1, 10), end: at(1, 11, 30), calendarID: work),
            CalendarEventInput(id: "demo-2", title: "Konzert Salzburg",
                               location: "Großes Festspielhaus, Hofstallgasse 1, 5020 Salzburg, Österreich",
                               start: at(2, 19, 30), end: at(2, 22), calendarID: home),
            CalendarEventInput(id: "demo-3", title: "Familienbesuch Bregenz", location: "Bahnhof Bregenz",
                               start: at(5, 12), end: at(5, 18), calendarID: home),
            // Lech has no rail station: precision over recall, no card.
            CalendarEventInput(id: "demo-4", title: "Skitag Lech", location: "Lech am Arlberg",
                               start: at(3, 9), end: at(3, 16), calendarID: home),
            CalendarEventInput(id: "demo-5", title: "Teamcall", location: "Zoom", start: at(0, 14), end: at(0, 15), calendarID: work),
            CalendarEventInput(id: "demo-6", title: "Urlaub", location: "Salzburg", start: at(7, 0), end: at(9, 0), isAllDay: true,
                               calendarID: home),
            // A weekly series in the office: two occurrences in the window, neither is a place.
            CalendarEventInput(id: "demo-7", title: "Jour fixe", location: "Büro", start: at(5, 9), end: at(5, 10), calendarID: work,
                               seriesID: "demo-series-jourfixe"),
            CalendarEventInput(id: "demo-7", title: "Jour fixe", location: "Büro", start: at(12, 9), end: at(12, 10), calendarID: work,
                               seriesID: "demo-series-jourfixe"),
            CalendarEventInput(id: "demo-8", title: "Yoga", location: "Arlbergstraße 12", start: at(1, 18), end: at(1, 19), calendarID: home),
            // In the town you start from: no train needed.
            CalendarEventInput(id: "demo-9", title: "Abendessen", location: "Hotel Post, St. Anton am Arlberg",
                               start: at(2, 18), end: at(2, 21), calendarID: home),
            // Started yesterday: too late for a suggestion.
            CalendarEventInput(id: "demo-10", title: "Messe Wels", location: "Messeplatz 1, 4600 Wels",
                               start: at(-1, 9), end: at(1, 17), calendarID: work),
            // Two Neumarkts with a station: ambiguous, no card.
            CalendarEventInput(id: "demo-11", title: "Besprechung", location: "Neumarkt", start: at(4, 15), end: at(4, 16),
                               calendarID: work),
        ]
    }

    /// The demo traveller's origin: St. Anton am Arlberg.
    public static let originStationID = "at:47:1222"
}
