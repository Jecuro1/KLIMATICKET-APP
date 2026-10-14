import Foundation
import UserNotifications
import KlimaCore

// Demo scenes of the Alarms screen (`-KBDemo`, CI screenshots `alarmsList` and `alarmHistory`): fixed values, no system
// notifications, no network. The times are relative to now, so the scene always reads as current.

enum AlarmsDemoScene {
    case list
    case history

    var authorization: UNAuthorizationStatus { .authorized }
    var pendingCount: Int { 9 }

    var items: [AlarmItem] {
        let now = Date()
        let vienna = AlarmCalendar.vienna
        func at(days: Int, hour: Int, minute: Int) -> Date? {
            guard let day = vienna.date(byAdding: .day, value: days, to: now) else { return nil }
            return vienna.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }
        return [
            AlarmItem(id: "liveFollow", kind: .liveFollow, title: "Live verfolgen · RJ 66",
                      detail: "St. Anton → Innsbruck Hbf", nextDate: now.addingTimeInterval(35 * 60), isOn: true),
            AlarmItem(id: "planner.reminder.demo-landeck", kind: .departure, title: "Abfahrt in 10 Min",
                      detail: "Landeck Zams → Innsbruck Hbf · RJ 66", nextDate: now.addingTimeInterval(3 * 3600), isOn: true),
            AlarmItem(id: "route.DEMO-ARBEIT", kind: .routeReminder, title: "Arbeit",
                      detail: "Abfahrt in 10 Min", nextDate: at(days: 1, hour: 7, minute: 20),
                      scheduleText: "Mo–Fr · 07:20", isOn: true),
            AlarmItem(id: "renewal.DEMO-TICKET", kind: .ticketRenewal, title: "Noch 30 Tage gültig",
                      detail: "KlimaTicket Ö Klassik läuft bald ab. Denk an die Verlängerung.",
                      nextDate: at(days: 2, hour: 9, minute: 0), isOn: true),
            AlarmItem(id: "advisor.renewal.DEMO-TICKET", kind: .objectionLetter, title: "Dein Verlängerungsbrief kommt bald",
                      detail: "Das Ticket verlängert sich automatisch. Widersprich bis zur Frist im Brief.",
                      nextDate: at(days: 9, hour: 9, minute: 0), isOn: true),
            AlarmItem(id: "weekly.summary", kind: .weeklySummary, title: "Wochenrückblick",
                      detail: "Wie viel du diese Woche gespart hast und ob alle Fahrten erfasst sind.",
                      nextDate: at(days: 3, hour: 18, minute: 0), scheduleText: "So · 18:00", isOn: true),
            AlarmItem(id: "route.DEMO-LANDECK", kind: .routeReminder, title: "Landeck",
                      detail: "Pausiert · Abfahrt in 10 Min", nextDate: at(days: 5, hour: 8, minute: 5),
                      scheduleText: "Sa–So · 08:15", isOn: false, canResume: true),
            AlarmItem(id: "perk.passengerRights.DEMO-TICKET", kind: .passengerRights,
                      title: "Fahrgastrechte: Entschädigung prüfen",
                      detail: "Der Termin liegt in der Vergangenheit.", nextDate: nil, isOn: false, canResume: false),
        ]
    }

    var history: [DeliveredNotice] {
        let now = Date()
        func notice(_ id: String, _ title: String, _ body: String, minutesAgo: Double) -> DeliveredNotice {
            NoticeHistoryStore.notice(identifier: id, title: title, body: body, date: now.addingTimeInterval(-minutesAgo * 60))
        }
        return [
            notice("livefollow-demo-7", "Verspätung +6 Min", "RJ 66 · Landeck Zams", minutesAgo: 18),
            notice("route.DEMO-ARBEIT.0", "Abfahrt in 10 Min", "Arbeit · St. Anton → Innsbruck", minutesAgo: 60 * 14),
            notice("livefollow-demo-6", "Gleis geändert", "Innsbruck Hbf: Gleis 3 → 5", minutesAgo: 60 * 26),
            notice("weekly.summary", "Deine Woche mit den Öffis", "Schau nach, wie viel du diese Woche gespart hast.", minutesAgo: 60 * 24 * 3),
            notice("renewal.DEMO-TICKET.30", "Noch 30 Tage gültig", "KlimaTicket Ö Klassik läuft bald ab.", minutesAgo: 60 * 24 * 5),
            notice("route.DEMO-ARBEIT.2", "Abfahrt in 10 Min", "Arbeit · St. Anton → Innsbruck", minutesAgo: 60 * 24 * 6),
            notice("livefollow-demo-5", "Angekommen", "RJ 66 in Innsbruck Hbf", minutesAgo: 60 * 24 * 6 + 40),
            notice("breakeven.KlimaTicket", "Geschafft: dein Ticket hat sich rentiert", "KlimaTicket Ö Klassik hat sich bezahlt gemacht.", minutesAgo: 60 * 24 * 9),
            notice("planner.reminder.demo-bludenz", "Abfahrt in 15 Min", "Bludenz → Feldkirch", minutesAgo: 60 * 24 * 11),
            notice("route.DEMO-ARBEIT.4", "Abfahrt in 10 Min", "Arbeit · St. Anton → Innsbruck", minutesAgo: 60 * 24 * 12),
            notice("livefollow-demo-4", "Zug fällt aus", "REX 5 ab Landeck Zams", minutesAgo: 60 * 24 * 15),
            notice("advisor.renewal.DEMO-TICKET", "Dein Verlängerungsbrief kommt bald", "Widersprich bis zur Frist im Brief.", minutesAgo: 60 * 24 * 20),
        ]
    }
}
