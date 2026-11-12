import SwiftUI
import SwiftData
import UIKit
import KlimaCore

// MARK: tripdetect – Einstellungen › Fahrten erkennen (docs/TRIP_DETECTION.md): Fahrt aufzeichnen, Hintergrund-Erkennung (Beta),
// Fahrplan-Abgleich, das Erkennungs-Protokoll und "Alle Standortdaten löschen". Plus the entry row of the capture section.

/// What the page shows – read from the service on the device, a synthetic one in the CI scenes.
struct TripDetectSettingsState: Equatable {
    var isEnabled = false
    var isAuthorizedAlways = false
    var isDenied = false
    var isAvailable = true
    var points = 0
    var visits = 0
    var oldest: Date?
    var logCount = 0
    var timetableLookup = true
    var liveConsentGranted = false

    @MainActor
    static func live(_ service: TripDetectionService, liveConsent: Bool) -> TripDetectSettingsState {
        TripDetectSettingsState(isEnabled: service.isEnabled, isAuthorizedAlways: service.isAuthorizedAlways, isDenied: service.isDenied,
                                isAvailable: service.isAvailable, points: service.bufferSummary.points, visits: service.bufferSummary.visits,
                                oldest: service.bufferSummary.oldest, logCount: service.log.entries.count,
                                timetableLookup: service.timetableLookupEnabled, liveConsentGranted: liveConsent)
    }
}

struct TripDetectSettingsView: View {
    /// CI scenes: the state to show instead of the live one.
    var preview: TripDetectSettingsState? = nil

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsExplain = false
    @State private var confirmsDeletion = false
    @State private var deletionTick = 0
    @Query(filter: #Predicate<TripCandidateEntity> { $0.statusRaw == "pending" }) private var pending: [TripCandidateEntity]

    private var state: TripDetectSettingsState {
        preview ?? .live(app.detection, liveConsent: app.live.consent == .granted)
    }

    var body: some View {
        let state = state
        List {
            recordSection
            backgroundSection(state)
            timetableSection(state)
            logSection(state)
            dataSection(state)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop() }
        .tint(Theme.accent)
        .revealScope()
        .navigationTitle("Fahrten erkennen")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showsExplain) {
            TripDetectExplainView(onEnable: { enable() }, onCancel: { showsExplain = false })
                .presentationBackground(Theme.sheetBackground)
        }
        .confirmationDialog("Alle Standortdaten löschen?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) { deleteAll() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Gelöscht werden die gesammelten Standortpunkte, das Erkennungs-Protokoll und alle Fahrten-Vorschläge samt Verlauf. Fahrten, die du schon übernommen hast, bleiben.")
        }
        .haptic(.warning, trigger: deletionTick)
        .onChange(of: scenePhase) { _, phase in
            // Back from the iOS Settings app: the permission may have changed.
            if phase == .active, preview == nil { app.detection.refreshAuthorization() }
        }
    }

    // MARK: Sections

    private var recordSection: some View {
        Section {
            NavigationLink {
                TripRecordView()
                    .toolbar(.hidden, for: .navigationBar)
            } label: {
                SetRowLabel(title: "Fahrt aufzeichnen", subtitle: "Genau, mit Live-Karte – du startest und beendest", symbol: "record.circle", tint: Theme.pine)
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Zuverlässig")
        } footer: {
            SetFooter(text: "Die Aufzeichnung nutzt den genauen Standort, solange sie läuft (blaue Anzeige). Beim Beenden schlägt KlimaBilanz die Fahrt vor – du bestätigst.")
        }
    }

    private func backgroundSection(_ state: TripDetectSettingsState) -> some View {
        Section {
            Group {
                Toggle(isOn: Binding(get: { state.isEnabled }, set: { setEnabled($0) })) {
                    SetRowLabel(title: "Hintergrund-Erkennung (Beta)",
                                subtitle: state.isAvailable ? "Schlägt Fahrten vor, wenn du an Bahnhöfen unterwegs bist" : "Auf diesem Gerät nicht verfügbar",
                                symbol: "location.fill", tint: Theme.glacier)
                        .setSymbolOnEnable(state.isEnabled)
                }
                .disabled(!state.isAvailable)
                .haptic(.start, trigger: state.isEnabled, when: { _, isOn in isOn })
                .haptic(.stop, trigger: state.isEnabled, when: { _, isOn in !isOn })
                if state.isEnabled {
                    Group {
                        if state.isAuthorizedAlways { activeRows(state) } else { permissionRow(state) }
                    }
                    .motionTransition(.rise)
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Im Hintergrund")
        } footer: {
            SetFooter(text: "Aus, bis du es mit Erklärung einschaltest. Es sammelt grobe Standortpunkte höchstens 36 Stunden lang nur auf diesem iPhone und schlägt Fahrten vor – nie ohne dein Okay. Eine Autofahrt zwischen zwei Orten mit Bahnhof kann wie eine Zugfahrt aussehen; deshalb fragt die App immer.")
        }
    }

    @ViewBuilder
    private func activeRows(_ state: TripDetectSettingsState) -> some View {
        SetRowLabel(title: "Aktiv",
                    subtitle: pendingCount == 0 ? "Vorschläge erscheinen in der Übersicht" : "\(SetFormat.count(pendingCount, "Vorschlag wartet", "Vorschläge warten")) in der Übersicht",
                    symbol: "checkmark.circle.fill", tint: Theme.pine)
            .motionAnimation(Motion.snappy, value: pendingCount)
        SetRowLabel(title: "Gespeichert auf diesem iPhone", subtitle: bufferText(state), symbol: "internaldrive.fill", tint: Theme.dusk)
    }

    private func permissionRow(_ state: TripDetectSettingsState) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SetRowLabel(title: state.isDenied ? "Standort ist aus" : "Standort „Immer“ fehlt",
                        subtitle: "Erlaube den Standortzugriff „Immer“, damit Fahrten auch im Hintergrund erkannt werden.",
                        symbol: "location.slash.fill", tint: Theme.dawn)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Einstellungen öffnen", systemImage: "gear").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func timetableSection(_ state: TripDetectSettingsState) -> some View {
        Section {
            Toggle(isOn: Binding(get: { state.timetableLookup && state.liveConsentGranted }, set: { app.detection.timetableLookupEnabled = $0 })) {
                SetRowLabel(title: "Fahrplan zum Abgleich nutzen", subtitle: "Einmal je Vorschlag nachsehen, ob ein Zug fuhr", symbol: "clock.badge.checkmark.fill", tint: Theme.glacier)
            }
            .disabled(!state.liveConsentGranted || preview != nil)
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Fahrplan")
        } footer: {
            SetFooter(text: state.liveConsentGranted
                      ? "Gesendet werden zwei Haltestellennamen und eine Uhrzeit an die ÖBB-Fahrplanauskunft – keine Koordinaten, nie dein Standort. Nur bei neuen Vorschlägen und über dasselbe Limit wie der Fahrplan."
                      : "Braucht deine Zustimmung zu Live-Daten (Einstellungen › Live-Daten). Ohne sie bleibt alles auf dem iPhone und es gibt kein Etikett „Sicher“.")
        }
    }

    private func logSection(_ state: TripDetectSettingsState) -> some View {
        Section {
            NavigationLink {
                TripDetectLogView(preview: nil)
            } label: {
                HStack {
                    SetRowLabel(title: "Erkennungs-Protokoll", subtitle: "Warum etwas vorgeschlagen wurde – oder nicht", symbol: "list.bullet.clipboard.fill", tint: Theme.gold)
                    Spacer(minLength: Theme.Spacing.xs)
                    if state.logCount > 0 {
                        Text(Format.number(Double(state.logCount))).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .listRowBackground(Theme.surface)
        } footer: {
            SetFooter(text: "Nur Haltestellennamen, Zeiten und Gründe – keine Koordinaten. Es bleibt auf dem iPhone, höchstens 14 Tage.")
        }
    }

    private func dataSection(_ state: TripDetectSettingsState) -> some View {
        Section {
            Button(role: .destructive) { confirmsDeletion = true } label: {
                SetRowLabel(title: "Alle Standortdaten löschen", subtitle: "Punkte, Protokoll und Vorschläge", symbol: "trash.fill", tint: Theme.negative)
            }
            .listRowBackground(Theme.surface)
        } footer: {
            SetFooter(text: "Die gesammelten Standortpunkte liegen nur in einer Datei auf diesem iPhone, die nicht im Backup ist und nie exportiert oder synchronisiert wird.")
        }
    }

    // MARK: Actions

    private var pendingCount: Int { preview != nil ? 2 : pending.count }

    private func setEnabled(_ on: Bool) {
        guard preview == nil else { return }
        if on {
            showsExplain = true
        } else {
            withMotion(Motion.smooth) { app.detection.disable() }
        }
    }

    private func enable() {
        showsExplain = false
        withMotion(Motion.smooth) { app.detection.enable() }
        Repository(context: context, app: app).configureTripDetection()
    }

    private func deleteAll() {
        deletionTick += 1
        let repository = Repository(context: context, app: app)
        repository.deleteAllCandidates()
        app.detection.deleteAllLocationData()
        app.detection.noteDeletion()
    }

    private func bufferText(_ state: TripDetectSettingsState) -> String {
        if state.points == 0 && state.visits == 0 { return "Noch nichts – höchstens 36 Stunden" }
        var parts: [String] = []
        if state.points > 0 { parts.append(SetFormat.count(state.points, "Ortspunkt", "Ortspunkte")) }
        if state.visits > 0 { parts.append(SetFormat.count(state.visits, "Aufenthalt", "Aufenthalte")) }
        if let oldest = state.oldest {
            let hours = max(1, Int(Date().timeIntervalSince(oldest) / 3600))
            parts.append("ältester vor \(hours) Std.")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - The entry row of Einstellungen › Fahrten erfassen

struct TripDetectEntryRow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationLink {
            TripDetectSettingsView()
        } label: {
            SetRowLabel(title: "Fahrten erkennen", subtitle: subtitle, symbol: "location.fill", tint: Theme.glacier)
                .setSymbolOnEnable(app.detection.isEnabled)
        }
    }

    private var subtitle: String {
        if app.detection.isEnabled { return app.detection.isAuthorizedAlways ? "Hintergrund-Erkennung aktiv (Beta)" : "Standort „Immer“ fehlt" }
        return "Aufzeichnen und Vorschläge im Hintergrund (Beta)"
    }
}

// MARK: - Erkennungs-Protokoll

struct TripDetectLogView: View {
    /// CI scenes: entries to show instead of the live log.
    var preview: [DetectionLogEntry]?

    @Environment(AppState.self) private var app
    @State private var confirmsClear = false

    private var entries: [DetectionLogEntry] { preview ?? app.detection.log.entries }

    var body: some View {
        List {
            if entries.isEmpty {
                Section {
                    Text("Noch nichts protokolliert. Sobald die Erkennung eine Bewegung ausgewertet hat, steht hier, ob und warum sie vorgeschlagen wurde.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .listRowBackground(Theme.surface)
                }
            } else {
                ForEach(groups, id: \.day) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            LogRow(entry: entry).listRowBackground(Theme.surface)
                        }
                    } header: {
                        SetSectionHeader(title: group.title)
                    }
                }
                Section {
                    Button(role: .destructive) { confirmsClear = true } label: {
                        SetRowLabel(title: "Protokoll leeren", symbol: "trash.fill", tint: Theme.negative)
                    }
                    .listRowBackground(Theme.surface)
                } footer: {
                    SetFooter(text: "Nur Haltestellennamen, Zeiten, Strecken und Gründe – keine Koordinaten. Höchstens 14 Tage, nur auf diesem iPhone.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop() }
        .tint(Theme.accent)
        .navigationTitle("Erkennungs-Protokoll")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Protokoll leeren?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Leeren", role: .destructive) { withMotion(Motion.smooth) { app.detection.clearLog() } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private struct DayGroup { var day: Date; var title: String; var entries: [DetectionLogEntry] }

    private var groups: [DayGroup] {
        let calendar = Calendar.vienna
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.tripStart ?? $0.loggedAt) }
        return byDay.keys.sorted(by: >).map { day in
            DayGroup(day: day, title: Format.relativeDay(day), entries: (byDay[day] ?? []).sorted { ($0.tripStart ?? $0.loggedAt) > ($1.tripStart ?? $1.loggedAt) })
        }
    }
}

private struct LogRow: View {
    let entry: DetectionLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Spacing.xs)
                    Text(timeText).font(.caption.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                }
                Text(entry.detail).font(.footnote).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        guard let start = entry.tripStart else { return Format.time(entry.loggedAt) }
        if let end = entry.tripEnd { return "\(Format.time(start))–\(Format.time(end))" }
        return Format.time(start)
    }

    private var symbol: String {
        switch entry.kind {
        case .proposed: "tray.and.arrow.down.fill"
        case .rejected: "xmark.circle.fill"
        case .duplicate: "doc.on.doc.fill"
        case .replaced: "arrow.triangle.merge"
        case .decision: "hand.tap.fill"
        case .info: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch entry.kind {
        case .proposed: Theme.accentText
        case .rejected: Theme.summitText
        case .duplicate, .replaced: Theme.textSecondary
        case .decision: Theme.positiveText
        case .info: Theme.textSecondary
        }
    }
}
