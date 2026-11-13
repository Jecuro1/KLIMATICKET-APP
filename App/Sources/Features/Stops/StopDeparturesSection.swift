import KlimaCore
import SwiftUI

// MARK: commute – „Nächste Abfahrten“ (ENRICH_SPEC §4, docs/COMMUTE.md §12): the next eight departures of the stop as the Fahrplan's
// board rows (time with realtime, line plate, destination, notice, platform; a cancelled run is struck through), the age of the
// answer and „Alle Abfahrten“ to the board. It asks only while the section is on screen and the app is active, at most once a
// minute, and only with live data. Without consent it offers the switch once; declined or switched off, it stays away.

struct StopDeparturesSection: View {
    let model: StopDetailModel

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var showsConsent = false

    var body: some View {
        if StopFeatureFlags.showsDepartures, let place = model.details?.place, isShown {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    StopSectionTitle(text: "Nächste Abfahrten")
                    Spacer(minLength: Theme.Spacing.xs)
                    if canShowBoard(place) {
                        Button { openBoard(place) } label: {
                            Label("Alle Abfahrten", systemImage: "chevron.right")
                                .labelStyle(TrailingIconLabelStyle())
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accentText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Öffnet die Abfahrtstafel im Fahrplan")
                    }
                }
                SurfaceCard(padding: 16, cornerRadius: 24) {
                    content
                }
            }
            .motionAnimation(Motion.smooth, value: model.departures)
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .onScrollVisibilityChange(threshold: 0.2) { isVisible = $0 }
            .task(id: LoadKey(visible: isVisible, active: scenePhase == .active, generation: app.live.generation)) {
                await loadLoop()
            }
            .sheet(isPresented: $showsConsent) { CommuteConsentSheet() }
            .motionTransition(.rise)
        }
    }

    /// Declined or switched off: the section stays away (the stop detail is complete without it). Undecided: the offer.
    private var isShown: Bool {
        guard !app.live.isDemo else { return true }
        switch app.live.timetableUnavailable {
        case .declined?, .switchedOff?: return false
        default: return true
        }
    }

    /// The model's state; before the first load the live gate already says why nothing will come.
    private var state: DeparturesState {
        if case .unavailable(nil) = model.departures, !app.live.isDemo, let reason = app.live.timetableUnavailable {
            return .unavailable(reason)
        }
        return model.departures
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .unavailable(.consentUndecided?):
            Button { showsConsent = true } label: {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    SetIconTile(symbol: "dot.radiowaves.left.and.right", tint: Theme.glacier, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Abfahrten live sehen?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Mit Live-Daten zeigt KlimaBilanz hier die nächsten Abfahrten mit Verspätung und Gleis.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.pressableCard)
            .accessibilityHint("Erklärt die Live-Daten und fragt nach deiner Zustimmung")
        case .unavailable(.killSwitch(let notice)?):
            CommuteNotice(symbol: "pause.circle", text: notice ?? "Live-Daten sind gerade pausiert.")
        case .unavailable(.offline?):
            CommuteNotice(symbol: "wifi.slash", text: "Offline – die Abfahrten kommen, sobald du wieder Netz hast.")
        case .unavailable, .loading:
            CommuteRowsSkeleton()
        case .empty:
            CommuteNotice(symbol: "moon.zzz", text: "In den nächsten \(StopBoardDepartures.minutes) Minuten fährt hier nichts ab.")
        case .failed:
            CommuteNotice(symbol: "exclamationmark.icloud", text: "ÖBB-Auskunft gerade nicht erreichbar – neuer Versuch in einer Minute.")
        case .unknownStop:
            CommuteNotice(symbol: "questionmark.circle", text: "Für diese Haltestelle findet die ÖBB-Auskunft keine Abfahrtstafel.")
        case .live(let snapshot):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(snapshot.rows.enumerated()), id: \.element.id) { index, row in
                    DepartureRow(row: row)
                        .accessibilityHint("")
                        .accessibilityRemoveTraits(.isButton)
                        .reveal(.rise, order: index)
                    if index < snapshot.rows.count - 1 { Divider().overlay(Theme.separator) }
                }
                CommuteDataAgeLine(fetchedAt: snapshot.fetchedAt, hasRealtime: snapshot.hasRealtime, isOffline: false,
                                   isDemo: app.live.isDemo)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    // MARK: Loading

    /// One board when the section comes on screen (or the app comes back, or live data changes), then every minute while it
    /// stays on screen. The minute refresh pauses in Low Power Mode.
    private func loadLoop() async {
        guard isVisible, scenePhase == .active else { return }
        await model.loadDepartures(live: app.live)
        guard !LaunchMode.isSandboxed else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(StopBoardDepartures.minRefreshInterval))
            guard !Task.isCancelled, !ProcessInfo.processInfo.isLowPowerModeEnabled else { continue }
            await model.loadDepartures(live: app.live)
        }
    }

    // MARK: Board

    private func canShowBoard(_ place: Place) -> Bool {
        if case .live = model.departures { return true }
        if case .empty = model.departures { return true }
        return false
    }

    /// The Fahrplan's Abfahrtstafel for this stop (every departure, arrivals, another time).
    private func openBoard(_ place: Place) {
        let stationID = place.stationID
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            app.selectedTab = .planner
            app.planner.showBoard(stationID: stationID)
        }
    }
}

private struct LoadKey: Hashable {
    var visible: Bool
    var active: Bool
    var generation: Int
}

/// „Alle Abfahrten ›“ – the title first, the chevron after it.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}
