import SwiftUI
import KlimaCore

/// The one-time consent for live data (docs/OEBB_LIVE.md §E7, decision D5). Shown on the first Fahrplan visit (`.card`) and
/// inline in the trip editor's price card (`.inline`) while the decision is open. Until the user taps „Aktivieren“, nothing
/// is sent to ÖBB or the Verkehrsauskunft Österreich – „Nur Offline-Daten“ keeps the app exactly as it was.
struct LiveConsentCard: View {
    enum Style { case card, inline }

    var style: Style = .card
    @Environment(AppState.self) private var app
    @State private var decisionTick = 0

    static let title = "Live-Daten aktivieren?"
    static let body = "KlimaBilanz kann Fahrplan, Echtzeit und Ticketpreise direkt bei der ÖBB-Fahrplanauskunft, im ÖBB-Ticketshop und bei der Verkehrsauskunft Österreich abfragen – von deinem iPhone aus, ohne Konto. Diese Schnittstellen sind nicht offiziell für andere Apps freigegeben und können sich jederzeit ändern. Ohne Live-Daten nutzt KlimaBilanz weiter die offiziellen Tarif-Tabellen."

    var body: some View {
        switch style {
        case .card: card
        case .inline: inline
        }
    }

    // MARK: Card

    private var card: some View {
        GlassCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    SetIconTile(symbol: "dot.radiowaves.left.and.right", tint: Theme.glacier, size: 40)
                    Kicker(text: "Fahrplan live")
                }
                Text(Self.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(Self.body)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Theme.Spacing.xs) {
                    Button { decide(.granted) } label: {
                        Text("Aktivieren").font(.headline).frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.prominentTint)
                    Button { decide(.declined) } label: {
                        Text("Nur Offline-Daten").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 24)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.top, Theme.Spacing.xxs)
            }
        }
        .haptic(.success, trigger: decisionTick)
    }

    // MARK: Inline

    private var inline: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                SetIconTile(symbol: "dot.radiowaves.left.and.right", tint: Theme.glacier, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live-Preis aktivieren?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Den Normalpreis live aus dem ÖBB-Ticketshop holen – von deinem iPhone aus, ohne Konto.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Theme.Spacing.xs) {
                Button { decide(.granted) } label: {
                    Text("Aktivieren").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.prominentTint)
                Button { decide(.declined) } label: {
                    Text("Nur Offline-Daten").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(Theme.Spacing.s)
        .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: Theme.Radius.formGroup, style: .continuous))
        .haptic(.success, trigger: decisionTick)
    }

    private func decide(_ consent: LiveDataService.Consent) {
        withMotion(Motion.smooth) { app.live.setConsent(consent) }
        decisionTick += 1
    }
}
