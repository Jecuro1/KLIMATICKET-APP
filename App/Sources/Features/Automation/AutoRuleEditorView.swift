import SwiftUI
import SwiftData
import KlimaCore

// MARK: automation – the rule editor (docs/AUTOMATION.md §5): the rule as one sentence „Wenn [Auslöser] und [Bedingung], dann
// [Aktion]“ whose parts are menus, the Testlauf right under it (the engine's own verdict, updated while you edit), then the
// values of the trigger, the conditions, what happens, the name. Nothing is saved before „Sichern“.

struct AutoRuleEditorView: View {
    let isNew: Bool
    /// CI scene `automationTest`: the Testlauf runs once the editor appears.
    var runsTestOnAppear = false
    /// CI scene `automationEditorBottom`: the section the editor scrolls to after the first frame.
    var screenshotScrollTarget: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var routes: [FavoriteRouteEntity]
    @State private var draft: AutoRule
    @State private var probe: AutoProbe?
    @State private var confirmsDelete = false
    @State private var savedTick = 0
    @State private var testTick = 0
    private let original: AutoRule

    private var store: AutoStore { .shared }
    private var runner: AutoRunner { .shared }
    private var kind: AutoTriggerKind { draft.trigger.kind }

    init(rule: AutoRule, isNew: Bool, runsTestOnAppear: Bool = false, screenshotScrollTarget: String? = nil) {
        self.isNew = isNew
        self.runsTestOnAppear = runsTestOnAppear
        self.screenshotScrollTarget = screenshotScrollTarget
        original = rule
        _draft = State(initialValue: rule)
    }

    var body: some View {
        ScrollViewReader { proxy in
            list
                .task {
                    guard let target = screenshotScrollTarget else { return }
                    try? await Task.sleep(for: .milliseconds(700))
                    proxy.scrollTo(target, anchor: .top)
                }
        }
    }

    private var list: some View {
        List {
            sentenceSection
            triggerSection
            if !kind.allowedConditions.isEmpty { conditionSection.id("conditions") }
            actionSection.id("action")
            nameSection
            if !isNew { deleteSection }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop(skyOpacity: 0.4) }
        .tint(Theme.accent)
        .navigationTitle(isNew ? "Neue Regel" : "Regel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save).fontWeight(.semibold)
            }
        }
        .interactiveDismissDisabled(draft != original)
        .haptic(.success, trigger: savedTick)
        .haptic(.tap, trigger: testTick)
        .onChange(of: draft) { _, _ in
            // The Testlauf follows every change while it is shown: the explanation is always the verdict of what you see.
            if probe != nil { probe = runner.probe(draft.normalized) }
        }
        .confirmationDialog("Regel löschen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive, action: delete)
        } message: {
            Text("„\(draft.name)“ und ihre geplanten Mitteilungen werden entfernt.")
        }
        .task {
            guard runsTestOnAppear, probe == nil else { return }
            runTest()
        }
    }

    // MARK: Sentence and Testlauf

    private var sentenceSection: some View {
        Section {
            GlassCard(padding: Theme.Spacing.m, tint: kind.autoTint) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.xs) {
                        AutoKindTile(kind: kind, isOn: draft.isEnabled, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Kicker(text: "Deine Regel")
                            Text(AutoText.kindTiming(kind).autoSentenceStart)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    sentence
                    testButton
                    if let probe {
                        AutoTestCard(probe: probe, rule: draft.normalized)
                            .motionTransition(.rise)
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var sentence: some View {
        AutoFlowLayout(spacing: 6, lineSpacing: 8) {
            AutoSentenceWord(text: "Wenn")
            triggerMenu
            if !kind.allowedConditions.isEmpty {
                AutoSentenceWord(text: "und", isMuted: draft.conditions.isEmpty)
                conditionMenu
            }
            AutoSentenceWord(text: "dann")
            actionMenu
        }
        .motionAnimation(Motion.smooth, value: draft)
    }

    private var triggerMenu: some View {
        Menu {
            Picker("Auslöser", selection: Binding(get: { kind }, set: setKind)) {
                ForEach(AutoTriggerKind.allCases) { option in
                    Label(AutoText.kindTitle(option), systemImage: option.autoSymbol).tag(option)
                }
            }
        } label: {
            AutoToken(text: AutoText.triggerPhrase(draft.trigger), tint: kind.autoTint, symbol: kind.autoSymbol)
        }
        .accessibilityLabel("Auslöser: \(AutoText.triggerPhrase(draft.trigger))")
        .accessibilityHint("Wählt, was die Regel startet")
    }

    private var conditionMenu: some View {
        let phrases = draft.normalized.conditions.map(AutoText.conditionPhrase)
        return Menu {
            ForEach(kind.allowedConditions) { option in
                Toggle(isOn: conditionBinding(option)) {
                    Label(option.autoTitle, systemImage: option.autoSymbol)
                }
            }
        } label: {
            AutoToken(text: phrases.isEmpty ? "Bedingung" : phrases.joined(separator: " und "), tint: Theme.glacier,
                      symbol: phrases.isEmpty ? "plus" : "line.3.horizontal.decrease", isPlaceholder: phrases.isEmpty)
        }
        .accessibilityLabel(phrases.isEmpty ? "Keine Bedingung" : "Bedingung: \(phrases.joined(separator: " und "))")
        .accessibilityHint("Fügt eine Bedingung hinzu oder nimmt sie weg")
    }

    private var actionMenu: some View {
        Menu {
            Picker("Aktion", selection: Binding(get: { draft.addTrip != nil }, set: setOpensAddTrip)) {
                Label("sag es mir", systemImage: "bell.badge").tag(false)
                Label("erinnere mich und öffne „Fahrt erfassen“", systemImage: "plus.circle").tag(true)
            }
        } label: {
            AutoToken(text: AutoText.actionPhrase(draft), tint: Theme.pine, symbol: "bell.badge.fill")
        }
        .accessibilityLabel("Aktion: \(AutoText.actionPhrase(draft))")
    }

    private var testButton: some View {
        Button(action: runTest) {
            Label(probe == nil ? "Testlauf" : "Nochmal prüfen", systemImage: probe == nil ? "play.fill" : "arrow.clockwise")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.onAccent)   // the symbol would take the tint – the button's own fill – and vanish
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.prominentTint)
        .controlSize(.large)
        .accessibilityHint("Zeigt, ob die Regel jetzt auslösen würde und warum")
    }

    private func runTest() {
        testTick += 1
        withMotion(Motion.smooth) { probe = runner.probe(draft.normalized) }
    }

    // MARK: Trigger

    private var triggerSection: some View {
        Section {
            switch draft.trigger {
            case let .ticketDeadline(days):
                AutoChoiceChips(choices: AutoTrigger.deadlineChoices, isSelected: { $0 == days },
                                title: { $0 == 1 ? "1 Tag" : "\($0) Tage" }) { draft.trigger = .ticketDeadline(daysBefore: $0) }
                    .accessibilityLabel("Tage vor Ablauf")
            case let .milestone(percents):
                AutoChoiceChips(choices: AutoTrigger.milestoneChoices, isSelected: { percents.contains($0) }, title: { "\($0) %" },
                                accessibilityTitle: { "\($0) Prozent" }) { value in
                    var set = percents
                    if set.contains(value) { if set.count > 1 { set.remove(value) } } else { set.insert(value) }
                    draft.trigger = .milestone(percents: set)
                }
            case let .dayWithoutTrip(weekdays, minute):
                AutoWeekdayPicker(selection: Binding(get: { weekdays }, set: { draft.trigger = .dayWithoutTrip(weekdays: $0, minuteOfDay: minute) }))
                    .accessibilityLabel("Wochentage")
                AutoTimeRow(title: "Uhrzeit", minute: Binding(get: { minute }, set: { draft.trigger = .dayWithoutTrip(weekdays: weekdays, minuteOfDay: $0) }))
            case let .followDelay(minutes):
                AutoChoiceChips(choices: AutoTrigger.delayChoices, isSelected: { $0 == minutes }, title: { "ab \($0) Min" },
                                accessibilityTitle: { "ab \($0) Minuten" }) { draft.trigger = .followDelay(minutes: $0) }
            case let .tripLogged(filter):
                tripFilterRows(filter)
            }
        } header: {
            SetSectionHeader(title: "Auslöser · \(AutoText.kindTitle(kind))")
        } footer: {
            SetFooter(text: triggerFooter)
        }
        .listRowBackground(Theme.surface)
    }

    @ViewBuilder
    private func tripFilterRows(_ filter: AutoTripFilter) -> some View {
        Picker(selection: Binding(get: { filter.minValueEUR ?? 0 }, set: { value in
            var copy = filter
            copy.minValueEUR = value > 0 ? value : nil
            draft.trigger = .tripLogged(copy)
        })) {
            Text("Jeder Wert").tag(0.0)
            ForEach(AutoTripFilter.valueChoices, id: \.self) { Text("ab \(AutoText.euro($0))").tag($0) }
        } label: {
            Label("Mindestwert", systemImage: "eurosign.circle")
        }
        .pickerStyle(.menu)
        Picker(selection: Binding(get: { filter.modes.count == 1 ? filter.modes.first : nil }, set: { mode in
            var copy = filter
            copy.modes = mode.map { [$0] } ?? []
            draft.trigger = .tripLogged(copy)
        })) {
            Text("Alle").tag(TransportMode?.none)
            ForEach(TransportMode.allCases.filter { $0 != .other }) { mode in
                Label(mode.displayName, systemImage: mode.symbolName).tag(TransportMode?.some(mode))
            }
        } label: {
            Label("Verkehrsmittel", systemImage: "tram")
        }
        .pickerStyle(.menu)
        Picker(selection: Binding(get: { filter.route.map(routeKey) ?? "" }, set: { key in
            var copy = filter
            copy.route = routeChoices.first { routeKey($0) == key }
            draft.trigger = .tripLogged(copy)
        })) {
            Text("Alle Strecken").tag("")
            ForEach(routeChoices, id: \.self) { route in
                Text("\(TripRow.short(route.fromName)) ⇄ \(TripRow.short(route.toName))").tag(routeKey(route))
            }
        } label: {
            Label("Strecke", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
        }
        .pickerStyle(.menu)
    }

    /// The routes of „Favoriten“ and „Meine Routen“ (two stations, no combination), plus the rule's own route.
    private var routeChoices: [AutoRouteRef] {
        var refs = routes.filter { !$0.isCombo && !$0.fromName.isEmpty && !$0.toName.isEmpty }.map {
            AutoRouteRef(fromName: $0.fromName, toName: $0.toName, fromStationID: $0.fromStationID, toStationID: $0.toStationID)
        }
        if case let .tripLogged(filter) = draft.trigger, let own = filter.route, !refs.contains(own) { refs.insert(own, at: 0) }
        var seen = Set<String>()
        return refs.filter { seen.insert(routeKey($0)).inserted }
    }

    private func routeKey(_ route: AutoRouteRef) -> String {
        "\(route.fromStationID ?? route.fromName)|\(route.toStationID ?? route.toName)"
    }

    private var triggerFooter: String {
        switch kind {
        case .ticketDeadline:
            let ticket = probe?.state.ticket ?? runner.state.ticket
            let validity = ticket.map { " \($0.name) gilt bis \(AutoText.dateText($0.end, calendar: .vienna))." } ?? " Noch ist kein Ticket erfasst."
            return "Um 09:00 Uhr an diesem Tag, als vorab geplante Mitteilung – auch wenn die App geschlossen ist." + validity
        case .milestone:
            return "Geprüft nach jedem Speichern einer Fahrt. Jeder Meilenstein meldet sich einmal pro Ticket; was beim Einschalten schon erreicht war, zählt nicht."
        case .dayWithoutTrip:
            return "Für die nächsten \(AutoRuleScheduler.horizonDays) Tage vorab geplant. Sobald an dem Tag eine Fahrt erfasst ist, fällt die Mitteilung weg."
        case .followDelay:
            return "Nur während „Live verfolgen“ läuft. Die Regel liest die Antworten, die die Verfolgung ohnehin abfragt – keine zusätzliche Abfrage bei den ÖBB. Gemeldet wird einmal je Fahrt, erneut erst, wenn die Verspätung unter den Wert fällt und wieder steigt."
        case .tripLogged:
            return "Geprüft nach dem Speichern. Ein Import mit mehr als \(AutoSnapshot.bulkLimit) Fahrten löst nichts aus."
        }
    }

    // MARK: Conditions

    private var conditionSection: some View {
        Section {
            ForEach(kind.allowedConditions) { option in
                Toggle(isOn: conditionBinding(option)) {
                    Label(option.autoTitle, systemImage: option.autoSymbol)
                }
                if let condition = draft.condition(option) {
                    conditionEditor(condition)
                        .motionTransition(.rise)
                }
            }
        } header: {
            SetSectionHeader(title: "Bedingungen")
        } footer: {
            SetFooter(text: "Hält eine Bedingung nicht, bleibt die Regel still – der Testlauf sagt, welche.")
        }
        .listRowBackground(Theme.surface)
    }

    @ViewBuilder
    private func conditionEditor(_ condition: AutoCondition) -> some View {
        switch condition {
        case let .weekdays(days):
            AutoWeekdayPicker(selection: Binding(get: { days }, set: { replace(.weekdays($0)) }))
        case let .timeWindow(start, end):
            AutoTimeRow(title: "Von", minute: Binding(get: { start }, set: { replace(.timeWindow(startMinute: $0, endMinute: end)) }))
            AutoTimeRow(title: "Bis", minute: Binding(get: { end }, set: { replace(.timeWindow(startMinute: start, endMinute: $0)) }))
        case .noTripToday, .validTicket:
            EmptyView()
        }
    }

    private func conditionBinding(_ option: AutoConditionKind) -> Binding<Bool> {
        Binding(get: { draft.condition(option) != nil }, set: { on in
            withMotion(Motion.smooth) {
                draft.conditions.removeAll { $0.kind == option }
                if on { draft.conditions.append(option.defaultCondition) }
            }
        })
    }

    private func replace(_ condition: AutoCondition) {
        guard let index = draft.conditions.firstIndex(where: { $0.kind == condition.kind }) else { return }
        draft.conditions[index] = condition
    }

    // MARK: Action

    private var actionSection: some View {
        Section {
            Toggle(isOn: Binding(get: { draft.addTrip != nil }, set: setOpensAddTrip)) {
                Label("Tippen öffnet „Fahrt erfassen“", systemImage: "plus.circle")
            }
            Toggle(isOn: Binding(get: { draft.actions.contains { $0.kind == .openShortcut } }, set: setShortcut)) {
                Label("Kurzbefehl anbieten", systemImage: "square.2.layers.3d")
            }
            if let index = draft.actions.firstIndex(where: { $0.kind == .openShortcut }) {
                TextField("Name des Kurzbefehls", text: Binding(get: {
                    if case let .openShortcut(name) = draft.actions[index] { return name }
                    return ""
                }, set: { draft.actions[index] = .openShortcut(name: String($0.prefix(60))) }))
                .textInputAutocapitalization(.sentences)
                .motionTransition(.rise)
            }
            TextField("Eigener Titel", text: Binding(get: { draft.customTitle }, set: setTitle),
                      prompt: Text("Automatisch: \(previewTitle)"))
            if kind.usesCooldown {
                Picker(selection: $draft.cooldownMinutes) {
                    ForEach(AutoRule.cooldownChoices, id: \.self) { Text(cooldownTitle($0)).tag($0) }
                } label: {
                    Label("Danach Pause", systemImage: "hourglass")
                }
                .pickerStyle(.menu)
            }
        } header: {
            SetSectionHeader(title: "Dann")
        } footer: {
            SetFooter(text: "In der offenen App kommt ein Hinweis mit Vibration, sonst eine Mitteilung von iOS. Ein Kurzbefehl öffnet die Kurzbefehle-App und startet ihn dort – das ist nie unbemerkt. Eine Regel schreibt nie eine Fahrt.")
        }
        .listRowBackground(Theme.surface)
    }

    private var previewTitle: String {
        if let probe, let firing = probe.verdict.firings.first { return firing.title }
        switch kind {
        case .ticketDeadline: if case let .ticketDeadline(days) = draft.trigger { return days <= 1 ? "Dein Ticket läuft ab" : "Noch \(days) Tage gültig" }
        case .milestone: return "50 % geschafft"
        case .dayWithoutTrip: return "Heute noch keine Fahrt erfasst"
        case .followDelay: return "Verspätung 12 Min"
        case .tripLogged: return "Fahrt erfasst"
        }
        return draft.name
    }

    private func cooldownTitle(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Keine"
        case 1440: "1 Tag"
        case let m where m % 60 == 0: "\(m / 60) Std"
        default: "\(minutes) Min"
        }
    }

    private func setTitle(_ title: String) {
        let body = draft.customBody
        draft.actions.removeAll { $0.kind == .notify }
        draft.actions.insert(.notify(title: String(title.prefix(60)), body: body), at: 0)
    }

    private func setOpensAddTrip(_ on: Bool) {
        withMotion(Motion.smooth) {
            draft.actions.removeAll { $0.kind == .openAddTrip }
            if on { draft.actions.append(.openAddTrip(fromStationID: nil, toStationID: nil)) }
        }
    }

    private func setShortcut(_ on: Bool) {
        withMotion(Motion.smooth) {
            draft.actions.removeAll { $0.kind == .openShortcut }
            if on { draft.actions.append(.openShortcut(name: "")) }
        }
    }

    // MARK: Name

    private var nameSection: some View {
        Section {
            TextField("Name", text: Binding(get: { draft.name }, set: { draft.name = String($0.prefix(AutoRule.maxNameLength)) }),
                      prompt: Text(AutoText.defaultName(for: kind)))
                .textInputAutocapitalization(.sentences)
            Toggle(isOn: $draft.isEnabled) {
                Label("Regel ist an", systemImage: "power")
            }
        } header: {
            SetSectionHeader(title: "Name")
        }
        .listRowBackground(Theme.surface)
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) { confirmsDelete = true } label: {
                Label("Regel löschen", systemImage: "trash").foregroundStyle(Theme.negativeText)
            }
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: Changes

    private func setKind(_ newKind: AutoTriggerKind) {
        guard newKind != kind else { return }
        withMotion(Motion.smooth) {
            let hadDefaultName = draft.name.isEmpty || draft.name == AutoText.defaultName(for: kind)
            draft.trigger = newKind.defaultTrigger
            draft.conditions = draft.conditions.filter { newKind.allowedConditions.contains($0.kind) }
            if !newKind.usesCooldown { draft.cooldownMinutes = 0 } else if draft.cooldownMinutes == 0, newKind == .followDelay { draft.cooldownMinutes = 30 }
            if hadDefaultName { draft.name = AutoText.defaultName(for: newKind) }
            draft.templateID = nil
        }
    }

    private func save() {
        var rule = draft.normalized
        if case let .openShortcut(name) = rule.actions.first(where: { $0.kind == .openShortcut }),
           name.trimmingCharacters(in: .whitespaces).isEmpty {
            rule.actions.removeAll { $0.kind == .openShortcut }   // a shortcut without a name is no shortcut
        }
        savedTick += 1
        withMotion(Motion.smooth) { store.save(rule, ticket: runner.currentTicket) }
        runner.rulesChanged(asksPermission: rule.isEnabled)
        dismiss()
    }

    private func delete() {
        withMotion(Motion.smooth) { store.delete(draft.id) }
        runner.rulesChanged(asksPermission: false)
        dismiss()
    }
}

/// A clock time (minutes after midnight) with the system's wheel, always in Vienna time.
struct AutoTimeRow: View {
    var title: String
    @Binding var minute: Int

    private static let vienna = TimeZone(identifier: "Europe/Vienna") ?? .current

    var body: some View {
        DatePicker(title, selection: Binding(get: {
            AutoClock.moment(on: AutoStore.shared.now(), minuteOfDay: minute, calendar: .vienna) ?? Date()
        }, set: { date in
            minute = AutoClock.minuteOfDay(date, calendar: .vienna)
        }), displayedComponents: .hourAndMinute)
        .environment(\.timeZone, Self.vienna)
        .environment(\.locale, Format.locale)   // 19:00, not 7:00 PM
    }
}

/// The Testlauf: the engine's verdict in words (selectable, read by VoiceOver as one sentence), a preview of the notice when
/// it would fire, and what the decision was made from.
struct AutoTestCard: View {
    let probe: AutoProbe
    let rule: AutoRule

    var body: some View {
        let verdict = probe.verdict
        let explanation = AutoText.explanation(verdict, calendar: .vienna)
        let split = Self.split(explanation)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(alignment: .center, spacing: Theme.Spacing.xs) {
                    Image(systemName: symbol(verdict.outcome))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(tint(verdict.outcome), in: Circle())
                        .environment(\.colorScheme, .light)
                        .symbolReplaceTransition()
                    VStack(alignment: .leading, spacing: 0) {
                        Kicker(text: "Testlauf · \(AutoClock.clockText(AutoClock.minuteOfDay(verdict.now, calendar: .vienna)))")
                        Text(split.head)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.opacity)
                    }
                }
                Text(split.tail)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .contentTransition(.opacity)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(explanation)
            .accessibilityAddTraits(.updatesFrequently)
            if let preview {
                Text(verdict.outcome == .now ? "So käme die Mitteilung" : "So kommt die Mitteilung")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                AutoNoticePreview(title: preview.title, ruleName: rule.name, message: preview.body, timeText: preview.time)
            }
            Text(basis)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(tint(verdict.outcome).opacity(0.35), lineWidth: 1)
        }
        .motionAnimation(Motion.smooth, value: explanation)
    }

    /// „Würde jetzt auslösen“ and the rest, split at the first colon – both parts of the engine's one sentence.
    static func split(_ text: String) -> (head: String, tail: String) {
        guard let range = text.range(of: ": ") else { return (text, "") }
        return (String(text[..<range.lowerBound]), String(text[range.upperBound...]).autoSentenceStart)
    }

    private var preview: (title: String, body: String, time: String)? {
        let verdict = probe.verdict
        if let firing = verdict.firings.first { return (firing.title, firing.body, "jetzt") }
        if case let .at(date) = verdict.outcome {
            let content = AutoText.content(rule: rule, reason: verdict.reason, calendar: .vienna)
            return (content.title, content.body, AutoText.whenShort(date, now: verdict.now, calendar: .vienna))
        }
        return nil
    }

    /// What the decision was read from – never more than the app knows.
    private var basis: String {
        let state = probe.state
        switch rule.trigger.kind {
        case .followDelay:
            guard let follow = state.follow else { return "Grundlage: keine laufende Live-Verfolgung." }
            return "Grundlage: die letzte Antwort von „Live verfolgen“ (\(follow.lineName), \(AutoClock.clockText(AutoClock.minuteOfDay(follow.updatedAt, calendar: .vienna)))) – keine neue Abfrage."
        case .milestone:
            guard let ticket = state.ticket else { return "Grundlage: kein Ticket erfasst." }
            return "Grundlage: \(ticket.name), \(ticket.percent) % amortisiert (\(AutoText.euro(ticket.value)) von \(AutoText.euro(ticket.price)))."
        case .ticketDeadline:
            guard let ticket = state.ticket else { return "Grundlage: kein Ticket erfasst." }
            return "Grundlage: \(ticket.name), gültig bis \(AutoText.dateText(ticket.end, calendar: .vienna))."
        case .dayWithoutTrip:
            return "Grundlage: deine erfassten Fahrten von heute bis in \(AutoRuleScheduler.horizonDays) Tagen."
        case .tripLogged:
            return "Grundlage: deine zuletzt gespeicherte Fahrt."
        }
    }

    private func symbol(_ outcome: AutoOutcome) -> String {
        switch outcome {
        case .now: "bolt.fill"
        case .at: "clock.fill"
        case .silent: "moon.zzz.fill"
        }
    }

    private func tint(_ outcome: AutoOutcome) -> Color {
        switch outcome {
        case .now: Theme.pine
        case .at: Theme.glacier
        case .silent: Theme.dusk
        }
    }
}
