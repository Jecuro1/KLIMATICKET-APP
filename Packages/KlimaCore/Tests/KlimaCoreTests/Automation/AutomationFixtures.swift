import Foundation
@testable import KlimaCore

/// Builders for the Automatik tests: Vienna dates, a ticket, trips and a follow.
enum AutomationFixtures {
    static let vienna: Calendar = .vienna

    static func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        vienna.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)) ?? .distantPast
    }

    /// The UTC wall clock of a moment ("2026-03-29 17:00"), to pin a daylight-saving result to the instant.
    static func utc(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let p = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0, p.hour ?? 0, p.minute ?? 0)
    }

    /// KlimaTicket Ö Klassik, valid 1 Mar 2026 – 28 Feb 2027 (the last second of the day before the anniversary).
    static func ticket(fraction: Double = 0.61, id: String = "T-2026", start: Date = at(2026, 3, 1),
                       end: Date = at(2027, 2, 28, 23, 59, 59)) -> AutoTicketFact {
        AutoTicketFact(id: id, name: "KlimaTicket Ö Klassik", start: start, end: end, amortizedFraction: fraction,
                       price: 1400, value: 1400 * fraction)
    }

    static func trip(_ value: Double, at date: Date, created: Date? = nil, from: String = "St. Anton am Arlberg",
                     to: String = "Innsbruck Hbf", fromID: String? = "at:81:1", toID: String? = "at:81:2",
                     modes: Set<TransportMode> = [.train]) -> AutoTripFact {
        AutoTripFact(id: UUID(), date: date, createdAt: created ?? date, fromName: from, toName: to, fromStationID: fromID,
                     toStationID: toID, modes: modes, value: value)
    }

    static func follow(delay: Int?, trip: String = "1|RJ66|0", finished: Bool = false, at date: Date) -> AutoFollowFact {
        AutoFollowFact(tripID: trip, lineName: "RJ 66", stopName: "Innsbruck Hbf", delayMinutes: delay, isFinished: finished, updatedAt: date)
    }

    static func rule(_ trigger: AutoTrigger, conditions: [AutoCondition] = [], cooldown: Int = 0, name: String = "Regel",
                     actions: [AutoAction] = [.notify(title: "", body: "")], id: UUID = UUID()) -> AutoRule {
        AutoRule(id: id, name: name, trigger: trigger, conditions: conditions, actions: actions, cooldownMinutes: cooldown,
                 createdAt: at(2026, 11, 1))
    }

    static func dayKeys(_ dates: Date...) -> Set<String> {
        Set(dates.map { AutoClock.dayKey($0, calendar: vienna) })
    }
}
