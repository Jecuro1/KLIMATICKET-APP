import SwiftUI
import UIKit
import KlimaCore

// MARK: calendarsuggestions – Einstellungen › Kalender-Vorschläge (docs/CALENDAR_SUGGESTIONS.md §2): the switch (off by default), the
// permission state with its own words (nicht gefragt, verweigert, eingeschränkt, nur hinzufügen, keine Kalender, aktiv), the calendars
// to read (birthdays and subscriptions are not offered; before the first pick only the default calendar is ticked) and the buffer.

struct CalendarSettingsPage: View {
    /// Opened from the Übersicht or klimabilanz://calendar (own sheet with „Fertig“).
    var isSheet = false
    /// CI scene `calendarSettingsBottom`: scrolls to „Datenschutz“ after the first frame.
    var screenshotScrollsDown = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = CalendarSuggestionStore.shared
    @State private var changeTick = 0

    var body: some View {
        ScrollViewReader { proxy in
            list.task {
                guard screenshotScrollsDown else { return }
                try? await Task.sleep(for: .milliseconds(600))
                proxy.scrollTo("privacy", anchor: .bottom)
            }
        }
    }

    private var list: some View {
        List {
            switchSection
            if store.prefs.isEnabled {
                stateSection
                if store.access == .fullAccess, !store.offered.isEmpty {
                    calendarsSection
                    bufferSection
                }
            }
            privacySection.id("privacy")
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop() }
        .tint(Theme.accent)
        .navigationTitle("Kalender-Vorschläge")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .motionAnimation(Motion.smooth, value: store.prefs.isEnabled)
        .motionAnimation(Motion.smooth, value: store.access)
        .haptic(.selection, trigger: changeTick)
        .sheet(isPresented: $store.showsExplanation) {
            CalendarExplainSheet(onContinue: { Task { await store.confirmExplanation() } }, onCancel: { store.cancelExplanation() })
                .interactiveDismissDisabled(store.isRequesting)
        }
        .sheet(isPresented: $store.showsPicker) {
            NavigationStack { CalendarPickerSheet() }
                .presentationDetents([.medium, .large])
        }
        .onAppear { if !store.isDemo { store.refreshAccess() } }
        .onChange(of: scenePhase) { _, phase in
            // Back from iOS Settings: the permission may have changed.
            if phase == .active, !store.isDemo { store.refreshAccess() }
        }
    }

    // MARK: Switch

    private var switchSection: some View {
        Section {
            Toggle(isOn: Binding(get: { store.prefs.isEnabled || store.showsExplanation }, set: { store.setEnabled($0) })) {
                SetRowLabel(title: "Kalender-Vorschläge", subtitle: "Termine mit Ort werden zu Zugfahrt-Vorschlägen in der Übersicht",
                            symbol: "calendar.badge.clock", tint: Theme.dusk)
                    .setSymbolOnEnable(store.prefs.isEnabled)
            }
            .disabled(store.isRequesting)
            .listRowBackground(Theme.surface)
        } footer: {
            SetFooter(text: "Wir lesen nur Titel, Ort und Zeit deiner Termine, nur auf diesem iPhone, nur während die App offen ist.")
        }
    }

    // MARK: Permission state

    private var stateSection: some View {
        Section {
            CalendarStateRow(state: store.setupState, selectedCount: store.selectedCalendars.count)
                .listRowBackground(Theme.surface)
            if let action = stateAction {
                Button(action: action.run) {
                    SetRowLabel(title: action.title, subtitle: action.subtitle, symbol: action.symbol, tint: Theme.glacier)
                }
                .listRowBackground(Theme.surface)
            }
        } header: {
            SetSectionHeader(title: "Zugriff")
        }
    }

    private struct StateAction {
        var title: String
        var subtitle: String?
        var symbol: String
        var run: () -> Void
    }

    private var stateAction: StateAction? {
        let openSettings = { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
        switch store.setupState {
        case .needsPermission:
            return StateAction(title: "Zugriff erlauben", subtitle: "Zuerst erklärt, dann fragt iOS", symbol: "hand.raised.fill") {
                store.showsExplanation = true
            }
        case .denied, .writeOnly:
            return StateAction(title: "In den iOS-Einstellungen ändern", subtitle: "Apps › KlimaBilanz › Kalender › Vollzugriff",
                               symbol: "gearshape.fill", run: openSettings)
        default:
            return nil
        }
    }

    // MARK: Calendars

    private var calendarsSection: some View {
        Section {
            CalendarPickerRows(changeTick: $changeTick)
        } header: {
            SetSectionHeader(title: "Kalender")
        } footer: {
            SetFooter(text: "Geburtstage und abonnierte Kalender (Feiertage, Sport) bietet die App nicht an.")
        }
    }

    // MARK: Buffer

    private var bufferSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Ankunft vor dem Termin", subtitle: "Gilt für neue Vorschläge; jede Karte lässt sich einzeln ändern",
                            symbol: "flag.checkered", tint: Theme.dawn)
                GlassSegmentedPicker(selection: Binding(get: { store.prefs.bufferMinutes }, set: { store.setBuffer($0) }),
                                     options: CalendarBuffer.options, tint: Theme.dawn) { minutes in
                    Text("\(minutes) min")
                        .monospacedDigit()
                        .accessibilityLabel("\(minutes) Minuten")
                }
            }
            .padding(.vertical, Theme.Spacing.xxs)
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Puffer")
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                privacyLine("iphone", "Gelesen wird nur auf diesem iPhone, solange KlimaBilanz offen ist – nie im Hintergrund.")
                privacyLine("tray", "Gespeichert werden keine Titel und keine Orte; für „Kein Zug“ nur ein Prüfwert, höchstens 60 Tage.")
                privacyLine("network.slash", "Kein Server, keine KI, keine Statistik, keine Synchronisierung.")
                privacyLine("tram", "„Verbindung suchen“ fragt die ÖBB nur mit deiner Live-Daten-Erlaubnis – mit zwei Bahnhöfen und einer Uhrzeit.")
            }
            .padding(.vertical, Theme.Spacing.xxs)
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Datenschutz")
        }
    }

    private func privacyLine(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.positiveText)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - State row

/// The permission state in words, with a symbol and a colour (never colour alone).
struct CalendarStateRow: View {
    let state: CalendarSetupState
    let selectedCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: look.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(look.tint)
                .frame(width: 30)
                .symbolBounce(on: state)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(look.title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(look.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private var look: (symbol: String, tint: Color, title: String, detail: String) {
        switch state {
        case .off:
            return ("pause.circle.fill", Theme.textSecondary, "Aus", "Die App liest keine Termine.")
        case .needsPermission:
            return ("questionmark.circle.fill", Theme.accentText, "Noch nicht erlaubt",
                    "iOS hat noch nicht gefragt. Ohne Lesezugriff gibt es keine Vorschläge.")
        case .denied:
            return ("xmark.octagon.fill", Theme.negativeText, "Zugriff verweigert",
                    "Kalender-Vorschläge brauchen Lesezugriff. Du kannst ihn in den iOS-Einstellungen erlauben – oder es so lassen.")
        case .restricted:
            return ("lock.circle.fill", Theme.negativeText, "Zugriff eingeschränkt",
                    "Bildschirmzeit oder ein Geräteprofil sperrt den Kalender für Apps. Ändern kann das nur, wer diese Einschränkung verwaltet.")
        case .writeOnly:
            return ("square.and.pencil.circle.fill", Theme.summitText, "Nur Hinzufügen erlaubt",
                    "Damit darf KlimaBilanz Termine eintragen, aber nicht lesen. Für Vorschläge braucht es „Vollzugriff“.")
        case .noCalendars:
            return ("calendar.badge.exclamationmark", Theme.summitText, "Keine Kalender gefunden",
                    "Auf diesem iPhone gibt es keinen Kalender, den die App lesen kann. Geburtstage und abonnierte Kalender zählen nicht.")
        case .noneSelected:
            return ("circle.dashed", Theme.summitText, "Kein Kalender gewählt", "Wähle unten, welche Kalender die App lesen darf.")
        case .active:
            return ("checkmark.circle.fill", Theme.positiveText, "Aktiv",
                    selectedCount == 1 ? "Liest 1 Kalender, die nächsten 14 Tage." : "Liest \(selectedCount) Kalender, die nächsten 14 Tage.")
        }
    }
}

// MARK: - Calendar picker

/// One row per calendar: colour dot, name, account, a check. Tapping ticks or unticks.
struct CalendarPickerRows: View {
    @Binding var changeTick: Int
    @State private var store = CalendarSuggestionStore.shared

    var body: some View {
        ForEach(store.offered) { calendar in
            let isOn = store.prefs.calendarIDs.contains(calendar.id)
            Button {
                changeTick += 1
                withMotion(Motion.snappy) { store.toggleCalendar(calendar.id) }
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Circle()
                        .fill(Color(hex: calendar.colorHex ?? "#7A6FE0"))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Theme.separator, lineWidth: 1))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(calendar.title)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                        Text(calendar.isDefault ? "\(calendar.sourceTitle) · Standardkalender" : calendar.sourceTitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: Theme.Spacing.xs)
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isOn ? Theme.accent : Theme.textTertiary)
                        .symbolReplaceTransition()
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .listRowBackground(Theme.surface)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            .accessibilityHint(isOn ? "Wird gelesen. Tippen, um ihn auszulassen." : "Wird nicht gelesen. Tippen, um ihn zu lesen.")
        }
    }
}

/// The picker right after access was granted: which calendars to read.
struct CalendarPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var changeTick = 0

    var body: some View {
        List {
            Section {
                CalendarPickerRows(changeTick: $changeTick)
            } header: {
                SetSectionHeader(title: "Welche Kalender?")
            } footer: {
                SetFooter(text: "Vorgewählt ist nur dein Standardkalender. Geburtstage und abonnierte Kalender bietet die App nicht an.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background { Theme.sheetBackground.ignoresSafeArea() }
        .navigationTitle("Kalender wählen")
        .navigationBarTitleDisplayMode(.inline)
        .haptic(.selection, trigger: changeTick)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }.fontWeight(.semibold)
            }
        }
    }
}

// MARK: - Settings entry

/// The row in Einstellungen: „Kalender-Vorschläge“ with its state.
struct SetCalendarSection: View {
    @State private var store = CalendarSuggestionStore.shared

    var body: some View {
        Section {
            NavigationLink {
                CalendarSettingsPage()
            } label: {
                SetRowLabel(title: "Kalender-Vorschläge", subtitle: subtitle, symbol: "calendar.badge.clock", tint: Theme.dusk)
                    .setSymbolOnEnable(store.setupState == .active)
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Kalender")
        }
        .onAppear { if !store.isDemo, store.prefs.isEnabled { store.refreshAccess() } }
    }

    private var subtitle: String {
        switch store.setupState {
        case .off: "Aus · schlägt Zugfahrten zu deinen Terminen vor"
        case .needsPermission: "An · Zugriff noch nicht erlaubt"
        case .denied: "An · Zugriff verweigert"
        case .restricted: "An · Zugriff eingeschränkt"
        case .writeOnly: "An · nur Hinzufügen erlaubt"
        case .noCalendars: "An · keine Kalender gefunden"
        case .noneSelected: "An · kein Kalender gewählt"
        case .active: store.selectedCalendars.count == 1 ? "An · 1 Kalender" : "An · \(store.selectedCalendars.count) Kalender"
        }
    }
}
