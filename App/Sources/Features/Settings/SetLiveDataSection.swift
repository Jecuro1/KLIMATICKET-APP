import SwiftUI
import KlimaCore

/// Einstellungen › Live-Daten (docs/OEBB_LIVE.md §E7): the consent toggle, the two feature switches, the health of each
/// provider, „Verbindung testen“ and „Live-Cache leeren“. Inserted after `SetFareSection`.
struct SetLiveDataSection: View {
    @Environment(AppState.self) private var app
    @State private var testState: TestState = .idle
    @State private var cacheCleared = false

    enum TestState: Equatable { case idle, running, ok, failed }

    var body: some View {
        let live = app.live
        let granted = live.consent == .granted
        Section {
            Group {
                Toggle(isOn: Binding(get: { granted }, set: { live.setConsent($0 ? .granted : .declined) })) {
                    SetRowLabel(title: "Live-Daten", subtitle: "Fahrplan, Echtzeit & Ticketpreise live abfragen",
                                symbol: "dot.radiowaves.left.and.right", tint: Theme.glacier)
                }
                .haptic(.snap, trigger: granted)
                Toggle(isOn: Binding(get: { live.isTimetableEnabledBySettings }, set: { live.setTimetableEnabled($0) })) {
                    SetRowLabel(title: "Fahrplan & Echtzeit", symbol: "clock.badge.checkmark.fill", tint: Theme.modeColor(.sBahn))
                }
                .padding(.leading, Theme.Spacing.m)
                .disabled(!granted)
                Toggle(isOn: Binding(get: { live.isLivePriceEnabledBySettings }, set: { live.setPricesEnabled($0) })) {
                    SetRowLabel(title: "Live-Ticketpreise", subtitle: "Normalpreis aus ÖBB-Ticketshop bzw. Verbundtarif",
                                symbol: "eurosign.circle.fill", tint: Theme.pine)
                }
                .padding(.leading, Theme.Spacing.m)
                .disabled(!granted)

                if granted || live.consent == .undecided {
                    ForEach(LiveProvider.allCases, id: \.self) { provider in
                        providerRow(provider, status: live.health[provider], enabled: granted)
                    }
                }

                if granted {
                    Button { Task { await runTest() } } label: {
                        HStack {
                            SetRowLabel(title: "Verbindung testen", symbol: "bolt.horizontal.fill", tint: Theme.dusk)
                            Spacer(minLength: 8)
                            testAccessory
                        }
                    }
                    .disabled(testState == .running)
                    Button {
                        Task {
                            await live.resetCaches()
                            cacheCleared = true
                            app.showToast("trash.fill", "Live-Cache geleert")
                        }
                    } label: {
                        SetRowLabel(title: "Live-Cache leeren", subtitle: "Gemerkte Preise und Haltestellen-Zuordnungen",
                                    symbol: "arrow.triangle.2.circlepath", tint: Theme.dawn)
                    }
                    .haptic(.warning, trigger: cacheCleared)
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Live-Daten")
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let notice = live.config.notice { SetFooter(text: notice) }
                SetFooter(text: footerText(live))
            }
        }
        .task { await live.refreshHealth() }
    }

    private func footerText(_ live: LiveDataService) -> String {
        switch live.consent {
        case .undecided: "Noch nichts gesendet: Live-Daten sind erst nach deiner Zustimmung aktiv. Bis dahin nutzt KlimaBilanz die offiziellen Tarif-Tabellen."
        case .declined: "Aus: KlimaBilanz bleibt offline und nutzt die offiziellen Tarif-Tabellen. Der Fahrplan braucht Live-Daten."
        case .granted: "Dein iPhone fragt direkt bei der ÖBB und der Verkehrsauskunft Österreich ab – ohne Konto, für „In der Nähe“ mit einem auf rund 100 m gerundeten Standort. KlimaBilanz selbst erhält diese Daten nicht."
        }
    }

    // MARK: Rows

    private func providerRow(_ provider: LiveProvider, status: LiveHealth.Status?, enabled: Bool) -> some View {
        let (text, tint) = Self.statusLine(provider, status: status, enabled: enabled, now: Date())
        return HStack(alignment: .firstTextBaseline) {
            Text(Self.providerName(provider)).font(.subheadline).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Text(text).font(.footnote).foregroundStyle(tint).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var testAccessory: some View {
        switch testState {
        case .idle: EmptyView()
        case .running: ProgressView()
        case .ok: SetPill(text: "Verbunden", symbol: "checkmark.circle.fill", tint: Theme.positiveText).motionTransition(.pop)
        case .failed: SetPill(text: "Nicht erreichbar", symbol: "exclamationmark.triangle.fill", tint: Theme.negativeText).motionTransition(.pop)
        }
    }

    private func runTest() async {
        withMotion(Motion.snappy) { testState = .running }
        let ok = await app.live.testConnection()
        withMotion(Motion.bouncy) { testState = ok ? .ok : .failed }
    }

    // MARK: Status text

    static func providerName(_ provider: LiveProvider) -> String {
        switch provider {
        case .oebbHafas: "ÖBB-Fahrplan"
        case .oebbShop: "ÖBB-Ticketshop"
        case .vaoTariff: "Verkehrsauskunft Österreich"
        }
    }

    /// „zuletzt OK 11:58“ · „pausiert bis 12:30“ · „noch nicht genutzt“ · „nicht erreichbar“.
    static func statusLine(_ provider: LiveProvider, status: LiveHealth.Status?, enabled: Bool, now: Date) -> (String, Color) {
        guard enabled else { return ("aus", Theme.textSecondary) }
        if let until = status?.openUntil, until > now { return ("pausiert bis \(Format.time(until))", Theme.summitText) }
        if let ok = status?.lastSuccess, status?.lastError == nil || (status?.consecutiveFailures ?? 0) == 0 {
            return ("zuletzt OK \(Format.time(ok))", Theme.positiveText)
        }
        if status?.lastError != nil, (status?.consecutiveFailures ?? 0) > 0 { return ("gestört", Theme.negativeText) }
        if let ok = status?.lastSuccess { return ("zuletzt OK \(Format.time(ok))", Theme.positiveText) }
        return ("noch nicht genutzt", Theme.textSecondary)
    }
}
