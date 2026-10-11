import SwiftUI
import KlimaCore

// Empty, loading, error and offline states of the Fahrplan (docs/OEBB_LIVE.md §E3 table, UX §5). Copy in Du-Form.

/// Why nothing can be searched: consent open (the consent card), live data off, switched off remotely, offline.
struct PlannerUnavailableView: View {
    var reason: LiveDataService.Unavailable
    var onSettings: () -> Void

    var body: some View {
        switch reason {
        case .consentUndecided:
            LiveConsentCard(style: .card)
        case .declined, .switchedOff:
            PlannerNoticeCard(symbol: "antenna.radiowaves.left.and.right.slash", title: "Live-Daten sind aus",
                              message: "Für den Fahrplan fragt KlimaBilanz bei der ÖBB-Fahrplanauskunft ab – das geht erst, wenn du Live-Daten einschaltest. Deine Fahrten und Normalpreise funktionieren weiter offline.",
                              actionTitle: "Einstellungen", action: onSettings)
        case .killSwitch(let notice):
            PlannerNoticeCard(symbol: "exclamationmark.shield", title: "Fahrplan vorübergehend aus",
                              message: notice ?? "Die Live-Abfrage ist gerade abgeschaltet. KlimaBilanz nutzt solange die offiziellen Tarif-Tabellen.",
                              actionTitle: nil, action: nil)
        case .offline:
            PlannerNoticeCard(symbol: "wifi.slash", title: "Offline",
                              message: "Ohne Internet gibt es keinen Fahrplan. Normalpreise rechnet KlimaBilanz weiter aus den Tarif-Tabellen.",
                              actionTitle: nil, action: nil)
        }
    }
}

/// A calm card with an icon, a title, text and an optional button.
struct PlannerNoticeCard: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var tint: Color = Theme.accent

    var body: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(tint.opacity(0.14), in: .circle)
                    .accessibilityHidden(true)
                Text(title).font(Theme.Typography.title).foregroundStyle(Theme.textPrimary).accessibilityAddTraits(.isHeader)
                Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(action: action) { Text(actionTitle).font(.subheadline.weight(.semibold)).padding(.horizontal, 6) }
                        .buttonStyle(.glass)
                        .padding(.top, 2)
                }
            }
        }
    }
}

/// „Offline · Fahrplan von 11:40 · ohne Echtzeit“ – a glass pill above stale results.
struct PlannerOfflinePill: View {
    var since: Date?

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "wifi.slash").font(.system(size: 13, weight: .semibold))
            Text(since.map { "Offline · Fahrplan von \(Format.time($0)) · ohne Echtzeit" } ?? "Offline · ohne Echtzeit")
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.accentText)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The error banner for everything that is not the user's doing („ÖBB-Fahrplan gerade nicht erreichbar“).
struct PlannerErrorBanner: View {
    var failure: PlannerFailure
    var isRetrying = false
    var onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.negativeText)
                .frame(width: 38, height: 38)
                .background(Theme.negative.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                if showsRetry {
                    Button(action: onRetry) {
                        HStack(spacing: 6) {
                            if isRetrying { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                            Text("Erneut versuchen")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glass)
                    .padding(.top, 4)
                    .disabled(isRetrying)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .frostedCard(cornerRadius: Theme.Radius.card, tint: Theme.negative)
        .accessibilityElement(children: .contain)
    }

    private var showsRetry: Bool {
        switch failure {
        case .unreachable, .rateLimited, .offline: true
        default: false
        }
    }

    private var symbol: String {
        switch failure {
        case .rateLimited: "hourglass"
        case .offline: "wifi.slash"
        case .tooClose: "arrow.triangle.merge"
        case .stationNotFound, .locationUnavailable: "mappin.slash"
        default: "arrow.triangle.2.circlepath.circle"
        }
    }

    private var title: String {
        switch failure {
        case .rateLimited: "Kurz zu viele Anfragen"
        case .offline: "Offline"
        case .tooClose: "Start und Ziel sind zu nah beieinander."
        case .stationNotFound: "Haltestelle nicht gefunden – bitte anders suchen."
        case .locationUnavailable: "Standort nicht verfügbar"
        default: "ÖBB-Fahrplan gerade nicht erreichbar"
        }
    }

    private var message: String {
        switch failure {
        case .rateLimited: "Gleich geht's weiter."
        case .offline: "Sobald du wieder Netz hast, geht es hier weiter."
        case .tooClose: "Wähle ein weiter entferntes Ziel."
        case .stationNotFound: "Such die Haltestelle über ihren Namen."
        case .locationUnavailable: "Erlaube den Standort in den Einstellungen oder wähle einen Startpunkt."
        default: "Das liegt nicht an dir. Wir versuchen es automatisch wieder."
        }
    }
}

/// „Keine Verbindung gefunden“ with chips to widen the search.
struct PlannerNoConnectionView: View {
    var isKlimaTicketOnly: Bool
    var onTomorrow: () -> Void
    var onWiden: () -> Void

    var body: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                Text("Keine Verbindung gefunden").font(Theme.Typography.title).multilineTextAlignment(.center)
                Text("Zu dieser Zeit fährt nichts. Probier es morgen früh oder mit weniger Filtern.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                HStack(spacing: Theme.Spacing.xs) {
                    Button(action: onTomorrow) { Text("Morgen früh zeigen").font(.subheadline.weight(.semibold)).padding(.horizontal, 4) }
                        .buttonStyle(.glass)
                    Button(action: onWiden) {
                        Text(isKlimaTicketOnly ? "Filter aus" : "Alle Verkehrsmittel").font(.subheadline.weight(.semibold)).padding(.horizontal, 4)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Skeleton cards while connections load.
struct PlannerSkeletonList: View {
    var count = 3

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack { bar(80, 26); Spacer(); bar(54, 16); Spacer(); bar(80, 26) }
                    bar(nil, 24)
                    bar(190, 14)
                }
                .padding(Theme.Spacing.m)
                .frostedCard(cornerRadius: Theme.Radius.card)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verbindungen werden geladen")
    }

    private func bar(_ width: CGFloat?, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2.5, style: .continuous)
            .fill(Theme.surfaceSecondary)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
    }
}
