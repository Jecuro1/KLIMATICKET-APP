import SwiftUI
import KlimaCore

// MARK: tarifstand – Einstellungen › Preisberechnung › „Tarifstand“ and „Jetzt prüfen“ (docs/TARIFF_FRESHNESS.md).

/// Two rows of the price section: „Tarifstand“ with the three dates behind the numbers (from the relation table in use, the
/// catalogue and the cache) opening the details page, and „Jetzt prüfen“ – a forced look for newer prices that answers
/// Aktuell, Aktualisiert, Kein Netz or Fehlgeschlagen. Nothing is claimed that the data does not hold: a missing date is left out.
struct SetTarifstandRows: View {
    @Environment(AppState.self) private var app
    @Environment(\.tariffNoticeInput) private var injected
    @Environment(\.tarifCheckPreset) private var preset
    @State private var check: TarifCheck

    init() {
        _check = State(initialValue: TarifCheck())
    }

    var body: some View {
        let input = injected ?? app.tariffNoticeInput()
        let state = TariffFreshness.state(catalog: input.catalog, now: input.now, lastCheck: input.lastCheck)
        NavigationLink {
            TariffNoticeSheet(input: input, showsClose: false)
                .navigationTitle("Tarifstand")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Tarifstand", subtitle: summary(input), symbol: "calendar.badge.clock", tint: Theme.dawn)
                Spacer(minLength: Theme.Spacing.xs)
                if !state.isCurrent {
                    SetPill(text: "Hinweis", symbol: "exclamationmark.circle.fill", tint: Theme.summitText)
                        .motionTransition(.pop)
                }
            }
            .motionAnimation(Motion.smooth, value: state)
        }
        checkRow(input)
    }

    private func summary(_ input: TariffNoticeInput) -> String {
        TariffFreshness.summaryLine(fareValidFrom: input.fareValidFrom,
                                    ticketPricesAsOf: TariffFreshness.ticketPricesAsOf(catalog: input.catalog, now: input.now),
                                    lastCheck: input.lastCheck)
    }

    private var hasSource: Bool {
        app.tariffs.tariffsURL(manifestHint: app.updates.manifest) != nil
    }

    /// The arrows turn while it runs; the result (word, symbol, one haptic) stays in the row until the next check.
    private func checkRow(_ input: TariffNoticeInput) -> some View {
        Button {
            Task { await check.run(app: app) }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetRowLabel(title: "Jetzt prüfen",
                            subtitle: hasSource || LaunchMode.isScreenshot ? nil : "Keine Online-Quelle eingerichtet",
                            symbol: "arrow.triangle.2.circlepath", tint: Theme.glacier, isBusy: check.isChecking)
                Spacer(minLength: Theme.Spacing.xs)
                SetBusyIndicator(isBusy: check.isChecking)
                if case .finished(let result) = check.phase {
                    SetPill(text: result.title, symbol: result.symbol, tint: result.isSuccess ? Theme.positiveText : Theme.summitText)
                        .motionTransition(.pop)
                }
            }
            .motionAnimation(Motion.smooth, value: check.phase)
        }
        .disabled(check.isChecking || (!hasSource && !LaunchMode.isScreenshot))
        .task { if let preset { check.preset(preset) } }   // demo fixture: a finished check
        .tarifCheckFeedback(check)
        .accessibilityValue(check.isChecking ? "Wird geprüft" : "")
    }
}
