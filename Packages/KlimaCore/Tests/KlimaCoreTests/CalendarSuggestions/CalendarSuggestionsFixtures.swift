import Foundation
import XCTest
@testable import KlimaCore

/// The shipped station list (App/Resources/stations.json) as the matcher's catalog, and Vienna dates.
enum CalendarFixtures {
    static let stations: [Station] = {
        let url = PlaceFixtures.resources.appendingPathComponent("stations.json")
        guard let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Station].self, from: data) else {
            fatalError("cannot read \(url.path)")
        }
        return list
    }()

    static let catalog = CalendarStationCatalog(stations: stations)
    static let matcher = CalendarTripMatcher(catalog: catalog)

    static func station(_ id: String) -> Station {
        guard let s = stations.first(where: { $0.id == id }) else { fatalError("no station \(id)") }
        return s
    }

    /// "2026-11-20 19:30" in Europe/Vienna.
    static func date(_ text: String, calendar: Calendar = .vienna) -> Date {
        let parts = text.split(separator: " ")
        let d = parts[0].split(separator: "-").compactMap { Int($0) }
        let t = parts.count > 1 ? parts[1].split(separator: ":").compactMap { Int($0) } : [0, 0]
        var c = DateComponents()
        c.year = d[0]; c.month = d[1]; c.day = d[2]; c.hour = t[0]; c.minute = t[1]
        guard let date = calendar.date(from: c) else { fatalError("bad date \(text)") }
        return date
    }

    static func event(_ id: String, _ title: String = "Termin", location: String?, start: String, minutes: Int = 60,
                      allDay: Bool = false, calendarID: String = "cal", series: String? = nil) -> CalendarEventInput {
        let s = date(start)
        return CalendarEventInput(id: id, title: title, location: location, start: s, end: s.addingTimeInterval(Double(minutes) * 60),
                                  isAllDay: allDay, calendarID: calendarID, seriesID: series)
    }

    static func prefs(calendars: [String] = ["cal"], buffer: Int = 20) -> CalendarSuggestionPrefs {
        var p = CalendarSuggestionPrefs()
        p.isEnabled = true
        p.calendarIDs = calendars
        p.hasPickedCalendars = true
        p.bufferMinutes = buffer
        return p
    }

    static func trip(to id: String?, name: String, on text: String, from fromID: String? = "at:47:1222",
                     fromName: String = "St. Anton am Arlberg") -> TripRecord {
        TripRecord(date: date(text), fromName: fromName, toName: name, fromStationID: fromID, toStationID: id, mode: .train,
                   distanceKm: 100, fareEUR: 20)
    }

    static func hm(_ date: Date, calendar: Calendar = .vienna) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
