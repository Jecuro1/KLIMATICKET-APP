import SwiftUI
import SwiftData
import KlimaCore

// MARK: commute – the Pendel-Modus card on the Übersicht (docs/COMMUTE.md §1). Four faces, decided by the settings and the clock:
// 1. not set up: an invitation „Ist das dein Arbeitsweg?“ – only when the detector is confident and the pair was not declined;
// 2. set up, outside the window: one compact line „Nächste Pendelfahrt heute 17:12“;
// 3. inside the window (from 45 minutes before): the next three connections with delay, platform and the age of the data;
// 4. the first connection cancelled or 10+ minutes late: a banner with the better connection of the same search.
// Without live data the card works from the plan and offers the consent once. It renders nothing when the mode is off and there
// is nothing to ask, and nothing in CI scenes other than its own (other tracks' screenshots stay as they were).

struct CommuteCardSection: View {
    /// The Übersicht's trips (newest first) – the detector reads the last 56 days.
    var trips: [TripEntity]
    /// „Meine Routen“ (the favourites): their schedules prefill the plan.
    var savedRoutes: [FavoriteRouteEntity]

    @Environment(AppState.self) private var app
    private var model: CommuteModel { .shared }

    /// Shown in normal runs and in the commute's own CI scenes only.
    static var isAllowedHere: Bool {
        guard LaunchMode.isSandboxed else { return true }
        return CommuteScreenshotHost.screens.contains(LaunchMode.screenshotScreen ?? "")
    }

    var body: some View {
        Group {
            // Nothing at all (no padding either) when there is no face to show: the Übersicht stays as it was.
            if Self.isAllowedHere, faceKey != 0 {
                content
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.top, DashStyle.cardSpacing)
                    .motionTransition(.rise)
            }
        }
        .motionAnimation(Motion.smooth, value: faceKey)
        .task(id: DetectKey(count: trips.count, newest: trips.first?.updatedAt, enabled: model.settings.isEnabled)) { detect() }
        .sheet(isPresented: Binding(get: { model.showsSetup }, set: { model.showsSetup = $0 })) {
            NavigationStack { CommuteSettingsPage(isSheet: true) }
        }
    }

    @ViewBuilder
    private var content: some View {
        let settings = model.settings
        if settings.isActive {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                CommuteActiveCard(now: model.demo?.now ?? context.date)
            }
        } else if settings.isEnabled {
            CommuteNeedsRouteCard { model.showsSetup = true }
        } else if let guess = invitation {
            CommuteInviteCard(guess: guess,
                              onAccept: { CommuteActions(app: app).accept(guess, savedRoutes: savedRoutes) },
                              onDecline: { CommuteActions(app: app).decline(guess) })
        }
    }

    /// The confident guess that was not declined in the last 30 days.
    private var invitation: CommuteGuess? {
        guard let guess = model.guess, guess.confidence == .high, !model.settings.isDeclined(guess.pairKey, now: model.now()) else { return nil }
        return guess
    }

    /// Which face shows (the cross-fade between faces).
    private var faceKey: Int {
        let s = model.settings
        if s.isActive { return 1 }
        if s.isEnabled { return 2 }
        return invitation == nil ? 0 : 3
    }

    /// The detector on the last 56 days, only while there is something to ask (mode off). Demo scenes bring their own guess.
    private func detect() {
        guard model.demo == nil, !model.settings.isEnabled else { return }
        let now = Date()
        let start = now.addingTimeInterval(-Double(CommuteDetector.windowDays + 1) * 86_400)
        let recent = trips.prefix { $0.date >= start }.filter { $0.deletedAt == nil }.map(\.record)
        model.guess = CommuteDetector.guess(trips: Array(recent), now: now, calendar: .vienna, homeStationID: app.settings.homeStationID)
    }
}

private struct DetectKey: Hashable {
    var count: Int
    var newest: Date?
    var enabled: Bool
}

// MARK: - Active card (set up)

/// The card once the Stammstrecke is set: live, compact or without weekday, by the clock.
struct CommuteActiveCard: View {
    let now: Date

    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    /// The card is (at least a sliver) inside the Übersicht's scroll view; scrolled away, the refreshes pause.
    @State private var isVisible = true
    private var model: CommuteModel { .shared }

    var body: some View {
        switch model.windowState(at: now) {
        case .live(let slot):
            CommuteLiveCard(slot: slot, now: now)
                .onScrollVisibilityChange(threshold: 0.05) { isVisible = $0 }
                .task(id: RefreshKey(slot: slot, direction: model.direction(for: slot), generation: app.live.generation,
                                     active: scenePhase == .active && isVisible, unavailable: model.liveUnavailable(app.live) != nil)) {
                    await refreshLoop(slot: slot)
                }
        case .upcoming(let slot):
            CommuteCompactCard(slot: slot, now: now)
        case .inactive:
            CommuteNeedsRouteCard(title: "Kein Wochentag gewählt", subtitle: "Wähle in den Pendel-Einstellungen, wann du fährst.") {
                model.showsSetup = true
            }
        }
    }

    /// One search when the window opens, the direction changes, the card scrolls back in or the app comes back; then every
    /// 60 s while the card is on screen and the app is active. Never without live data; the minute refresh pauses in Low Power Mode.
    private func refreshLoop(slot: CommuteSlot) async {
        guard scenePhase == .active, isVisible, model.liveUnavailable(app.live) == nil else { return }
        await model.refresh(app: app, slot: slot)
        guard model.demo == nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(CommuteSearch.minRefreshInterval))
            guard !Task.isCancelled, !ProcessInfo.processInfo.isLowPowerModeEnabled else { continue }
            await model.refresh(app: app, slot: slot)
        }
    }
}

private struct RefreshKey: Hashable {
    var slot: CommuteSlot
    var direction: CommuteDirection
    var generation: Int
    var active: Bool
    var unavailable: Bool
}
