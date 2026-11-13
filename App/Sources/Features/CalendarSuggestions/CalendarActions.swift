import SwiftUI
import KlimaCore

// MARK: calendarsuggestions – what the buttons of a card do (docs/CALENDAR_SUGGESTIONS.md §2): „Verbindung suchen“ opens the Fahrplan
// with the station and „an“ the arrival (the Fahrplan asks the ÖBB only with live consent – it shows its own consent state otherwise),
// „Kein Zug“ and „Später“ hide the card with „Rückgängig“ in the toast, „Fahrt erfassen“ opens the editor prefilled.

@MainActor
struct CalendarActions {
    let app: AppState
    private var store: CalendarSuggestionStore { .shared }

    /// The Fahrplan from where you usually start to the matched station, arriving by start − buffer (the planner's „Ankunft“ mode).
    /// Without a known start the Fahrplan keeps its own (the current location) and only the destination and the time are set.
    func searchConnection(_ suggestion: CalendarSuggestion) {
        let station = suggestion.match.station
        let planner = app.planner
        app.selectedTab = .planner
        if let origin = store.origin, origin.id != station.id {
            planner.handleDeepLink(PlannerLink(from: origin.id, to: station.id, at: suggestion.arrival, isArrival: true))
            return
        }
        planner.mode = .connections
        planner.path = []
        planner.destination = .station(station)
        planner.setWhen(suggestion.arrival, arrival: true)
        planner.startSearch()
    }

    func dismiss(_ suggestion: CalendarSuggestion) {
        withMotion(Motion.smooth) { store.dismiss(suggestion) }
        app.showToast("hand.raised.fill", "Kein Zug", "Dieser Termin bekommt keinen Vorschlag mehr", actionTitle: "Rückgängig", haptic: .tap) {
            withMotion(Motion.smooth) { CalendarSuggestionStore.shared.undoDismiss(suggestion) }
        }
    }

    func snooze(_ suggestion: CalendarSuggestion) {
        var until = Date()
        withMotion(Motion.smooth) { until = store.snooze(suggestion) }
        app.showToast("clock.arrow.circlepath", "Später", "Kommt \(CalendarText.when(until, now: store.now())) wieder", actionTitle: "Rückgängig",
                      haptic: .tap) {
            withMotion(Motion.smooth) { CalendarSuggestionStore.shared.undoSnooze(suggestion) }
        }
    }

    /// „Fahrt erfassen“ from „Warst du gefahren?“: the editor with the usual start, the station and the event's day.
    func logTrip(_ followUp: CalendarFollowUpPlanner.FollowUp) {
        var draft = TripDraft()
        if let origin = store.origin, origin.id != followUp.entry.stationID {
            draft.fromStationID = origin.id
            draft.fromName = origin.name
        }
        draft.toStationID = followUp.entry.stationID
        draft.toName = followUp.entry.stationName
        draft.date = followUp.entry.arrival
        app.presentAddTrip(draft)
    }

    func answerNo(_ followUp: CalendarFollowUpPlanner.FollowUp) {
        withMotion(Motion.smooth) { store.answerFollowUp(followUp.key) }
    }
}

/// Dates and places of the cards, against the store's clock (pinned in CI scenes).
enum CalendarText {
    /// "Heute", "Morgen", "Sa., 21. Nov."
    static func day(_ date: Date, now: Date) -> String {
        let cal = Calendar.vienna
        if cal.isDate(date, inSameDayAs: now) { return "Heute" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) { return "Morgen" }
        return Format.weekdayDayMonth(date)
    }

    /// "Sa., 21. Nov. · 19:30–22:00", "Morgen · 10:00–11:30"; an event over several days ends with its end day.
    static func eventLine(_ s: CalendarSuggestion, now: Date) -> String {
        let cal = Calendar.vienna
        let endText = cal.isDate(s.end, inSameDayAs: s.start) ? Format.time(s.end) : Format.weekdayDayMonth(s.end) + " " + Format.time(s.end)
        return day(s.start, now: now) + " · " + Format.time(s.start) + "–" + endText
    }

    /// "morgen 07:00", "Fr., 20. Nov. 07:00", "heute 21:00" – when a snoozed card comes back.
    static func when(_ date: Date, now: Date) -> String {
        let d = day(date, now: now)
        return (d == "Heute" || d == "Morgen" ? d.lowercased() : d) + " um " + Format.time(date)
    }

    /// Station names as the app shows them ("Salzburg Hbf", "St. Anton").
    static func station(_ name: String) -> String { TripRow.short(name) }

    /// "Ort erkannt: Linz Hbf" · "Ort: Salzburg (ungefähr)"
    static func placeLine(_ match: CalendarPlaceMatch) -> String {
        switch match.precision {
        case .station: "Ort erkannt: " + station(match.station.name)
        case .town: "Ort: " + match.placeText + " (ungefähr)"
        }
    }

    /// What VoiceOver reads for a card.
    static func spoken(_ s: CalendarSuggestion, now: Date) -> String {
        let place = s.match.precision == .station
            ? "Ort erkannt: \(station(s.match.station.name))"
            : "Ort ungefähr: \(s.match.placeText), Ziel \(station(s.match.station.name))"
        return "\(s.title). \(day(s.start, now: now)) um \(Format.time(s.start)). \(place). "
            + "Vorgeschlagene Ankunft \(Format.time(s.arrival)), \(s.bufferMinutes) Minuten vor Beginn."
    }
}
