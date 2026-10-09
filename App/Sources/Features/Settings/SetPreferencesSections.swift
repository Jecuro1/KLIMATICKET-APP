import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import KlimaCore

// MARK: - Fahrten bewerten

/// Defaults used to value new trips: discount card, class, home station, fare explanation, favourites.
struct SetFareSection: View {
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }) private var favorites: [FavoriteRouteEntity]

    var body: some View {
        @Bindable var settings = app.settings
        Section {
            Group {
                Picker(selection: $settings.defaultDiscount) {
                    ForEach(FareDiscount.allCases) { discount in
                        Text(SetFareSection.title(for: discount)).tag(discount)
                    }
                } label: {
                    SetRowLabel(title: "Ermäßigung", symbol: "percent", tint: Theme.dusk)
                }
                Picker(selection: $settings.defaultTravelClass) {
                    ForEach(TravelClass.allCases) { travelClass in
                        Text(travelClass.displayName).tag(travelClass)
                    }
                } label: {
                    SetRowLabel(title: "Klasse", symbol: "sofa.fill", tint: Theme.modeColor(.train))
                }
                homeStationRow
                NavigationLink {
                    SetInfoPage(title: "Preisschätzung", kicker: "So rechnet KlimaBilanz", symbol: "eurosign.circle.fill",
                                tint: Theme.glacier, text: Copy.fareExplanation,
                                notesTitle: "Tarifstand · Version \(app.catalog.version)", notes: app.catalog.notes)
                } label: {
                    SetRowLabel(title: "Wie wird der Preis geschätzt?", symbol: "eurosign.circle.fill", tint: Theme.glacier)
                }
                NavigationLink {
                    FavoritesManagerView()
                } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        SetRowLabel(title: "Favoriten verwalten", symbol: "star.fill", tint: Theme.gold)
                        Spacer(minLength: Theme.Spacing.xs)
                        if !favorites.isEmpty {
                            Text(Format.number(Double(favorites.count)))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Fahrten bewerten")
        } footer: {
            SetFooter(text: "Gilt für neue Fahrten. Beim Erfassen kannst du jeden Preis antippen und anpassen.")
        }
    }

    private var homeStationRow: some View {
        NavigationLink {
            StationPickerView(title: "Heimatbahnhof") { station in
                app.settings.homeStationID = station.id
            }
        } label: {
            SetRowLabel(title: "Heimatbahnhof", subtitle: homeStationSubtitle, symbol: "house.fill", tint: Theme.pine)
        }
        .swipeActions(edge: .trailing) {
            if app.settings.homeStationID != nil {
                Button("Entfernen", role: .destructive) {
                    app.settings.homeStationID = nil
                }
            }
        }
    }

    private var homeStationSubtitle: String {
        guard let id = app.settings.homeStationID, let station = app.stations.station(id: id) else {
            return "Startpunkt für neue Fahrten festlegen"
        }
        if let state = station.federalState?.displayName { return "\(station.name) · \(state)" }
        return station.name
    }

    static func title(for discount: FareDiscount) -> String {
        switch discount {
        case .none: "Ohne"
        case .vorteilscard: "Vorteilscard"
        }
    }
}

// MARK: - Automatische Fahrterkennung

struct SetDetectionSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var detection = app.detection
        Section {
            Group {
                Toggle(isOn: $detection.isEnabled) {
                    SetRowLabel(title: "Fahrten automatisch erkennen",
                                subtitle: detection.isAvailable ? "Vorschläge an deinen Lieblingsbahnhöfen" : "Auf diesem Gerät nicht verfügbar",
                                symbol: "location.fill", tint: Theme.pine)
                }
                .disabled(!detection.isAvailable)
                .onChange(of: detection.isEnabled) { _, enabled in
                    if enabled { Repository(context: context, app: app).configureTripDetection() }
                }
                if detection.isEnabled {
                    if detection.isAuthorizedAlways {
                        activeRow
                    } else {
                        permissionRow
                    }
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Automatische Fahrterkennung")
        } footer: {
            SetFooter(text: "KlimaBilanz bemerkt per Geofencing, wenn du an deinen häufigsten Bahnhöfen abfährst und ankommst, und schlägt dir die Fahrt zum Erfassen vor – akkuschonend, ohne Dauer-GPS. Dein Standort verlässt dein iPhone nie.")
        }
    }

    private var activeRow: some View {
        let count = app.detection.suggestions.count
        return SetRowLabel(title: "Aktiv",
                           subtitle: count == 0 ? "Bis zu 20 Bahnhöfe werden beobachtet"
                                                : "\(SetFormat.count(count, "Vorschlag wartet", "Vorschläge warten")) in der Übersicht",
                           symbol: "checkmark.circle.fill", tint: Theme.pine)
    }

    private var permissionRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SetRowLabel(title: "Standort „Immer“ fehlt",
                        subtitle: "Erlaube den Standortzugriff „Immer“, damit Fahrten auch im Hintergrund erkannt werden.",
                        symbol: "location.slash.fill", tint: Theme.dawn)
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
}

// MARK: - Darstellung

struct SetAppearanceSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Section {
            Group {
                SetAppearancePicker(selection: $settings.appearance, hapticsEnabled: settings.hapticsEnabled)
                    .padding(.vertical, Theme.Spacing.xs)
                Toggle(isOn: $settings.hapticsEnabled) {
                    SetRowLabel(title: "Haptisches Feedback", subtitle: "Spürbare Bestätigung beim Erfassen",
                                symbol: "iphone.radiowaves.left.and.right", tint: Theme.alpenglow)
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Darstellung")
        }
    }
}

/// Three mini phone previews (System / Hell / Dunkel) like the iOS display settings.
private struct SetAppearancePicker: View {
    @Binding var selection: AppSettings.Appearance
    var hapticsEnabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            ForEach(AppSettings.Appearance.allCases) { option in
                tile(option)
            }
        }
        .settingsHaptic(.selection, trigger: selection, enabled: hapticsEnabled)
    }

    private func tile(_ option: AppSettings.Appearance) -> some View {
        let isSelected = selection == option
        return Button {
            withAnimation(.snappy) { selection = option }
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                SetAppearancePreview(option: option)
                    .frame(maxWidth: 78)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.modeTile, style: .continuous)
                            .strokeBorder(isSelected ? Theme.accent : Theme.separator, lineWidth: isSelected ? 2.5 : 1)
                    }
                    .shadow(color: Color.black.opacity(isSelected ? 0.14 : 0.05), radius: 8, y: 4)
                    .scaleEffect(isSelected ? 1 : 0.96)
                Text(option.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        @Bindable var settings = app.settings
        Section {
            Group {
                if status == .denied {
                    deniedRow
                }
                Toggle(isOn: $settings.renewalRemindersEnabled) {
                    SetRowLabel(title: "Verlängerungs-Erinnerung", subtitle: renewalSubtitle,
                                symbol: "bell.badge.fill", tint: Theme.dawn)
                }
                .onChange(of: settings.renewalRemindersEnabled) { _, enabled in
                    updateRenewalReminders(enabled)
                }
                .task {
                    status = await app.notifications.authorizationStatus()
                }
                Toggle(isOn: $settings.weeklySummaryEnabled) {
                    SetRowLabel(title: "Wochenrückblick", subtitle: "Sonntags um 18 Uhr",
                                symbol: "calendar.badge.clock", tint: Theme.dusk)
                }
                .onChange(of: settings.weeklySummaryEnabled) { _, enabled in
                    updateWeeklySummary(enabled)
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Mitteilungen")
        } footer: {
            SetFooter(text: "Die Tage vor Ablauf stellst du je Ticket im Ticket-Tab ein.")
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
