import Foundation

// Automatik (docs/AUTOMATION.md): the six ready-made rules of „Vorlagen“. Five are rules; „Wochenende ruhig“ is the book's
// switch that keeps every rule quiet on Saturday and Sunday.

public struct AutoTemplate: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    /// The trigger's kind (icon and tint); nil for „Wochenende ruhig“.
    public var kind: AutoTriggerKind?

    /// The rule this template switches on; nil for „Wochenende ruhig“ (a switch of the book, not a rule).
    public func makeRule(now: Date) -> AutoRule? {
        switch id {
        case AutoTemplates.deadlineID:
            return AutoRule(name: "30 Tage vor Ablauf", trigger: .ticketDeadline(daysBefore: 30), createdAt: now, templateID: id)
        case AutoTemplates.milestonesID:
            return AutoRule(name: "Meilensteine feiern", trigger: .milestone(percents: [50, 75, 100]), createdAt: now, templateID: id)
        case AutoTemplates.eveningID:
            return AutoRule(name: "Abendcheck", trigger: .dayWithoutTrip(weekdays: AutoClock.workdays, minuteOfDay: 19 * 60),
                            actions: [.notify(title: "", body: ""), .openAddTrip(fromStationID: nil, toStationID: nil)],
                            createdAt: now, templateID: id)
        case AutoTemplates.delayID:
            return AutoRule(name: "Verspätung melden", trigger: .followDelay(minutes: 10), cooldownMinutes: 30, createdAt: now, templateID: id)
        case AutoTemplates.bigTripID:
            return AutoRule(name: "Große Fahrt", trigger: .tripLogged(AutoTripFilter(minValueEUR: 20)), createdAt: now, templateID: id)
        default:
            return nil
        }
    }
}

public enum AutoTemplates {
    public static let deadlineID = "deadline30"
    public static let milestonesID = "milestones"
    public static let eveningID = "evening19"
    public static let delayID = "delay10"
    public static let bigTripID = "trip20"
    public static let quietWeekendID = "quietWeekend"

    public static let all: [AutoTemplate] = [
        AutoTemplate(id: deadlineID, title: "30 Tage vor Ablauf erinnern",
                     subtitle: "Um 09:00, 30 Tage bevor dein Ticket abläuft", kind: .ticketDeadline),
        AutoTemplate(id: milestonesID, title: "Bei 50, 75 und 100 % gratulieren",
                     subtitle: "Einmal pro Ticket, nach dem Speichern einer Fahrt", kind: .milestone),
        AutoTemplate(id: eveningID, title: "Werktags um 19:00 erinnern",
                     subtitle: "Nur wenn an dem Tag noch keine Fahrt erfasst ist", kind: .dayWithoutTrip),
        AutoTemplate(id: delayID, title: "Ab 10 Min Verspätung informieren",
                     subtitle: "Während „Live verfolgen“ läuft, ohne zusätzliche Abfrage", kind: .followDelay),
        AutoTemplate(id: bigTripID, title: "Nach jeder Fahrt ab € 20",
                     subtitle: "Ein kurzes Feedback nach dem Speichern", kind: .tripLogged),
        AutoTemplate(id: quietWeekendID, title: "Wochenende ruhig",
                     subtitle: "Samstag und Sonntag meldet sich keine Regel", kind: nil),
    ]

    public static func template(_ id: String) -> AutoTemplate? { all.first { $0.id == id } }
}
