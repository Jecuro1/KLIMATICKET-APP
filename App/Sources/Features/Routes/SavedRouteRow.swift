import SwiftUI
import KlimaCore

/// One saved route in the list: mode, name, the route line, the schedule, the next cached departure, fare and CO₂.
struct SavedRouteRow: View {
    let route: FavoriteRouteEntity
    /// The connection cache the list read once for all rows (`SavedRouteDepartures.currentCache`).
    let cache: WidgetConnectionCache?
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            ModeIcon(mode: route.mode, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(route.displayTitle)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(SavedRoutes.routeLine(from: route.fromName, via: route.via.map(\.name), to: route.toName))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                if let schedule = route.schedule {
                    Label(schedule.summary, systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                }
                departureLine
            }
            Spacer(minLength: Theme.Spacing.xs)
            VStack(alignment: .trailing, spacing: 3) {
                Text(fareText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(co2Text)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.positiveText)
                if route.isRoundTrip {
                    Text("hin & retour")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var departureLine: some View {
        if !route.viaRaw.isEmpty || route.isCombo {
            Text("Live-Abfahrten gibt es für Strecken mit Zwischenhalt nicht")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        } else if let next = SavedRouteDepartures.connections(for: route, in: cache).first(where: { departure($0) >= Date().addingTimeInterval(-60) }) {
            let platform = next.platform.map { " · \($0)" } ?? ""
            Text("Nächste \(Format.time(departure(next))) · \(next.lineName)\(platform)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.positiveText)
        } else if SavedRouteDepartures.unavailableText(app.live) != nil {
            Text("Live-Abfahrten sind aus")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        } else {
            Text("Keine Abfahrt in der nächsten Zeit geladen")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func departure(_ connection: WidgetConnection) -> Date {
        connection.realtime ?? connection.planned
    }

    /// The fare of one log of the route: both directions for a return trip (`valuePerLog`).
    private var fareText: String {
        SavedRouteFigures.fareEUR(route).map { Format.euroPrecise($0) } ?? "Preis offen"
    }

    private var co2Text: String {
        let kg = SavedRouteFigures.co2Kg(route, app: app)
        return kg > 0 ? "\(Format.number(kg, decimals: 1)) kg CO₂" : "CO₂ offen"
    }
}
