import SwiftUI
import SwiftData
import KlimaCore

// MARK: commute – Einstellungen › Pendeln (docs/COMMUTE.md §8): the switch, the Stammstrecke (a suggestion from the trips, a route
// of „Meine Routen“ or two stations), weekdays and the two departure times, „Hin und retour erfassen“, the live-data status and
// the Siri phrases. Everything is stored as versioned JSON in UserDefaults (`CommuteSettingsStore`); nothing is synced.

struct CommuteSettingsPage: View {
    /// Opened from the Übersicht card (own sheet with a „Fertig“ button).
    var isSheet = false
    /// CI scenes: the detector's candidates instead of the ones computed from the store.
    var previewCandidates: [CommuteGuess]? = nil
    /// CI scene `commuteSettingsBottom`: scrolls to „Wann du fährst“ after the first frame.
    var screenshotScrollsDown = false

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query private var recentTrips: [TripEntity]
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var routes: [FavoriteRouteEntity]

    @State private var candidates: [CommuteGuess] = []
    @State private var showsConsent = false
    @State private var confirmsRemoval = false
    @State private var changeTick = 0
    private var model: CommuteModel { .shared }
    private var settings: CommuteSettings { model.settings }

    init(isSheet: Bool = false, previewCandidates: [CommuteGuess]? = nil, screenshotScrollsDown: Bool = false) {
        self.isSheet = isSheet
        self.previewCandidates = previewCandidates
        self.screenshotScrollsDown = screenshotScrollsDown
        // Only the detector's window is read (56 days and one day of slack), not the whole history.
        let start = Date().addingTimeInterval(-Double(CommuteDetector.windowDays + 1) * 86_400)
        _recentTrips = Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil && $0.date >= start },
                             sort: \TripEntity.date, order: .reverse)
    }

    var body: some View {
        ScrollViewReader { proxy in
            list
                .task {
                    guard screenshotScrollsDown else { return }
                    try? await Task.sleep(for: .milliseconds(700))
                    proxy.scrollTo("times", anchor: .top)
                }
        }
    }

    private var list: some View {
        List {
            switchSection
            if settings.isEnabled {
                routeSection
                timeSection.id("times")
                logSection
                liveSection
                siriSection
                if settings.hasRoute { removeSection }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop() }
        .tint(Theme.accent)
        .navigationTitle("Pendeln")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .motionAnimation(Motion.smooth, value: settings.isEnabled)
        .motionAnimation(Motion.smooth, value: settings.source)
        .haptic(.selection, trigger: changeTick)
        .sheet(isPresented: $showsConsent) { CommuteConsentSheet() }
        .confirmationDialog("Stammstrecke entfernen?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) { removeRoute() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Pendel-Modus wird ausgeschaltet und vergisst Strecke, Wochentage und Zeiten. Deine Fahrten bleiben. Die Übersicht fragt 30 Tage nicht nach dieser Strecke.")
        }
        .task(id: recentTrips.count) { detect() }
    }

    // MARK: Switch

    private var switchSection: some View {
        Section {
            Toggle(isOn: Binding(get: { settings.isEnabled }, set: { setEnabled($0) })) {
                SetRowLabel(title: "Pendel-Modus", subtitle: "Die Übersicht zeigt vor der Abfahrt die nächsten Züge deiner Stammstrecke",
                            symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: Theme.glacier)
                    .setSymbolOnEnable(settings.isEnabled)
            }
            .listRowBackground(Theme.surface)
        } footer: {
            SetFooter(text: "Ab 45 Minuten vor deiner Abfahrt bis 30 Minuten danach: Verspätung, Gleis und bei Ausfall die nächste Verbindung. Verspätungen siehst du nur, solange KlimaBilanz offen ist – es gibt keine Push-Mitteilungen.")
        }
    }

    // MARK: Route

    private var routeSection: some View {
        Section {
            Group {
                Picker("Quelle", selection: Binding(get: { settings.source }, set: { source in
                    changeTick += 1
                    model.store.update { $0.source = source }
                })) {
                    ForEach(CommuteSettings.RouteSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Woher die Stammstrecke kommt")

                switch settings.source {
                case .suggestion: suggestionRows
                case .savedRoute: savedRouteRows
                case .stations: stationRows
                }

                if let origin = settings.origin, let destination = settings.destination {
                    HStack(spacing: Theme.Spacing.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hinfahrt").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            CommuteRouteTitle(from: origin.name, to: destination.name, font: .system(.headline, design: .rounded, weight: .bold))
                        }
                        Spacer(minLength: Theme.Spacing.xs)
                        Button {
                            changeTick += 1
                            withMotion(Motion.bouncy) { swapEnds() }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Richtung tauschen")
                        .accessibilityHint("Die Hinfahrt beginnt dann in \(TripRow.short(destination.name))")
                    }
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Stammstrecke")
        } footer: {
            SetFooter(text: routeFooter)
        }
    }

    @ViewBuilder
    private var suggestionRows: some View {
        let usable = candidates.filter { $0.origin.stationID != nil && $0.destination.stationID != nil }.prefix(3)
        if usable.isEmpty {
            CommuteNotice(symbol: "sparkle.magnifyingglass",
                          text: "Noch kein Vorschlag. Ab \(CommuteDetector.minRides) Fahrten auf derselben Strecke in \(CommuteDetector.minWeeks) verschiedenen Wochen und an \(CommuteDetector.minWeekdays) Wochentagen schlägt KlimaBilanz sie hier vor.")
        } else {
            ForEach(Array(usable), id: \.pairKey) { guess in
                Button { apply(guess) } label: {
                    choiceRow(title: "\(TripRow.short(guess.origin.name)) ⇄ \(TripRow.short(guess.destination.name))",
                              subtitle: "\(guess.trips) Fahrten in \(guess.weeks) Wochen · \(CommutePlan(weekdays: guess.weekdays).dayText)",
                              symbol: "sparkles", isSelected: isCurrent(guess.origin, guess.destination))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var savedRouteRows: some View {
        let usable = routes.filter { $0.fromStationID != nil && $0.toStationID != nil && !$0.isCombo }
        if usable.isEmpty {
            CommuteNotice(symbol: "bookmark",
                          text: "Unter „Meine Routen“ ist noch keine Strecke mit zwei Stationen. Lege dort eine an oder wähle zwei Stationen.")
        } else {
            ForEach(usable) { route in
                Button { apply(route) } label: {
                    choiceRow(title: route.displayTitle,
                              subtitle: route.schedule.map { "\($0.summary) · Zeiten werden übernommen" } ?? "Ohne Zeitplan",
                              symbol: route.mode.symbolName, isSelected: settings.savedRouteID == route.id)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var stationRows: some View {
        NavigationLink {
            StationPickerView(title: "Von (Start der Hinfahrt)") { station in pick(station, isOrigin: true) }
        } label: {
            stationRow(label: "Von", name: settings.origin?.name, symbol: "house.fill", tint: Theme.pine)
        }
        NavigationLink {
            StationPickerView(title: "Nach") { station in pick(station, isOrigin: false) }
        } label: {
            stationRow(label: "Nach", name: settings.destination?.name, symbol: "briefcase.fill", tint: Theme.dusk)
        }
    }

    private func choiceRow(title: String, subtitle: String, symbol: String, isSelected: Bool) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            SetRowLabel(title: title, subtitle: subtitle, symbol: symbol, tint: isSelected ? Theme.glacier : Theme.textTertiary)
            Spacer(minLength: Theme.Spacing.xs)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                .symbolReplaceTransition()
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func stationRow(label: String, name: String?, symbol: String, tint: Color) -> some View {
        HStack {
            SetRowLabel(title: label, symbol: symbol, tint: tint)
            Spacer(minLength: Theme.Spacing.xs)
            Text(name.map(TripRow.short) ?? "wählen")
                .font(.subheadline)
                .foregroundStyle(name == nil ? Theme.accentText : Theme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var routeFooter: String {
        switch settings.source {
        case .suggestion: "Der Vorschlag kommt aus deinen Fahrten der letzten 8 Wochen, beide Richtungen zusammen. Gerechnet wird nur auf deinem iPhone."
        case .savedRoute: "Wochentage und Abfahrtszeit kommen aus dem Zeitplan der Route; die Rückfahrt stellst du unten ein."
        case .stations: "„Von“ ist der Start der Hinfahrt, meist dein Zuhause."
        }
    }

    // MARK: Times

    private var timeSection: some View {
        Section {
            Group {
                CommuteWeekdayPicker(weekdays: settings.plan.weekdays) { day in
                    changeTick += 1
                    updatePlan { plan in
                        if plan.weekdays.contains(day) { plan.weekdays.remove(day) } else { plan.weekdays.insert(day) }
                    }
                }
                timeRow(title: "Hinfahrt", subtitle: settings.origin.map { "ab \(TripRow.short($0.name))" },
                        symbol: "sunrise.fill", tint: Theme.dawn, minute: settings.plan.outboundMinute) { minute in
                    updatePlan { $0.outboundMinute = minute }
                }
                timeRow(title: "Rückfahrt", subtitle: settings.destination.map { "ab \(TripRow.short($0.name))" },
                        symbol: "sunset.fill", tint: Theme.dusk, minute: settings.plan.returnMinute) { minute in
                    updatePlan { $0.returnMinute = minute }
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Wann du fährst")
        } footer: {
            SetFooter(text: "Die Karte zeigt die Fahrt, die als Nächste ansteht, und ab 45 Minuten davor die Züge. Auf der Karte kannst du die Richtung tauschen.")
        }
    }

    private func timeRow(title: String, subtitle: String?, symbol: String, tint: Color, minute: Int,
                         set: @escaping (Int) -> Void) -> some View {
        DatePicker(selection: Binding(get: { Self.date(for: minute) }, set: { set(Self.minute(of: $0)) }),
                   displayedComponents: .hourAndMinute) {
            SetRowLabel(title: title, subtitle: subtitle, symbol: symbol, tint: tint)
        }
        .environment(\.timeZone, Calendar.vienna.timeZone)
        .environment(\.locale, Format.locale)   // „07:20“, never „7:20 AM“
    }

    static func date(for minute: Int) -> Date {
        let cal = Calendar.vienna
        return cal.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: cal.startOfDay(for: Date())) ?? Date()
    }

    static func minute(of date: Date) -> Int {
        CommuteWindow.minuteOfDay(date, calendar: .vienna)
    }

    // MARK: Logging

    private var logSection: some View {
        Section {
            Toggle(isOn: Binding(get: { settings.logsRoundTrip }, set: { on in model.store.update { $0.logsRoundTrip = on } })) {
                SetRowLabel(title: "Hin und retour erfassen",
                            subtitle: "„Fahrt erfassen“ auf der Karte und Siri tragen beide Richtungen als eine Fahrt ein",
                            symbol: "arrow.left.arrow.right", tint: Theme.pine)
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Erfassen")
        } footer: {
            SetFooter(text: "Ohne „Hin und retour“ gilt die Richtung der Tageszeit: vor 13 Uhr die Hinfahrt, danach die Rückfahrt. Im Formular kannst du vor dem Sichern alles ändern.")
        }
    }

    // MARK: Live data

    private var liveSection: some View {
        Section {
            Group {
                HStack(alignment: .firstTextBaseline) {
                    Text("Live-Daten").font(.subheadline).foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: Theme.Spacing.xs)
                    Text(liveStatus.text)
                        .font(.footnote)
                        .foregroundStyle(liveStatus.ok ? Theme.positiveText : Theme.summitText)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
                if app.live.consent == .undecided, !app.live.isDemo {
                    Button { showsConsent = true } label: {
                        SetRowLabel(title: "Live-Daten einschalten …", subtitle: "Erklärt, was abgefragt wird, und fragt nach deiner Zustimmung",
                                    symbol: "dot.radiowaves.left.and.right", tint: Theme.glacier)
                    }
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Verspätungen")
        } footer: {
            SetFooter(text: "Abgefragt wird nur, während die Karte in der Übersicht zu sehen ist, höchstens einmal pro Minute und über dieselbe Drossel wie der Fahrplan. Nichts läuft im Hintergrund, und dein Standort wird nicht verwendet. Ohne Live-Daten zeigt die Karte deinen Plan.")
        }
    }

    private var liveStatus: (text: String, ok: Bool) {
        if app.live.isDemo { return ("Demo-Daten", true) }
        switch app.live.timetableUnavailable {
        case nil: return ("an", true)
        case .consentUndecided: return ("noch nicht entschieden", false)
        case .declined: return ("aus (nur Offline-Daten)", false)
        case .switchedOff: return (FeatureCenter.shared.offlineMode ? "Offline-Modus ist an" : "Fahrplan live ist aus", false)
        case .killSwitch: return ("gerade pausiert", false)
        case .offline: return ("offline", false)
        }
    }

    // MARK: Siri

    private var siriSection: some View {
        Section {
            Group {
                SetRowLabel(title: "„Wann fährt mein nächster Zug in KlimaBilanz?“",
                            subtitle: "Siri sagt Zeit, Verspätung und Gleis – aus der letzten Abfrage der Karte, höchstens 15 Minuten alt, sonst deinen Plan",
                            symbol: "waveform", tint: Theme.alpenglow)
                SetRowLabel(title: "„Pendelfahrt in KlimaBilanz erfassen“",
                            subtitle: "Trägt deine Stammstrecke für jetzt ein, so wie „Fahrt erfassen“ auf der Karte",
                            symbol: "plus.bubble.fill", tint: Theme.pine)
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Siri und Kurzbefehle")
        }
    }

    // MARK: Remove

    private var removeSection: some View {
        Section {
            Button(role: .destructive) { confirmsRemoval = true } label: {
                SetRowLabel(title: "Stammstrecke entfernen", symbol: "trash.fill", tint: Theme.negative)
                    .foregroundStyle(Theme.negativeText)
            }
            .listRowBackground(Theme.surface)
        }
    }

    // MARK: Actions

    private func detect() {
        if let previewCandidates { candidates = previewCandidates; return }
        let records = recentTrips.map(\.record)
        candidates = CommuteDetector.candidates(trips: records, now: Date(), calendar: .vienna, homeStationID: app.settings.homeStationID)
    }

    private func setEnabled(_ on: Bool) {
        changeTick += 1
        model.store.update { s in
            s.isEnabled = on
            // Switched on without a route: the best suggestion of the trips is the obvious start (it can be changed below).
            if on, !s.hasRoute, let best = candidates.first(where: { $0.origin.stationID != nil && $0.destination.stationID != nil }) {
                s.source = .suggestion
                s.origin = best.origin
                s.destination = best.destination
                s.plan = CommuteSetup.plan(guess: best, route: CommuteSetup.savedRoute(for: best, in: routes))
                s.logsRoundTrip = best.mostlyRoundTrips
            }
        }
        model.settingsChanged()
    }

    private func isCurrent(_ a: CommuteEndpoint, _ b: CommuteEndpoint) -> Bool {
        guard let origin = settings.origin, let destination = settings.destination else { return false }
        return CommuteDetector.pairKey(origin, destination) == CommuteDetector.pairKey(a, b)
    }

    private func apply(_ guess: CommuteGuess) {
        changeTick += 1
        let match = CommuteSetup.savedRoute(for: guess, in: routes)
        model.store.update { s in
            s.source = .suggestion
            s.origin = guess.origin
            s.destination = guess.destination
            s.savedRouteID = nil
            s.plan = CommuteSetup.plan(guess: guess, route: match)
            s.mode = match?.mode ?? .train
            s.logsRoundTrip = guess.mostlyRoundTrips
        }
        model.settingsChanged()
    }

    private func apply(_ route: FavoriteRouteEntity) {
        changeTick += 1
        model.store.update { s in
            s.source = .savedRoute
            s.savedRouteID = route.id
            s.origin = CommuteEndpoint(stationID: route.fromStationID, name: route.fromName)
            s.destination = CommuteEndpoint(stationID: route.toStationID, name: route.toName)
            s.mode = route.mode
            s.logsRoundTrip = route.isRoundTrip
            if let schedule = route.schedule, !schedule.weekdays.isEmpty {
                s.plan = CommutePlan(schedule: schedule, returnMinute: s.plan.returnMinute)
            }
        }
        model.settingsChanged()
    }

    private func pick(_ station: Station, isOrigin: Bool) {
        let end = CommuteEndpoint(stationID: station.id, name: station.name)
        model.store.update { s in
            s.source = .stations
            s.savedRouteID = nil
            if isOrigin { s.origin = end } else { s.destination = end }
        }
        model.settingsChanged()
    }

    private func swapEnds() {
        model.store.update { s in
            let origin = s.origin
            s.origin = s.destination
            s.destination = origin
            // The times stay with their direction: the morning ride is still the „Hinfahrt“, it now starts at the other end.
        }
        model.settingsChanged()
    }

    private func updatePlan(_ change: (inout CommutePlan) -> Void) {
        model.store.update { s in
            var plan = s.plan
            change(&plan)
            s.plan = CommutePlan(weekdays: plan.weekdays, outboundMinute: plan.outboundMinute, returnMinute: plan.returnMinute)
        }
        model.settingsChanged()
    }

    private func removeRoute() {
        let declined = settings.declinedPairs
        let removed = settings.origin.flatMap { origin in settings.destination.map { CommuteDetector.pairKey(origin, $0) } }
        model.store.reset()
        // A „Nein“ on the invitation stays remembered – and the removed route counts as one: the Übersicht does not ask
        // „Ist das dein Arbeitsweg?“ about it right after it was removed (30 days, like „Nein“).
        model.store.update { $0.declinedPairs = declined }
        if let removed { model.store.decline(pairKey: removed) }
        model.settingsChanged()
        app.showToast("trash.fill", "Stammstrecke entfernt", "Der Pendel-Modus ist aus", haptic: .warning)
    }
}

// MARK: - Weekdays

/// Mo … So as seven round toggles (the state is in the fill and the check trait, not in colour alone).
struct CommuteWeekdayPicker: View {
    var weekdays: Set<RouteWeekday>
    var toggle: (RouteWeekday) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Wochentage").font(.subheadline).foregroundStyle(Theme.textPrimary)
            let columns = typeSize.isAccessibilitySize ? 4 : 7
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                ForEach(RouteWeekday.allCases, id: \.self) { day in
                    let on = weekdays.contains(day)
                    Button { toggle(day) } label: {
                        Text(day.shortName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(on ? Theme.onAccent : Theme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(on ? AnyShapeStyle(Theme.prominentTint) : AnyShapeStyle(Theme.surfaceSecondary), in: .capsule)
                            .overlay { if on { Capsule().strokeBorder(Theme.onAccent.opacity(0.25), lineWidth: 1) } }
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(Self.longName(day))
                    .accessibilityValue(on ? "ausgewählt" : "nicht ausgewählt")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .motionAnimation(Motion.snappy, value: weekdays)
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }

    static func longName(_ day: RouteWeekday) -> String {
        ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"][day.rawValue]
    }
}

// MARK: - Settings entry

/// The row in Einstellungen: „Pendeln“ with the route or „Aus“.
struct SetCommuteSection: View {
    private var model: CommuteModel { .shared }

    var body: some View {
        Section {
            NavigationLink {
                CommuteSettingsPage()
            } label: {
                SetRowLabel(title: "Pendeln", subtitle: subtitle, symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: Theme.glacier)
                    .setSymbolOnEnable(model.settings.isActive)
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Pendeln")
        }
    }

    private var subtitle: String {
        let s = model.settings
        guard s.isEnabled else { return "Aus · zeigt die nächsten Züge deiner Stammstrecke" }
        guard s.hasRoute, let origin = s.origin, let destination = s.destination else { return "An · Stammstrecke fehlt" }
        return "\(TripRow.short(origin.name)) ⇄ \(TripRow.short(destination.name)) · \(s.plan.dayText)"
    }
}
