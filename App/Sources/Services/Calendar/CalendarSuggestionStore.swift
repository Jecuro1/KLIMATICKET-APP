import Foundation
import Observation
import KlimaCore

// MARK: calendarsuggestions – the state behind „Kalender-Vorschläge“ (docs/CALENDAR_SUGGESTIONS.md §4–5): the switch, the permission,
// the ticked calendars, the buffer, the cards and the follow-ups. Persisted in UserDefaults as JSON (`CalendarSuggestionPrefs`): no
// event text, only hashes of dismissed / snoozed / suggested events, station ids and dates. Events are read from the source on every
// refresh – only while the app is open – and dropped again; nothing is logged, synced or sent anywhere.

@Observable
@MainActor
final class CalendarSuggestionStore {
    static let shared = CalendarSuggestionStore()

    private(set) var prefs: CalendarSuggestionPrefs
    private(set) var access: CalendarAccess
    private(set) var offered: [CalendarInfo] = []
    private(set) var suggestions: [CalendarSuggestion] = []
    private(set) var followUps: [CalendarFollowUpPlanner.FollowUp] = []
    /// Where trips usually start (home station, else the most frequent origin): the planner's start and the follow-up's „Von“.
    private(set) var origin: Station?
    /// Einstellungen: the explanation sheet before the system question.
    var showsExplanation = false
    /// Einstellungen: the calendar picker (opens by itself once access was granted).
    var showsPicker = false
    /// klimabilanz://calendar – Einstellungen › Kalender-Vorschläge as a sheet over the current tab.
    var showsSettingsSheet = false
    /// The system question is up (the switch waits for it).
    private(set) var isRequesting = false
    /// When the cards change by the clock alone (an arrival passes, a „Später“ runs out, midnight): the Übersicht plans again then,
    /// if it is still open. nil while nothing is planned.
    private(set) var nextChange: Date?

    @ObservationIgnored private var source: CalendarEventSource
    @ObservationIgnored private var catalog: CalendarStationCatalog?
    @ObservationIgnored private var catalogHasPlaces = false
    @ObservationIgnored private var lastTrips: [TripRecord] = []
    @ObservationIgnored private var lastStations: StationIndex?
    @ObservationIgnored private var lastHomeStationID: String?
    /// Demo and CI scenes: a fixed clock, the fake calendar, nothing persisted.
    @ObservationIgnored private(set) var isDemo: Bool
    @ObservationIgnored private var clock: () -> Date = Date.init

    private static let prefsKey = "calendarSuggestions.prefs.v1"

    init() {
        if LaunchMode.isSandboxed {
            source = FakeCalendarSource(access: .notDetermined)
            prefs = CalendarSuggestionPrefs()
            isDemo = true
        } else {
            source = EventKitSource()
            prefs = Self.loadPrefs()
            isDemo = false
        }
        access = source.currentAccess()
    }

    func now() -> Date { clock() }

    var setupState: CalendarSetupState {
        CalendarSetupState.make(isEnabled: prefs.isEnabled, access: access, offeredCalendars: offered.count,
                                selectedCalendars: selectedCalendars.count)
    }

    /// Ticked calendars that still exist.
    var selectedCalendars: [CalendarInfo] { offered.filter { prefs.calendarIDs.contains($0.id) } }

    /// The calendar database changed while the app is open (EventKit's notification; never for the fake source).
    static var changeNotification: Notification.Name { EventKitSource.changeNotification }

    // MARK: Settings

    /// The switch in Einstellungen. On: the explanation sheet first (the system question only follows its „Verstanden“). Off: the cards
    /// go at once; the ticked calendars and „Kein Zug“ stay remembered.
    func setEnabled(_ on: Bool) {
        if on {
            guard !prefs.isEnabled else { return }
            showsExplanation = true
        } else {
            update { $0.isEnabled = false }
            suggestions = []
            followUps = []
        }
    }

    /// „Verstanden, weiter“ in the explanation sheet: switches on, asks iOS once (if it has not been asked), preselects the default
    /// calendar and opens the picker.
    func confirmExplanation() async {
        showsExplanation = false
        update { $0.isEnabled = true }
        isRequesting = true
        // The sheet's dismissal first, so neither the system alert nor the picker sheet fights it.
        if !isDemo { try? await Task.sleep(for: .milliseconds(450)) }
        if access == .notDetermined {
            access = await source.requestFullAccess()
        } else {
            access = source.currentAccess()
        }
        isRequesting = false
        reloadCalendars()
        if access == .fullAccess, !offered.isEmpty { showsPicker = true }
        recompute()
    }

    func cancelExplanation() { showsExplanation = false }

    func toggleCalendar(_ id: String) {
        update { p in
            if let i = p.calendarIDs.firstIndex(of: id) { p.calendarIDs.remove(at: i) } else { p.calendarIDs.append(id) }
            p.hasPickedCalendars = true
        }
        recompute()
    }

    func setBuffer(_ minutes: Int) {
        update { $0.bufferMinutes = CalendarBuffer.clamp(minutes) }
        recompute()
    }

    /// iOS may have changed the permission (Einstellungen › Apps › KlimaBilanz › Kalender): re-read it on every return to the app.
    /// Revoked → the cards disappear, Einstellungen says „verweigert“.
    func refreshAccess() {
        access = source.currentAccess()
        // With the switch off the calendar database stays closed (not even the list of calendars is read).
        if prefs.isEnabled { reloadCalendars() } else if !offered.isEmpty { offered = [] }
        if access != .fullAccess {
            suggestions = []
            followUps = []
        }
    }

    /// klimabilanz://calendar: the settings page as a sheet. The app-level sheets (Einstellungen, Gipfelbuch, an optional update,
    /// Was-wäre-wenn – a second sheet cannot stack on them) close first. Not over the onboarding (the explanation and the system
    /// question never come before it is done), an open trip editor, the Jahresrückblick or a required update (the same rules as
    /// klimabilanz://timebalance).
    func openSettingsFromLink(closing app: AppState, afterSheet: Bool = false) {
        guard !showsSettingsSheet, app.tripDraft == nil, app.yearReviewRequest == nil,
              app.settings.onboardingCompleted || LaunchMode.isSandboxed else { return }
        if app.updates.isPresentingSheet && app.updates.isRequired { return }
        guard afterSheet || app.isShowingSettings || app.isShowingAchievements || app.updates.isPresentingSheet else {
            showsSettingsSheet = true
            return
        }
        app.isShowingSettings = false
        app.isShowingAchievements = false
        app.updates.isPresentingSheet = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))   // the sheet's dismissal animation (as for klimabilanz://timebalance)
            if app.tripDraft == nil, app.yearReviewRequest == nil { showsSettingsSheet = true }
        }
    }

    // MARK: Cards

    /// Reads the next 14 days of the ticked calendars and plans the cards. Called by the Übersicht on appear, on return to the
    /// foreground, when trips change and when the calendar database changes.
    func refresh(trips: [TripRecord], stations: StationIndex, homeStationID: String?) {
        lastTrips = trips
        lastStations = stations
        lastHomeStationID = homeStationID
        refreshAccess()
        recompute()
    }

    /// „Kein Zug“: this event never gets a card again (remembered as a hash for 60 days after it).
    func dismiss(_ suggestion: CalendarSuggestion) {
        update { $0.dismiss(key: suggestion.key, eventStart: suggestion.start) }
        recompute()
    }

    func undoDismiss(_ suggestion: CalendarSuggestion) {
        update { $0.undoDismiss(key: suggestion.key) }
        recompute()
    }

    /// „Später“: the card comes back tomorrow morning, or three hours before the arrival.
    func snooze(_ suggestion: CalendarSuggestion) -> Date {
        let until = CalendarSnooze.until(now: now(), arrival: suggestion.arrival)
        update { $0.snooze(key: suggestion.key, until: until) }
        recompute()
        return until
    }

    func undoSnooze(_ suggestion: CalendarSuggestion) {
        update { $0.snoozed[suggestion.key] = nil }
        recompute()
    }

    /// „Nein“ on „Warst du gefahren?“.
    func answerFollowUp(_ key: String) {
        update { $0.followUps[key] = nil }
        followUps.removeAll { $0.key == key }
    }

    // MARK: Planning

    private func recompute() {
        guard setupState.showsSuggestions, let stations = lastStations else {
            suggestions = []
            followUps = []
            nextChange = nil
            return
        }
        let now = now()
        let catalog = currentCatalog(stations)
        let resolved = resolveOrigin(stations: stations)
        if resolved != origin { origin = resolved }
        let horizon = now.addingTimeInterval(Double(CalendarSuggestionPlanner.windowDays) * 86_400 + 3600)
        // From a few days back: a follow-up may only ask about an event that is still in the calendar (the planner itself takes
        // only what starts after now).
        let events = source.events(from: CalendarFollowUpPlanner.readStart(now: now), to: horizon, calendarIDs: Set(prefs.calendarIDs))
        let planned = CalendarSuggestionPlanner.plan(events: events, matcher: CalendarTripMatcher(catalog: catalog), prefs: prefs,
                                                     trips: lastTrips, origin: origin, now: now)
        // The follow-up may ask about every card shown (station, arrival and start only) – while its event stays in the calendar.
        var next = prefs
        for s in planned where next.followUps[s.key] == nil {
            next.followUps[s.key] = CalendarFollowUpEntry(stationID: s.match.station.id, stationName: s.match.station.name, arrival: s.arrival,
                                                          eventStart: s.start)
        }
        next.keepFollowUps(eventKeys: Set(events.map(\.key)))
        next.prune(now: now)
        if next != prefs {
            prefs = next
            save()
        }
        if planned != suggestions { suggestions = planned }
        let pending = CalendarFollowUpPlanner.pending(prefs: prefs, trips: lastTrips, now: now)
        if pending != followUps { followUps = pending }
        let change = CalendarSuggestionPlanner.nextChange(suggestions: planned, prefs: prefs, now: now)
        if change != nextChange { nextChange = change }
    }

    private func currentCatalog(_ stations: StationIndex) -> CalendarStationCatalog {
        let hasPlaces = stations.places != nil
        if let catalog, catalogHasPlaces == hasPlaces { return catalog }
        let built = CalendarStationCatalog.make(stations: stations.stations, places: stations.places)
        catalog = built
        catalogHasPlaces = hasPlaces
        return built
    }

    private func resolveOrigin(stations: StationIndex) -> Station? {
        if isDemo, let demo = stations.station(id: CalendarDemoEvents.originStationID) { return demo }
        if let id = lastHomeStationID, let home = stations.station(id: id) { return home }
        guard let frequent = CalendarOrigin.mostFrequent(trips: lastTrips) else { return nil }
        return stations.station(id: frequent.stationID)
    }

    private func reloadCalendars() {
        let list = access == .fullAccess ? source.calendars() : []
        if list != offered { offered = list }
        // Nothing ticked before the user picks, except the calendar new events go to.
        if access == .fullAccess, !prefs.hasPickedCalendars, prefs.calendarIDs.isEmpty, let main = list.first(where: \.isDefault) {
            update { $0.calendarIDs = [main.id] }
        }
    }

    // MARK: Persistence

    private func update(_ change: (inout CalendarSuggestionPrefs) -> Void) {
        var next = prefs
        change(&next)
        guard next != prefs else { return }
        prefs = next
        save()
    }

    private func save() {
        guard !isDemo, let data = try? JSONEncoder().encode(prefs) else { return }
        UserDefaults.standard.set(data, forKey: Self.prefsKey)
    }

    private static func loadPrefs() -> CalendarSuggestionPrefs {
        guard let data = UserDefaults.standard.data(forKey: prefsKey),
              let prefs = try? JSONDecoder().decode(CalendarSuggestionPrefs.self, from: data) else { return CalendarSuggestionPrefs() }
        return prefs
    }

    /// „Alle Daten löschen“ (Repository): every trace of an event goes – „Kein Zug“, „Später“ and the follow-ups with their stations
    /// and times. The switch, the ticked calendars and the buffer are settings and stay, like the app's other settings.
    func forgetEvents() {
        guard !isDemo else { return }
        update { $0.forgetEvents() }
        followUps = []
        recompute()
    }

    // MARK: Demo

    /// A CI scene: the fake calendar in the given permission state, a fixed clock, the switch and the calendars as given.
    func installDemo(access demoAccess: CalendarAccess, enabled: Bool, calendarIDs: [String], bufferMinutes: Int = CalendarBuffer.defaultMinutes,
                     calendars: [CalendarInfo] = CalendarDemoEvents.calendars, events: [CalendarEventInput] = CalendarDemoEvents.events(),
                     followUps: [String: CalendarFollowUpEntry] = [:], now pinned: Date = CalendarDemoEvents.now) {
        isDemo = true
        source = FakeCalendarSource(access: demoAccess, calendars: calendars, events: events)
        var p = CalendarSuggestionPrefs()
        p.isEnabled = enabled
        p.calendarIDs = calendarIDs
        p.hasPickedCalendars = true
        p.bufferMinutes = bufferMinutes
        p.followUps = followUps
        prefs = p
        clock = { pinned }
        access = demoAccess
        offered = demoAccess == .fullAccess ? calendars : []
        suggestions = []
        self.followUps = []
    }
}
