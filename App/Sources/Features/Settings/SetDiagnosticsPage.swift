import SwiftUI
import SwiftData
import KlimaCore

/// Einstellungen › Über KlimaBilanz › Diagnose & Stabilität: crashes, hangs and unexpected exits of the last 30 days,
/// the latest entries, this session's timings and the export of a diagnostics file for the developer.
/// Everything comes from `DiagnosticsService` and stays on the device until the user shares the file.
struct SetDiagnosticsPage: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    @State private var overview: DiagnosticsOverview?
    @State private var exportURL: URL?
    @State private var isPreparingExport = false
    @State private var watchdogOn = DiagnosticsService.shared.isWatchdogEnabled
    @State private var isConfirmingClear = false

    private static let latestLimit = 8

    var body: some View {
        List {
            statusSection
            countsSection
            latestSection
            if let highlights = overview?.metricKit {
                metricKitSection(highlights)
            }
            if let timings = overview?.timings, !timings.isEmpty {
                timingsSection(timings)
            }
            shareSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop(skyOpacity: 0.4, fadeEnd: 0.4) }
        .navigationTitle("Diagnose & Stabilität")
        .navigationBarTitleDisplayMode(.large)
        .task { await reload() }
        .refreshable { await reload() }
        .diagnosticsScreen("Diagnose & Stabilität")
    }

    // MARK: Status

    private var statusSection: some View {
        Section {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                // "Wird geladen …" morphs into the verdict: the stethoscope turns into the seal (or the ECG line).
                SetIconTile(symbol: status.symbol, tint: status.tint, size: 44)
                    .symbolReplaceTransition()
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.opacity)
                    Text(status.message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                    if let overview {
                        HStack(spacing: Theme.Spacing.xs) {
                            SetPill(text: SetFormat.count(overview.sessionCount, "Sitzung", "Sitzungen"), symbol: "clock")
                            if overview.metricKitPayloadCount > 0 {
                                SetPill(text: SetFormat.count(overview.metricKitPayloadCount, "iOS-Bericht", "iOS-Berichte"),
                                        symbol: "doc.text")
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Spacing.xxs)
            .accessibilityElement(children: .combine)
            .listRowBackground(Theme.surface)
        }
    }

    private struct Status {
        var title: String
        var message: String
        var symbol: String
        var tint: Color
    }

    private var status: Status {
        guard let overview else {
            return Status(title: "Wird geladen …", message: "Diagnosedaten werden gelesen.", symbol: "stethoscope", tint: Theme.glacier)
        }
        if overview.isQuiet {
            return Status(title: "Alles stabil", message: "Keine Abstürze, Hänger oder unerwarteten Beendigungen in den letzten 30 Tagen.",
                          symbol: "checkmark.seal.fill", tint: Theme.pine)
        }
        let total = overview.crashes + overview.hangs + overview.abnormalExits + overview.resourceWarnings
        return Status(title: SetFormat.count(total, "Auffälligkeit", "Auffälligkeiten"),
                      message: "Teile die Diagnosedatei mit der Entwicklung – so lassen sich Ruckler und Abstürze gezielt beheben.",
                      symbol: "waveform.path.ecg", tint: Theme.dawn)
    }

    // MARK: Counts

    private var countsSection: some View {
        Section {
            Group {
                countRow(title: "Abstürze", subtitle: "Berichte von iOS", symbol: "exclamationmark.octagon.fill",
                         tint: Theme.negative, value: overview.map { "\($0.crashes)" })
                countRow(title: "Hänger", subtitle: hangSubtitle, symbol: "hourglass", tint: Theme.dawn,
                         value: overview.map { "\($0.hangs)" })
                countRow(title: "Unerwartet beendet", subtitle: "Im Vordergrund ohne sauberes Ende",
                         symbol: "bolt.horizontal.circle.fill", tint: Theme.dusk, value: overview.map { "\($0.abnormalExits)" })
                countRow(title: "Ressourcen-Warnungen", subtitle: "CPU- oder Schreiblast über dem iOS-Limit", symbol: "cpu.fill",
                         tint: Theme.gold, value: overview.map { "\($0.resourceWarnings)" })
                countRow(title: "App-Start", subtitle: launchSubtitle, symbol: "speedometer", tint: Theme.glacier,
                         value: overview?.lastLaunch.map { Self.duration($0.processToFirstFrameMs ?? $0.initToFirstFrameMs) } ?? "–")
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Letzte 30 Tage")
        }
    }

    private var hangSubtitle: String {
        if let longest = overview?.longestHangMs { return "Länger als 250 ms blockiert · längster \(Self.duration(longest))" }
        return "Bedienung länger als 250 ms blockiert"
    }

    private var launchSubtitle: String {
        guard let launch = overview?.lastLaunch else { return "Bis zur ersten Ansicht" }
        return launch.processToFirstFrameMs == nil ? "Bis zur ersten Ansicht (ab App-Code)" : "Bis zur ersten Ansicht, dieser Start"
    }

    private func countRow(title: String, subtitle: String, symbol: String, tint: Color, value: String?) -> some View {
        LabeledContent {
            Text(value ?? "–")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
        } label: {
            SetRowLabel(title: title, subtitle: subtitle, symbol: symbol, tint: tint)
        }
    }

    // MARK: Latest

    private var latestSection: some View {
        Section {
            Group {
                if let events = overview?.latest, !events.isEmpty {
                    ForEach(events.prefix(Self.latestLimit)) { event in
                        eventRow(event)
                    }
                    if events.count > Self.latestLimit {
                        NavigationLink {
                            SetDiagnosticsEventsPage(events: events)
                        } label: {
                            Text("Alle \(events.count) Einträge")
                                .foregroundStyle(Theme.accentText)
                        }
                    }
                } else {
                    Label {
                        Text(overview == nil ? "Wird geladen …" : "Noch keine Einträge")
                            .foregroundStyle(Theme.textSecondary)
                    } icon: {
                        SetIconTile(symbol: "tray", tint: Theme.textTertiary)
                    }
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Zuletzt")
        }
    }

    fileprivate static func eventRowLabel(_ event: DiagnosticsEvent) -> some View {
        let style = SetDiagnosticsStyle(kind: event.kind)
        var title = event.title
        if let ms = event.durationMs { title += " · \(duration(ms))" }
        var lines = [[event.screen, "\(Format.weekdayDayMonth(event.date)), \(Format.time(event.date))"]
            .compactMap { $0 }.joined(separator: " · ")]
        if let build = event.build { lines[0] += " · Build \(build)" }
        if let detail = event.detail, event.kind == .crash || event.kind == .fatalHang || event.source == .metricKit {
            lines.append(detail)
        }
        return SetRowLabel(title: title, subtitle: lines.joined(separator: "\n"), symbol: style.symbol, tint: style.tint)
            .accessibilityElement(children: .combine)
    }

    private func eventRow(_ event: DiagnosticsEvent) -> some View {
        Self.eventRowLabel(event)
    }

    // MARK: MetricKit

    private func metricKitSection(_ highlights: MetricKitHighlights) -> some View {
        Section {
            Group {
                if let ratio = highlights.scrollHitchTimeRatio {
                    metricRow("Ruckeln beim Scrollen", "\(Format.number(ratio, decimals: 1)) ms/s", symbol: "scroll.fill", tint: Theme.dawn)
                }
                if let firstDraw = highlights.averageTimeToFirstDrawMs {
                    metricRow("Start bis erstes Bild", Self.duration(firstDraw), symbol: "speedometer", tint: Theme.glacier)
                }
                if let hang = highlights.averageHangTimeMs {
                    metricRow("Hänger im Schnitt", Self.duration(hang), symbol: "hourglass", tint: Theme.dusk)
                }
                if let memory = highlights.peakMemoryMB {
                    metricRow("Speicher-Spitze", "\(Format.number(memory)) MB", symbol: "memorychip.fill", tint: Theme.pine)
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Von iOS gemessen")
        } footer: {
            SetFooter(text: "Tageswerte von iOS (MetricKit), zuletzt bis \(Format.dayMonth(highlights.periodEnd)). Unter 5 ms/s Ruckeln fühlt sich Scrollen flüssig an.")
        }
    }

    private func metricRow(_ title: String, _ value: String, symbol: String, tint: Color) -> some View {
        LabeledContent {
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        } label: {
            SetRowLabel(title: title, symbol: symbol, tint: tint)
        }
    }

    // MARK: Timings

    private static let timingNames: [(key: String, title: String)] = [
        ("Analytics.make", "Bilanz berechnen"),
        ("Analytics.compute", "davon Statistik"),
        ("Widgets.refresh", "Widgets aktualisieren"),
        ("Repository.save", "Speichern"),
        ("Sync", "Synchronisieren"),
    ]

    private func timingsSection(_ timings: [String: TimingStat]) -> some View {
        Section {
            Group {
                ForEach(Self.timingNames.filter { timings[$0.key] != nil }, id: \.key) { entry in
                    if let stat = timings[entry.key] {
                        LabeledContent {
                            Text("Ø \(Self.duration(stat.averageMs)) · max \(Self.duration(stat.maxMs))")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("\(stat.count)× · \(entry.key)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Diese Sitzung")
        } footer: {
            SetFooter(text: "Wie lange wiederkehrende Arbeiten der App seit dem Start gedauert haben.")
        }
    }

    // MARK: Share & settings

    private var shareSection: some View {
        Section {
            Group {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        SetRowLabel(title: "Diagnosedatei teilen", subtitle: "JSON-Datei für die Entwicklung",
                                    symbol: "square.and.arrow.up.fill", tint: Theme.glacier)
                    }
                } else {
                    SetRowLabel(title: "Diagnosedatei teilen", subtitle: isPreparingExport ? "Wird vorbereitet …" : "Nicht verfügbar",
                                symbol: "square.and.arrow.up.fill", tint: Theme.glacier)
                        .foregroundStyle(Theme.textTertiary)
                }
                Toggle(isOn: $watchdogOn) {
                    SetRowLabel(title: "Hänger erkennen", subtitle: "Prüft alle 0,5 Sekunden, ob die App reagiert",
                                symbol: "waveform.path.ecg", tint: Theme.dawn)
                }
                .onChange(of: watchdogOn) { _, enabled in
                    DiagnosticsService.shared.setWatchdogEnabled(enabled)
                }
                Button(role: .destructive) {
                    isConfirmingClear = true
                } label: {
                    Label {
                        Text("Diagnosedaten löschen")
                    } icon: {
                        SetIconTile(symbol: "trash.fill", tint: Theme.negative)
                    }
                }
                .confirmationDialog("Diagnosedaten löschen?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                    Button("Löschen", role: .destructive) { Task { await clear() } }
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Absturz- und Hängerberichte, Sitzungen und der Verlauf werden von diesem iPhone gelöscht. Deine Fahrten bleiben unberührt.")
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Teilen")
        } footer: {
            SetFooter(text: "Alles bleibt auf deinem iPhone – nichts wird automatisch gesendet. Die Datei enthält Abstürze, Hänger, die zuletzt geöffneten Bildschirme, Gerätemodell und iOS-Version und nur die Anzahl deiner Fahrten – keine Strecken, Namen oder Kontodaten. Berichte von iOS kommen nur, wenn „Mit App-Entwickler:innen teilen“ aktiv ist (Einstellungen › Datenschutz & Sicherheit › Analyse & Verbesserungen), meist beim nächsten Start.")
        }
    }

    // MARK: Actions

    private func reload() async {
        let loaded = await DiagnosticsService.shared.overview()
        withMotion(Motion.smooth) { overview = loaded }
        isPreparingExport = true
        let counts = dataCounts()
        let exportContext = DiagnosticsExport.context(app: app, trips: counts.trips, tickets: counts.tickets, favorites: counts.favorites)
        exportURL = try? await DiagnosticsService.shared.writeExport(context: exportContext)
        isPreparingExport = false
    }

    private func clear() async {
        await DiagnosticsService.shared.clearAll()
        app.showToast("trash.fill", "Diagnosedaten gelöscht")   // the toast plays the deletion's one haptic
        await reload()
    }

    /// Counts only (no content) – how much data the screens have to handle.
    private func dataCounts() -> (trips: Int, tickets: Int, favorites: Int) {
        let trips = (try? context.fetchCount(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil }))) ?? 0
        let tickets = (try? context.fetchCount(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.deletedAt == nil }))) ?? 0
        let favorites = (try? context.fetchCount(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.deletedAt == nil }))) ?? 0
        return (trips, tickets, favorites)
    }

    // MARK: Formatting

    /// "420 ms", "1,4 s".
    static func duration(_ ms: Double) -> String {
        ms < 1000 ? "\(Format.number(ms)) ms" : "\(Format.number(ms / 1000, decimals: 1)) s"
    }
}

/// All entries of the last 30 days (newest first).
private struct SetDiagnosticsEventsPage: View {
    let events: [DiagnosticsEvent]

    var body: some View {
        List {
            Section {
                ForEach(events) { event in
                    SetDiagnosticsPage.eventRowLabel(event)
                }
                .listRowBackground(Theme.surface)
            } footer: {
                SetFooter(text: "Einträge der letzten 30 Tage. Ältere werden automatisch gelöscht.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop(skyOpacity: 0.4, fadeEnd: 0.4) }
        .navigationTitle("Alle Einträge")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Icon tile per incident kind.
private struct SetDiagnosticsStyle {
    var symbol: String
    var tint: Color

    init(kind: DiagnosticsEvent.Kind) {
        switch kind {
        case .crash: (symbol, tint) = ("exclamationmark.octagon.fill", Theme.negative)
        case .hang, .watchdogHang: (symbol, tint) = ("hourglass", Theme.dawn)
        case .fatalHang: (symbol, tint) = ("hourglass.bottomhalf.filled", Theme.negative)
        case .abnormalExit: (symbol, tint) = ("bolt.horizontal.circle.fill", Theme.dusk)
        case .cpuException: (symbol, tint) = ("cpu.fill", Theme.gold)
        case .diskWriteException: (symbol, tint) = ("internaldrive.fill", Theme.gold)
        case .slowLaunch: (symbol, tint) = ("tortoise.fill", Theme.glacier)
        }
    }
}
