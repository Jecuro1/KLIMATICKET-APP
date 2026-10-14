import SwiftUI
import UIKit
import UserNotifications
import ActivityKit
import KlimaCore

// Einstellungen › Live-Mitteilungen (docs/OEBB_LIVE.md §R8). Off until the user switches it on. Switching it on is the only
// moment the notification permission is asked for; with the switch off nothing is requested, sent or started for "Live
// verfolgen". Inserted after `SetLiveDataSection`.
struct SetFollowNoticesSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization: UNAuthorizationStatus?
    @State private var activitiesAllowed = false
    @State private var backgroundAllowed = false

    var body: some View {
        let settings = app.settings.followNotices
        Section {
            Group {
                Toggle(isOn: Binding(get: { app.settings.followNotices.isEnabled }, set: { setEnabled($0) })) {
                    SetRowLabel(title: "Live-Mitteilungen", subtitle: "Bei „Live verfolgen“ über Verspätung, Gleis, Umstieg und Ankunft informieren",
                                symbol: "bell.and.waves.left.and.right.fill", tint: Theme.glacier)
                }
                // Without the live-data consent the switch cannot go on: no permission is asked before the consent exists.
                .disabled(!settings.isEnabled && app.live.consent != .granted)

                if settings.isEnabled {
                    statusRow(title: "Mitteilungen", value: notificationStatus.text, ok: notificationStatus.ok)
                    statusRow(title: "Live-Aktivitäten", value: activitiesAllowed ? "erlaubt" : "in iOS aus", ok: activitiesAllowed)
                    statusRow(title: "Hintergrund-Aktualisierung", value: backgroundAllowed ? "an" : "in iOS aus", ok: backgroundAllowed)

                    Picker(selection: Binding(get: { app.settings.followNotices.delayThresholdMinutes },
                                              set: { value in update { $0.delayThresholdMinutes = value } })) {
                        ForEach(FollowNoticeSettings.delayChoices, id: \.self) { Text("\($0) Min").tag($0) }
                    } label: {
                        SetRowLabel(title: "Verspätung ab", subtitle: "Ab dieser Verspätung meldet sich KlimaBilanz",
                                    symbol: "clock.badge.exclamationmark.fill", tint: Theme.dawn)
                    }

                    ForEach(FollowNoticeKind.allCases, id: \.self) { kind in
                        Toggle(isOn: Binding(get: { app.settings.followNotices.kinds.contains(kind) },
                                             set: { on in
                                                 update { settings in
                                                     if on { settings.kinds.insert(kind) } else { settings.kinds.remove(kind) }
                                                 }
                                             })) {
                            SetRowLabel(title: kind.settingsTitle, subtitle: kind.settingsSubtitle, symbol: kind.settingsSymbol, tint: kind.settingsTint)
                        }
                        .padding(.leading, Theme.Spacing.m)
                    }

                    Toggle(isOn: Binding(get: { app.settings.followNotices.quietHours.isEnabled },
                                         set: { on in update { $0.quietHours.isEnabled = on } })) {
                        SetRowLabel(title: "Ruhezeit", subtitle: quietSubtitle(settings.quietHours),
                                    symbol: "moon.zzz.fill", tint: Theme.dusk)
                    }
                    if settings.quietHours.isEnabled {
                        Picker("Ruhezeit ab", selection: Binding(get: { app.settings.followNotices.quietHours.startHour },
                                                                set: { h in update { $0.quietHours.startHour = h } })) {
                            ForEach(0..<24, id: \.self) { Text(Self.hourText($0)).tag($0) }
                        }
                        .padding(.leading, Theme.Spacing.m)
                        Picker("Ruhezeit bis", selection: Binding(get: { app.settings.followNotices.quietHours.endHour },
                                                                 set: { h in update { $0.quietHours.endHour = h } })) {
                            ForEach(0..<24, id: \.self) { Text(Self.hourText($0)).tag($0) }
                        }
                        .padding(.leading, Theme.Spacing.m)
                    }

                    if notificationStatus.denied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            SetRowLabel(title: "Mitteilungen in iOS erlauben", subtitle: "Öffnet die Einstellungen von KlimaBilanz",
                                        symbol: "gearshape.fill", tint: Theme.glacier)
                        }
                    }
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Live-Mitteilungen")
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SetFooter(text: "Mitteilungen und Live-Aktivitäten brauchen deine Erlaubnis in iOS und diesen Schalter hier. Ohne Schalter fragt KlimaBilanz nie nach der Erlaubnis und sendet nichts. Live-Daten brauchen außerdem deine Zustimmung oben unter „Live-Daten“.")
                SetFooter(text: "iOS entscheidet, wann KlimaBilanz im Hintergrund nachsieht. Mitteilungen können deshalb verspätet kommen oder ausbleiben. Es gibt keine Zusage für eine bestimmte Minute.")
            }
        }
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            // Back from the iOS Settings app: the permission may have changed.
            if phase == .active { Task { await refreshStatus() } }
        }
    }

    // MARK: Actions

    private func setEnabled(_ on: Bool) {
        update { $0.isEnabled = on }
        // The permission is asked only when live data is granted too (§2: nothing is asked or sent before the consent).
        if on, app.live.consent == .granted, !LaunchMode.isSandboxed { LiveFollowNotifications.requestAuthorization() }
        Task { await refreshStatus() }
    }

    /// Writes one change of the switches; the store saves it.
    private func update(_ change: (inout FollowNoticeSettings) -> Void) {
        var next = app.settings.followNotices
        change(&next)
        app.settings.followNotices = next
    }

    private func refreshStatus() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        activitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
        backgroundAllowed = FollowBackgroundRefresh.isBackgroundRefreshAvailable
    }

    // MARK: Text

    private struct NotificationStatus {
        var text: String
        var ok: Bool
        var denied: Bool
    }

    private var notificationStatus: NotificationStatus {
        switch authorization {
        case .authorized, .provisional, .ephemeral:
            NotificationStatus(text: "erlaubt", ok: true, denied: false)
        case .denied:
            NotificationStatus(text: "in iOS aus", ok: false, denied: true)
        case .notDetermined, nil:
            NotificationStatus(text: "noch nicht gefragt", ok: false, denied: false)
        @unknown default:
            NotificationStatus(text: "unbekannt", ok: false, denied: false)
        }
    }

    private func statusRow(title: String, value: String, ok: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Text(value).font(.footnote).foregroundStyle(ok ? Theme.positiveText : Theme.summitText)
        }
        .accessibilityElement(children: .combine)
    }

    private func quietSubtitle(_ quiet: QuietHours) -> String {
        quiet.isEnabled
            ? "Keine Mitteilungen von \(Self.hourText(quiet.startHour)) bis \(Self.hourText(quiet.endHour))"
            : "Aus: auch nachts kommen Mitteilungen"
    }

    private static func hourText(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}

// MARK: Labels of the notice kinds (German, Du-Form)

private extension FollowNoticeKind {
    var settingsTitle: String {
        switch self {
        case .delay: "Verspätung"
        case .platform: "Gleisänderung"
        case .cancelled: "Zug fällt aus"
        case .tightTransfer: "Knapper Umstieg"
        case .arrivingSoon: "Ankunft in Kürze"
        case .departed: "Abfahrt"
        case .arrived: "Ankunft"
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .delay: "Auch wenn sich eine Verspätung wieder verkleinert"
        case .platform: "Am Einstiegs- und Ausstiegsbahnhof"
        case .cancelled: "Sofort, wenn HAFAS die Fahrt streicht"
        case .tightTransfer: "Wenn du weniger als 5 Minuten zum Umsteigen hast"
        case .arrivingSoon: "Etwa 10 Minuten vor dem Ausstieg"
        case .departed: "Wenn der Zug den Einstiegsbahnhof verlässt"
        case .arrived: "Wenn du am Ausstieg angekommen bist"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .delay: "clock.arrow.circlepath"
        case .platform: "signpost.right.fill"
        case .cancelled: "xmark.octagon.fill"
        case .tightTransfer: "arrow.triangle.swap"
        case .arrivingSoon: "location.fill"
        case .departed: "tram.fill"
        case .arrived: "flag.checkered"
        }
    }

    var settingsTint: Color {
        switch self {
        case .delay, .tightTransfer: Theme.dawn
        case .platform: Theme.dusk
        case .cancelled: Theme.negative
        case .arrivingSoon, .departed: Theme.glacier
        case .arrived: Theme.pine
        }
    }
}
