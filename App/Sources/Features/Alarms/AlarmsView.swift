import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import KlimaCore

// Alarme einsehen (docs/ROUTES_ALARMS.md §2): one screen for everything that can notify the user – live follow, departure
// and route reminders, ticket and objection deadlines, the weekly summary – with on/off, the time, edit and delete. The
// permission and consent states are shown as they are; nothing is switched on here by itself.

struct AlarmsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var routes: [FavoriteRouteEntity]
    @State private var model: AlarmsModel
    @State private var editingRoute: FavoriteRouteEntity?
    @State private var pendingDelete: AlarmItem?

    init(demo: AlarmsDemoScene? = nil) {
        _model = State(initialValue: AlarmsModel(demo: demo))
    }

    var body: some View {
        List {
            statusSection
            let active = model.items.filter(\.isOn)
            let paused = model.items.filter { !$0.isOn }
            if !active.isEmpty {
                Section("Aktiv") {
                    ForEach(active) { item in row(item) }
                }
            }
            if !paused.isEmpty {
                Section {
                    ForEach(paused) { item in row(item) }
                } header: {
                    Text("Ausgeschaltet")
                } footer: {
                    Text("Ausgeschaltete Alarme sind nicht vergessen. Schalte sie wieder ein, solange ihr Termin noch kommt.")
                }
            }
            if model.isLoaded && model.items.isEmpty {
                Section {
                    EmptyStateView(symbol: "bell.slash", title: "Keine Alarme",
                                   message: "Erinnerungen stellst du bei Routen mit Zeitplan, bei Tickets und bei Abfahrten. Sie erscheinen dann hier.")
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                Label {
                    Text("Störungen kannst du nicht abonnieren. Sie stehen im Planer unter „Störungen“.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Theme.summitText)
                }
                .listRowBackground(Theme.surface)
            } header: {
                Text("Störungen")
            }
            Section {
                NavigationLink {
                    AlarmHistoryView(model: model)
                } label: {
                    Label {
                        Text("Verlauf")
                        Text("Die letzten \(model.history.count) von 30 Mitteilungen")
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.dusk)
                    }
                }
                .listRowBackground(Theme.surface)
            } footer: {
                Text("Der Verlauf liegt nur auf diesem Gerät.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.sheetBackground)
        .navigationTitle("Alarme")
        .task { await reload() }
        .refreshable { await reload() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await reload() }
        }
        .sheet(item: $editingRoute) { route in
            NavigationStack { SavedRouteEditView(route: route) }
        }
        .confirmationDialog("Alarm löschen?", isPresented: Binding(get: { pendingDelete != nil },
                                                                   set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { item in
            Button("Löschen", role: .destructive) {
                let repository = Repository(context: context, app: app)
                Task { await model.remove(item, app: app, routes: routes, repository: repository) }
            }
        } message: { item in
            Text(deleteMessage(for: item))
        }
    }

    // MARK: Rows

    private func row(_ item: AlarmItem) -> some View {
        AlarmRow(item: item) { on in
            Task { await model.setOn(item, on, app: app, routes: routes) }
        }
        .listRowBackground(Theme.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = item
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            if canEdit(item) {
                Button {
                    edit(item)
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }
                .tint(Theme.glacier)
            }
        }
    }

    private func canEdit(_ item: AlarmItem) -> Bool {
        switch item.kind {
        case .routeReminder, .ticketRenewal, .objectionLetter, .passengerRights: true
        default: false
        }
    }

    /// Route reminders edit the route; ticket and objection deadlines are changed on the ticket.
    private func edit(_ item: AlarmItem) {
        switch item.kind {
        case .routeReminder:
            let routeID = String(item.id.dropFirst(AlarmIdentifier.routePrefix.count))
            editingRoute = routes.first { $0.id.uuidString == routeID }
        case .ticketRenewal, .objectionLetter, .passengerRights:
            app.isShowingSettings = false
            app.selectedTab = .ticket
        default:
            break
        }
    }

    private func deleteMessage(for item: AlarmItem) -> String {
        switch item.kind {
        case .routeReminder: "Die Erinnerungen dieser Route und ihr Zeitplan werden entfernt. Die Route bleibt erhalten."
        case .liveFollow: "Die Live-Verfolgung endet."
        case .weeklySummary: "Der Wochenrückblick ist danach aus."
        default: "Diese Erinnerung wird entfernt."
        }
    }

    private func reload() async {
        await model.reload(app: app, routes: routes)
    }

    // MARK: Status

    private var statusSection: some View {
        let lines = statusLines
        return Group {
            if !lines.isEmpty {
                Section {
                    ForEach(lines) { line in
                        Label {
                            Text(line.text)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                        } icon: {
                            Image(systemName: line.symbol)
                                .foregroundStyle(line.tint)
                        }
                        .listRowBackground(Theme.surface)
                        if let action = line.action {
                            Button(action.title) { action.run() }
                                .listRowBackground(Theme.surface)
                        }
                    }
                } header: {
                    Text("Stand")
                } footer: {
                    Text("Live-Mitteilungen kommen sofort und stehen deshalb nicht in dieser Liste. Du findest sie in der Mitteilungs-Zentrale.")
                }
            }
        }
    }

    private struct StatusLine: Identifiable {
        let id: String
        let symbol: String
        let tint: Color
        let text: String
        var action: (title: String, run: () -> Void)?
    }

    /// Permission, consent and the notification budget, each only when it matters.
    private var statusLines: [StatusLine] {
        var lines: [StatusLine] = []
        switch model.authorization {
        case .denied:
            lines.append(StatusLine(id: "denied", symbol: "bell.slash.fill", tint: Theme.summitText,
                                    text: "Mitteilungen sind in iOS ausgeschaltet. Dann kommt kein Alarm an.",
                                    action: ("Einstellungen öffnen", {
                                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                    })))
        case .notDetermined:
            lines.append(StatusLine(id: "undetermined", symbol: "questionmark.circle", tint: Theme.textSecondary,
                                    text: "iOS hat noch nicht gefragt. Sobald du einen Alarm einschaltest, fragt es nach der Erlaubnis.",
                                    action: nil))
        default:
            break
        }
        if app.live.consent != .granted {
            lines.append(StatusLine(id: "consent", symbol: "antenna.radiowaves.left.and.right.slash", tint: Theme.textSecondary,
                                    text: "Live-Daten sind nicht freigegeben. Live-Verfolgung und Live-Abfahrten bleiben aus.",
                                    action: nil))
        }
        if !FollowNoticeStore.load().isEnabled {
            lines.append(StatusLine(id: "follow", symbol: "dot.radiowaves.left.and.right", tint: Theme.textSecondary,
                                    text: "Live-Mitteilungen sind aus. Du schaltest sie unter Einstellungen › Mitteilungen ein.",
                                    action: nil))
        }
        switch PendingNoticeBudget.level(pending: model.pendingCount) {
        case .ok:
            break
        case .nearLimit:
            lines.append(StatusLine(id: "budget", symbol: "tray.full", tint: Theme.summitText,
                                    text: "iOS nimmt nur begrenzt viele ausstehende Mitteilungen an (nach unserem Stand 64). Du hast \(model.pendingCount) belegt.",
                                    action: nil))
        case .full:
            lines.append(StatusLine(id: "full", symbol: "tray.full.fill", tint: Theme.alpenglow,
                                    text: "Alle Plätze für ausstehende Mitteilungen sind belegt. Neue Erinnerungen werden nicht gesetzt.",
                                    action: nil))
        }
        return lines
    }
}

/// One alarm: its kind, what it is about, the time and the switch.
struct AlarmRow: View {
    let item: AlarmItem
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: item.kind.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.isOn ? item.kind.tint : Theme.textTertiary)
                .frame(width: 36, height: 36)
                .background(item.kind.tint.opacity(item.isOn ? 0.16 : 0.07), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(item.isOn ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(2)
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                Text(timeText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(item.isOn ? Theme.accentText : Theme.textTertiary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            Toggle(item.title, isOn: Binding(get: { item.isOn }, set: onToggle))
                .labelsHidden()
                .disabled(!item.isOn && !item.canResume)
        }
        .padding(.vertical, 2)
    }

    /// "Mo–Fr · 07:20 · nächste Heute 07:20", "Heute 14:10", "abgelaufen" or "kein Termin".
    private var timeText: String {
        if let schedule = item.scheduleText {
            guard let next = item.nextDate else { return schedule }
            return "\(schedule) · nächste \(Format.relativeDay(next)) \(Format.time(next))"
        }
        if let next = item.nextDate {
            return "\(Format.relativeDay(next)) \(Format.time(next))"
        }
        return item.canResume ? "kein Termin" : "abgelaufen"
    }
}

extension AlarmKind {
    var symbol: String {
        switch self {
        case .liveFollow: "dot.radiowaves.left.and.right"
        case .departure: "bell.fill"
        case .routeReminder: "bookmark.fill"
        case .ticketRenewal: "ticket.fill"
        case .objectionLetter: "envelope.badge.fill"
        case .passengerRights: "banknote.fill"
        case .weeklySummary: "calendar.badge.clock"
        case .other: "bell"
        }
    }

    var tint: Color {
        switch self {
        case .liveFollow, .departure: Theme.glacier
        case .routeReminder, .weeklySummary: Theme.dusk
        case .ticketRenewal: Theme.gold
        case .objectionLetter: Theme.dawn
        case .passengerRights: Theme.pine
        case .other: Theme.textSecondary
        }
    }
}
