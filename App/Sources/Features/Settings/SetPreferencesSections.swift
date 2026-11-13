import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import KlimaCore

// MARK: - Fahrten erfassen

/// How trips get into the app: home station (pre-filled start), favourites (one-tap capture), recording a ride and the opt-in
/// background detection (docs/TRIP_DETECTION.md, `TripDetectEntryRow`).
struct SetCaptureSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }) private var favorites: [FavoriteRouteEntity]

    var body: some View {
        Section {
            Group {
                homeStationRow
                favoritesRow
                // MARK: tripdetect – Fahrt aufzeichnen and the opt-in Hintergrund-Erkennung (Beta) live on their own page.
                TripDetectEntryRow()
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Fahrten erfassen")
        } footer: {
            SetFooter(text: "Fahrten aufzeichnen oder – optional, als Beta – im Hintergrund erkennen lassen. Vorschläge werden nie ohne dein Okay erfasst, der Standort bleibt auf deinem iPhone.")
        }
    }

    private var favoritesRow: some View {
        NavigationLink {
            FavoritesManagerView()
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Favoriten verwalten", subtitle: "Strecken mit einem Tipp erfassen",
                            symbol: "star.fill", tint: Theme.gold)
                Spacer(minLength: Theme.Spacing.xs)
                if !favorites.isEmpty {
                    Text(Format.number(Double(favorites.count)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .numericValue(Double(favorites.count))
                }
            }
        }
    }

    private var homeStationRow: some View {
        NavigationLink {
            StationPickerView(title: "Heimatbahnhof") { station in
                app.settings.homeStationID = station.id
            }
        } label: {
            SetRowLabel(title: "Heimatbahnhof", subtitle: homeStationSubtitle, symbol: "house.fill", tint: Theme.pine)
                .setSymbolEffect(.bounce, trigger: app.settings.homeStationID)
                .motionAnimation(Motion.snappy, value: app.settings.homeStationID)
        }
        // Removing is a swipe – and, for whoever does not know the gesture, the same action on a long press.
        .swipeActions(edge: .trailing) {
            if app.settings.homeStationID != nil {
                Button("Entfernen", role: .destructive, action: removeHomeStation)
            }
        }
        .contextMenu {
            if app.settings.homeStationID != nil {
                Button("Heimatbahnhof entfernen", systemImage: "house.slash", role: .destructive, action: removeHomeStation)
            }
        }
        .haptic(.warning, trigger: app.settings.homeStationID, when: { old, new in old != nil && new == nil })
    }

    private func removeHomeStation() {
        withMotion(Motion.snappy) { app.settings.homeStationID = nil }
    }

    private var homeStationSubtitle: String {
        guard let id = app.settings.homeStationID, let station = app.stations.station(id: id) else {
            return "Startpunkt für neue Fahrten festlegen"
        }
        if let state = station.federalState?.displayName { return "\(station.name) · \(state)" }
        return station.name
    }
}

// MARK: - Darstellung

struct SetAppearanceSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Section {
            Group {
                SetAppearancePicker(selection: $settings.appearance)
                    .padding(.vertical, Theme.Spacing.xs)
                    .id(SetScrollAnchor.appearance)
                // MARK: themes – Look & Feel: Farbe, Bewegung, Haptik (it replaces the switch „Haptisches Feedback“), Zahlen
                AppearanceSettingsRow()
                // MARK: icons – Einstellungen › Darstellung › App-Symbol
                if AppIconStore.shared.isSupported {
                    AppIconSettingsRow()
                }
                SetOfficialLogosToggle() // MARK: stops
                NavigationLink {
                    WidgetGalleryView()
                } label: {
                    SetRowLabel(title: "Widgets & Kurzbefehle", subtitle: "Home- und Sperrbildschirm, Kontrollzentrum, Siri",
                                symbol: "square.grid.2x2.fill", tint: Theme.glacier)
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Darstellung")
        }
    }
}

// MARK: stops – „Offizielle Logos & Wappen“ (LOGO_SPEC §3.3): off = own Wegzeichen and no download.
private struct SetOfficialLogosToggle: View {
    var body: some View {
        @Bindable var logos = LogoPackStore.shared
        Toggle(isOn: $logos.userEnabled) {
            SetRowLabel(title: "Offizielle Logos & Wappen", subtitle: "Skigebiets-Logos und Landeswappen bei Haltestellen",
                        symbol: "mountain.2.fill", tint: Theme.dusk)
        }
        .haptic(.selection, trigger: logos.userEnabled)
    }
}

/// Three mini phone previews (System / Hell / Dunkel) like the iOS display settings. The selection ring glides from
/// one preview to the next (matched geometry), the picked phone settles forward and its check morphs in.
private struct SetAppearancePicker: View {
    @Binding var selection: AppSettings.Appearance
    @Namespace private var namespace

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            ForEach(AppSettings.Appearance.allCases) { option in
                tile(option)
            }
        }
        .haptic(.selection, trigger: selection)
    }

    private func tile(_ option: AppSettings.Appearance) -> some View {
        let isSelected = selection == option
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.modeTile, style: .continuous)
        return Button {
            guard option != selection else { return }
            withMotion(Motion.snappy) { selection = option }
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                SetAppearancePreview(option: option)
                    .frame(maxWidth: 78)
                    .overlay { shape.strokeBorder(Theme.separator, lineWidth: 1) }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Theme.Radius.modeTile + 3, style: .continuous)
                                .strokeBorder(Theme.accent, lineWidth: 2.5)
                                .padding(-3)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .shadow(color: Color.black.opacity(isSelected ? 0.14 : 0.05), radius: 8, y: 4)
                    .scaleEffect(isSelected ? 1 : 0.94)
                Text(option.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .symbolReplaceTransition()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Erscheinungsbild \(option.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SetAppearancePreview: View {
    var option: AppSettings.Appearance

    var body: some View {
        ZStack {
            switch option {
            case .light:
                SetMiniScreen().environment(\.colorScheme, .light)
            case .dark:
                SetMiniScreen().environment(\.colorScheme, .dark)
            case .system:
                SetMiniScreen().environment(\.colorScheme, .light)
                SetMiniScreen().environment(\.colorScheme, .dark)
                    .mask { SetDiagonalHalf() }
            }
        }
        .aspectRatio(0.76, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.modeTile, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Tiny rendition of the dashboard: sky, ridge, "73 %" and a frosted card with the route bar.
private struct SetMiniScreen: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.background
            LinearGradient(colors: [Theme.glacier.opacity(0.42), Theme.dusk.opacity(0.18), Theme.dawn.opacity(0.14), Theme.dawn.opacity(0)],
                           startPoint: .top, endPoint: .center)
            RidgeShape(peakX: 0.66, peakY: 0.46, seed: 7, roughness: 0.9)
                .fill(LinearGradient(colors: [Theme.glacier2.opacity(0.42), Theme.glacier2.opacity(0.06)],
                                     startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(Theme.textTertiary).frame(width: 16, height: 2.5)
                Capsule().fill(Theme.textPrimary).frame(width: 26, height: 4)
                Text("73")
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.surface)
                    .frame(height: 16)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.routeGradient)
                            .frame(width: 24, height: 3)
                            .padding(.leading, 5)
                    }
            }
            .padding(7)
        }
    }
}

private struct SetDiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Mitteilungen

struct SetNotificationsSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        @Bindable var settings = app.settings
        Section {
            Group {
                // MARK: routes – every alarm in one list: on/off, time, edit, history (docs/ROUTES_ALARMS.md §2)
                NavigationLink {
                    AlarmsView()
                } label: {
                    SetRowLabel(title: "Alle Alarme", subtitle: "Erinnerungen, Live-Verfolgung, Verlauf",
                                symbol: "bell.badge.fill", tint: Theme.gold)
                }
                .listRowBackground(Theme.surface)
                if status == .denied {
                    deniedRow
                        .motionTransition(.rise)
                }
                // On: the bell rings once. Off: it morphs into the struck-through bell.
                Toggle(isOn: $settings.renewalRemindersEnabled.animation(MotionPolicy.animation(Motion.snappy))) {
                    SetRowLabel(title: "Verlängerungs-Erinnerung", subtitle: renewalSubtitle,
                                symbol: settings.renewalRemindersEnabled ? "bell.badge.fill" : "bell.slash.fill", tint: Theme.dawn)
                        .setSymbolOnEnable(settings.renewalRemindersEnabled, .wiggle)
                }
                .haptic(.selection, trigger: settings.renewalRemindersEnabled)
                .onChange(of: settings.renewalRemindersEnabled) { _, enabled in
                    updateRenewalReminders(enabled)
                }
                .task {
                    await refreshStatus()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Back from the iOS Settings app ("Einstellungen öffnen") – the permission may have changed.
                    guard phase == .active else { return }
                    Task { await refreshStatus() }
                }
                Toggle(isOn: $settings.weeklySummaryEnabled) {
                    SetRowLabel(title: "Wochenrückblick", subtitle: "Sonntags um 18 Uhr",
                                symbol: "calendar.badge.clock", tint: Theme.dusk)
                        .setSymbolOnEnable(settings.weeklySummaryEnabled)
                }
                .haptic(.selection, trigger: settings.weeklySummaryEnabled)
                .onChange(of: settings.weeklySummaryEnabled) { _, enabled in
                    updateWeeklySummary(enabled)
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Mitteilungen")
        } footer: {
            SetFooter(text: "Wie viele Tage vorher du erinnert wirst, stellst du je Ticket im Tab „Ticket“ ein.")
        }
    }

    private var renewalSubtitle: String {
        let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID)
        return ticket.flatMap { SetFormat.reminderOffsets($0.reminderOffsets) } ?? "Bevor dein Ticket abläuft"
    }

    private var deniedRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SetRowLabel(title: "Mitteilungen sind aus",
                        subtitle: "Erlaube Mitteilungen in den iOS-Einstellungen, damit Erinnerungen ankommen.",
                        symbol: "bell.slash.fill", tint: Theme.negative)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Einstellungen öffnen", systemImage: "gear")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func refreshStatus() async {
        let previous = status
        let current = await app.notifications.authorizationStatus()
        // The "Mitteilungen sind aus" row folds in / out (back from the iOS Settings app); the first read just shows it.
        if previous == nil {
            status = current
        } else if previous != current {
            withMotion(Motion.smooth) { status = current }
        }
        // Allowed again in the iOS Settings app: schedule what was skipped while notifications were off.
        guard previous == .denied, current == .authorized || current == .provisional else { return }
        if app.settings.renewalRemindersEnabled { updateRenewalReminders(true) }
        if app.settings.weeklySummaryEnabled { await app.notifications.setWeeklySummary(enabled: true) }
    }

    private func updateRenewalReminders(_ enabled: Bool) {
        let liveTickets = tickets
        Task {
            if enabled {
                await app.notifications.requestAuthorization()
                status = await app.notifications.authorizationStatus()
                let repository = Repository(context: context, app: app)
                for ticket in liveTickets where !ticket.isExpired {
                    repository.scheduleReminders(for: ticket)
                }
            } else {
                for ticket in liveTickets {
                    await app.notifications.cancelRenewalReminders(ticketID: ticket.id)
                }
            }
        }
    }

    private func updateWeeklySummary(_ enabled: Bool) {
        Task {
            if enabled {
                await app.notifications.requestAuthorization()
                status = await app.notifications.authorizationStatus()
            }
            await app.notifications.setWeeklySummary(enabled: enabled)
        }
    }
}
