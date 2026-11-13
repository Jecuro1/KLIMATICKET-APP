import SwiftUI
import SwiftData
import KlimaCore

// MARK: funktionen – Einstellungen › Funktionen (docs/FUNCTIONS_HUB.md). The app side of the hub: `features.v1` (Offline-Modus and
// the hub's own switches), the bridge to the switches that live elsewhere, and the gate every entry point asks. Nothing here changes
// the live-data consent; the hub only adds ways to switch things off.

@Observable
@MainActor
final class FeatureCenter {
    static let shared = FeatureCenter()

    /// What the hub stores. Screenshot and perf runs start from the defaults and store nothing.
    private(set) var settings: FeatureSettings {
        didSet {
            guard settings != oldValue else { return }
            defaults?.set(settings.encoded(), forKey: FeatureSettings.storageKey)
        }
    }

    /// A deep link or a widget control asked for a feature that is off: the hub opens at its row (`FeatureLinkHost`).
    var linkFocus: FeatureLinkRequest?

    /// CI scenes: wrapped switches shown as if set (the screenshot run's own settings are never written).
    private(set) var demoWrapped: [FeatureID: Bool] = [:]

    @ObservationIgnored private let defaults: UserDefaults?

    init(defaults: UserDefaults? = LaunchMode.isSandboxed ? nil : .standard) {
        self.defaults = defaults
        settings = FeatureSettings.decode(defaults?.data(forKey: FeatureSettings.storageKey))
    }

    var offlineMode: Bool { settings.offlineMode }

    // MARK: Gate

    /// The switches that live elsewhere, read where they are stored.
    func context(app: AppState) -> FeatureContext {
        let s = app.settings
        var wrapped: [FeatureID: Bool] = [
            .liveTimetable: s.liveTimetableEnabled,
            .livePrices: s.livePricesEnabled,
            .followNotices: s.followNotices.isEnabled,
            .tripDetection: app.detection.isEnabled,
            .assistant: s.localAIEnabled,
            .renewalReminders: s.renewalRemindersEnabled,
            .weeklySummary: s.weeklySummaryEnabled,
            .haptics: s.hapticsEnabled,
            .officialLogos: LogoPackStore.shared.userEnabled,
        ]
        wrapped.merge(demoWrapped) { _, demo in demo }
        return FeatureContext(wrapped: wrapped, live: liveState(app.live))
    }

    /// The live layer as the hub tells it (the consent first, then the remote switch, then the connection).
    private func liveState(_ live: LiveDataService) -> FeatureLiveState {
        if live.isDemo { return .ready }
        switch live.consent {
        case .undecided: return .consentOpen
        case .declined: return .declined
        case .granted: break
        }
        if live.config.killSwitch || !live.config.isEnabled(.oebbHafas) { return .remoteOff }
        return live.isOnline ? .ready : .noInternet
    }

    func status(_ id: FeatureID, app: AppState) -> FeatureStatus {
        FeatureGate.status(id, settings: settings, context: context(app: app))
    }

    func isOn(_ id: FeatureID, app: AppState) -> Bool {
        FeatureGate.isOn(id, settings: settings, context: context(app: app))
    }

    // MARK: Switches

    /// Sets a feature's own switch – in `features.v1` for the hub's switches, at its own place for the others. Switches whose
    /// effect needs more than the value (notices to plan, a permission) do it here exactly like their own settings row.
    func set(_ id: FeatureID, _ on: Bool, app: AppState, tickets: [TicketEntity] = [], context: ModelContext? = nil) {
        if id.descriptor.isHubSwitch {
            settings.set(id, on)
            return
        }
        let s = app.settings
        switch id {
        case .liveTimetable: app.live.setTimetableEnabled(on)
        case .livePrices: app.live.setPricesEnabled(on)
        case .assistant: s.localAIEnabled = on
        case .haptics: s.hapticsEnabled = on
        case .officialLogos: LogoPackStore.shared.userEnabled = on
        case .renewalReminders:
            guard s.renewalRemindersEnabled != on else { return }
            s.renewalRemindersEnabled = on
            FeatureNoticeEffects.renewalReminders(on, app: app, tickets: tickets, context: context)
        case .weeklySummary:
            guard s.weeklySummaryEnabled != on else { return }
            s.weeklySummaryEnabled = on
            FeatureNoticeEffects.weeklySummary(on, app: app)
        case .followNotices, .tripDetection:
            break   // switched on their own page (permission and setup), the hub links there
        case .radar, .trainSearch, .disruptions, .perksCard, .achievementsTeaser, .weekInsight:
            break   // hub switches, handled above
        }
    }

    /// Offline-Modus: live data and the automatic update check stop; the consent stays as it is.
    func setOfflineMode(_ on: Bool, app: AppState) {
        guard settings.offlineMode != on else { return }
        settings.offlineMode = on
        app.live.featureSwitchesChanged()
    }

    // MARK: Links

    /// A link or a control wants `id`. True when it is on; otherwise the hub opens at its row with a toast, and the caller stops.
    func allowsLink(to id: FeatureID, app: AppState) -> Bool {
        guard !isOn(id, app: app) else { return true }
        let title = id.title
        app.showToast("eye.slash.fill", "\(title) ist ausgeblendet", "Hier kannst du es wieder einschalten", haptic: .warning)
        // A sheet cannot be presented over Einstellungen: that closes first (like „Fahrt erfassen“ from outside).
        if app.isShowingSettings {
            app.isShowingSettings = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                self.linkFocus = FeatureLinkRequest(id: id)
            }
        } else {
            linkFocus = FeatureLinkRequest(id: id)
        }
        return false
    }

    // MARK: Demo

    /// Screenshot scenes: the settings of a scene and wrapped switches to show, in memory only (sandboxed runs store nothing).
    func installDemo(_ settings: FeatureSettings, wrapped: [FeatureID: Bool] = [:]) {
        guard LaunchMode.isSandboxed else { return }
        self.settings = settings
        demoWrapped = wrapped
    }
}

/// The hub opened by a link (`FeatureCenter.allowsLink`).
struct FeatureLinkRequest: Identifiable, Equatable {
    let id: FeatureID
}

/// Renewal reminders and the weekly summary need more than their value: a permission when they go on, planned or removed
/// notices. The same steps as their rows in Einstellungen › Mitteilungen (`SetNotificationsSection`).
enum FeatureNoticeEffects {
    @MainActor
    static func renewalReminders(_ on: Bool, app: AppState, tickets: [TicketEntity], context: ModelContext?) {
        Task {
            if on {
                _ = await app.notifications.requestAuthorization()
                guard let context else { return }
                let repository = Repository(context: context, app: app)
                for ticket in tickets where !ticket.isExpired { repository.scheduleReminders(for: ticket) }
            } else {
                for ticket in tickets { await app.notifications.cancelRenewalReminders(ticketID: ticket.id) }
            }
        }
    }

    @MainActor
    static func weeklySummary(_ on: Bool, app: AppState) {
        Task {
            if on { _ = await app.notifications.requestAuthorization() }
            await app.notifications.setWeeklySummary(enabled: on)
        }
    }
}

// MARK: - Gate sites

/// Shows its content only while the feature is on – entry points of an off feature are hidden, not greyed (the hub names
/// what it hid). One line per gate site, marked `// MARK: funktionen`.
private struct FeatureGateModifier: ViewModifier {
    let ids: [FeatureID]
    @Environment(AppState.self) private var app

    func body(content: Content) -> some View {
        if ids.contains(where: { FeatureCenter.shared.isOn($0, app: app) }) {
            content
        }
    }
}

extension View {
    /// Hidden while `id` is off.
    func featureGated(_ id: FeatureID) -> some View { modifier(FeatureGateModifier(ids: [id])) }
    /// Hidden while every one of `ids` is off (a container of several gated entries).
    func featureGatedAny(_ ids: FeatureID...) -> some View { modifier(FeatureGateModifier(ids: ids)) }
    /// Opens the hub at a feature's row when a link asked for it while it is off (RootView, `// MARK: funktionen`).
    func featureLinkHost() -> some View { modifier(FeatureLinkHost()) }
}

/// The hub as a sheet over the app, opened by a link to a hidden feature.
private struct FeatureLinkHost: ViewModifier {
    @Bindable private var center = FeatureCenter.shared

    func body(content: Content) -> some View {
        content.sheet(item: $center.linkFocus) { request in
            NavigationStack { FeaturesHubView(focus: request.id, isSheet: true) }
                .overlay(alignment: .top) {
                    // RootView's toast sits under the sheet: mirror it above, below the navigation bar.
                    ToastOverlay(playsHaptic: false).padding(.top, 56)
                }
        }
    }
}
