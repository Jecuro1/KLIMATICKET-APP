import AppIntents
import SwiftUI
import KlimaCore

// MARK: siri – „Frag KlimaBilanz“ (docs/SIRI_QUESTIONS.md §5): a figure for a period by voice or in a Kurzbefehl. The intent reads the
// table the app wrote (SiriKpiFile) and never opens the SwiftData store or the network; the answer is KlimaCore's KpiAnswer, the same
// one Einstellungen › Fragen an KlimaBilanz shows. It returns the written figure as text, so a Kurzbefehl can pass it on.

/// What one can ask. The cases mirror KlimaCore's `KpiQuestion` (raw values are stored by the Kurzbefehle-App – never rename one).
enum AskKlimaQuestion: String, AppEnum {
    case trips, value, distance, co2, net, daysLeft, breakEven, costPerDay

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Frage"

    // Titles are the Übersicht's tile titles (KpiKind.title); the synonyms are what people say („… in KlimaBilanz“).
    static let caseDisplayRepresentations: [AskKlimaQuestion: DisplayRepresentation] = [
        .trips: DisplayRepresentation(title: "Fahrten", image: .init(systemName: "tram.fill"),
                                      synonyms: ["Wie viele Fahrten", "Anzahl der Fahrten", "Meine Fahrten"]),
        .value: DisplayRepresentation(title: "Wert deiner Fahrten", image: .init(systemName: "eurosign.circle.fill"),
                                      synonyms: ["Wert meiner Fahrten", "Wie viel waren meine Fahrten wert", "Fahrtwert"]),
        .distance: DisplayRepresentation(title: "Kilometer", image: .init(systemName: "point.topleft.down.to.point.bottomright.curvepath"),
                                         synonyms: ["Wie viele Kilometer", "Wie weit bin ich gefahren", "Strecke"]),
        .co2: DisplayRepresentation(title: "CO₂ gespart", image: .init(systemName: "leaf.fill"),
                                    synonyms: ["Wie viel CO₂ habe ich gespart", "Wie viel CO2 habe ich gespart", "Wie viel CO2", "CO2 gespart",
                                               "CO2 Ersparnis", "CO zwei"]),
        .net: DisplayRepresentation(title: "Ersparnis nach Ticketkosten", image: .init(systemName: "plus.forwardslash.minus"),
                                    synonyms: ["Bin ich im Plus", "Plus oder Minus", "Ersparnis nach Ticketpreis"]),
        .daysLeft: DisplayRepresentation(title: "Tage bis Ablauf", image: .init(systemName: "hourglass"),
                                         synonyms: ["Wann läuft mein Ticket ab", "Wie lange gilt mein Ticket", "Ablauf meines Tickets"]),
        .breakEven: DisplayRepresentation(title: "Fehlt bis Break-even", image: .init(systemName: "flag.checkered"),
                                          synonyms: ["Wie viel fehlt bis zum Break-even", "Wie viel fehlt noch", "Was fehlt noch"]),
        .costPerDay: DisplayRepresentation(title: "Kosten pro Tag", image: .init(systemName: "ticket.fill"),
                                           synonyms: ["Was kostet mein Ticket pro Tag", "Ticketkosten pro Tag", "Preis pro Tag"]),
    ]

    var question: KpiQuestion { KpiQuestion(rawValue: rawValue) ?? .trips }
}

/// For which time. Mirrors KlimaCore's `KpiPeriod`.
enum AskKlimaPeriod: String, AppEnum {
    case thisWeek, thisMonth, lastMonth, ticketYear, calendarYear

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Zeitraum"

    static let caseDisplayRepresentations: [AskKlimaPeriod: DisplayRepresentation] = [
        .thisWeek: DisplayRepresentation(title: "Diese Woche", synonyms: ["in dieser Woche", "die Woche"]),
        .thisMonth: DisplayRepresentation(title: "Dieser Monat", synonyms: ["diesen Monat", "in diesem Monat", "im aktuellen Monat"]),
        .lastMonth: DisplayRepresentation(title: "Letzter Monat", synonyms: ["letzten Monat", "im letzten Monat", "im Vormonat"]),
        .ticketYear: DisplayRepresentation(title: "Ticketjahr", synonyms: ["im Ticketjahr", "dieses Ticketjahr", "seit Ticketbeginn"]),
        .calendarYear: DisplayRepresentation(title: "Kalenderjahr", synonyms: ["dieses Jahr", "heuer", "im Kalenderjahr"]),
    ]

    var period: KpiPeriod { KpiPeriod(rawValue: rawValue) ?? .ticketYear }
}

struct AskKlimaIntent: AppIntent {
    static let title: LocalizedStringResource = "Frag KlimaBilanz"
    static let description = IntentDescription(
        "Sagt dir eine Zahl aus KlimaBilanz – Fahrten, Wert, Kilometer, CO₂ oder dein Ticket – für den Zeitraum, den du wählst. Die Antwort entsteht auf deinem iPhone aus Tagessummen, ohne Haltestellen und Orte. Was ein Kurzbefehl danach mit der Zahl macht, bestimmst du.",
        categoryName: "Zahlen", searchKeywords: ["Fahrten", "CO₂", "Kilometer", "Ticket", "Statistik"], resultValueName: "Antwort")

    // Defaults: a phrase names one of the two („Wie viele Fahrten diesen Monat“ → the period, „Wie viel CO₂ habe ich gespart“ →
    // the question); the other keeps its default, so Siri never has to ask back.
    @Parameter(title: "Frage", default: .trips)
    var question: AskKlimaQuestion

    @Parameter(title: "Zeitraum", default: .ticketYear)
    var period: AskKlimaPeriod

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$question) für \(\.$period)")
    }

    init() {}

    init(question: AskKlimaQuestion, period: AskKlimaPeriod) {
        self.question = question
        self.period = period
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let answer = KpiAnswer.make(question.question, period: period.period, table: SiriKpiFile.load(), now: Date(),
                                    pending: SiriPendingTrips.dates())   // MARK: review-siri
        return .result(value: answer.shortcutValue, dialog: "\(answer.sentence)", view: AskKlimaSnippet(answer: answer))
    }
}

/// The Fahrten that wait to be saved (MARK: review-siri): „Lieblingsfahrt erfassen“ from a widget, Control Center or Siri queues its
/// Fahrt in the App Group and the app saves it when it opens (QuickLogQueue); „Pendelfahrt erfassen“ keeps a ride queued while its
/// stations cannot be found yet (CommuteLogQueue). Only their dates – an answer names how many fall in its period.
enum SiriPendingTrips {
    static func dates() -> [Date] {
        QuickLogQueue.pending().map(\.date) + CommuteLogQueue.pending().map(\.date)
    }
}
