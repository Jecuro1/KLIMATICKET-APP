import SwiftUI
import SwiftData
import KlimaCore

// Building blocks of the trip-editor module ("Fahrt hinzufügen" sheet + station picker).
// Everything non-private is prefixed `TripEd` to stay collision-free with modules written in parallel.

// MARK: - Enums shared by the editor's subviews

/// Which stop the station picker edits.
enum TripEdPick: String, Identifiable {
    case from, to
    // MARK: via – first / second via, or a new one (TripEdViaRows.swift)
    case via1, via2, viaNew

    var id: String { rawValue }

    var endpoint: TripEditorModel.Endpoint { self == .from ? .from : .to }

    var pickerTitle: String {
        switch self {
        case .from: "Start wählen"
        case .to: "Ziel wählen"
        case .via1, .via2, .viaNew: "Über"
        }
    }
}

/// Focusable text fields of the editor (manual fare, note).
enum TripEdField: Hashable {
    case fare, note
}

// MARK: - Formatting

@MainActor
enum TripEdFormat {
    /// The editor has room for full names – only "Hauptbahnhof" is shortened ("Innsbruck Hbf").
    static func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: "Hauptbahnhof", with: "Hbf")
    }

    /// "Hauptbahnhof · Tirol", "Bahnhof · Vorarlberg", "Bushaltestelle · Warth · Vorarlberg".
    static func stationSubtitle(_ station: Station) -> String {
        station.rowSubtitle
    }

    /// Mode used for the coloured station icon.
    static func mode(for kind: Station.Kind) -> TransportMode {
        switch kind {
        case .rail: return .train
        case .metro: return .metro
        case .tramHub: return .tram
        case .stop: return .bus
        }
    }

    /// Category plaque ("S", "U", "Bus", "Bim") – only when known; trains without a category get none.
    static func badge(for mode: TransportMode) -> String? {
        switch mode {
        case .sBahn: return "S"
        case .metro: return "U"
        case .bus: return "Bus"
        case .tram: return "Bim"
        default: return nil
        }
    }

    /// "St. Anton ⇄ Innsbruck Hbf"
    static func routeTitle(from: String, to: String, roundTrip: Bool) -> String {
        "\(TripRow.short(from)) \(roundTrip ? "⇄" : "→") \(TripRow.short(to))"
    }

    /// "23,50" for the inline fare field (empty when there is no price yet).
    static func editableEuro(_ value: Double) -> String {
        value > 0 ? Format.number(value, decimals: 2) : ""
    }

    /// Parses de-AT input ("24,90", "24.90", "€ 1.024,50") → 24.9. Nil for empty/invalid/implausible values.
    static func parseEuro(_ text: String) -> Double? {
        var s = text.replacingOccurrences(of: "€", with: "")
        s = s.components(separatedBy: .whitespacesAndNewlines).joined()
        if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        guard !s.isEmpty, let value = Double(s), value.isFinite, value > 0, value < 10_000 else { return nil }
        return (value * 100).rounded() / 100
    }

    /// "+ € 47,00"
    static func plusEuro(_ value: Double) -> String { "+ " + Format.euroPrecise(value) }
}

// MARK: - Model helpers (read-only conveniences; the logic lives in TripEditorModel)

extension TripEditorModel {
    /// Route meta under the stations: "Zug · 101 km" (nothing is invented – no duration).
    var tripEdRouteMeta: String? {
        guard distanceKm > 0 else { return nil }
        return "\(mode.displayName) · \(Format.km(distanceKm))"
    }

    /// Whether a favourite describes exactly the route currently in the form.
    func tripEdMatches(_ favorite: FavoriteRouteEntity) -> Bool {
        guard favorite.modeRaw == mode.rawValue, favorite.isRoundTrip == isRoundTrip else { return false }
        guard tripEdViaMatches(favorite) else { return false }   // MARK: via
        return Self.tripEdSameStop(favorite.fromStationID, fromStation, favorite.fromName, resolvedFromName)
            && Self.tripEdSameStop(favorite.toStationID, toStation, favorite.toName, resolvedToName)
    }

    private static func tripEdSameStop(_ id: String?, _ station: Station?, _ name: String, _ resolved: String) -> Bool {
        if let id, let station { return id == station.id }
        return !resolved.isEmpty && name == resolved
    }

    /// Amortisation of `ticket` without and with the trip in this form, against the own share (`price`). `before` leaves
    /// out the trip being edited (wherever its old date lies), `after` adds the form's value only when the form's date is
    /// inside the ticket period. Nil when the own share is 0. The baseline is cached (`tripEdBaseline`).
    func tripEdImpact(ticket: TicketEntity, context: ModelContext)
        -> (before: Double, after: Double, price: Double, inPeriod: Bool)? {
        let base = tripEdBaseline(ticket: ticket, context: context)
        let price = base.period.price
        guard price > 0 else { return nil }
        let inPeriod = base.period.contains(date)
        let added = inPeriod ? totalValue : 0
        return (base.value / price, (base.value + added) / price, price, inPeriod)
    }
}

// MARK: - Small views

/// Coloured rounded-square icon used in form rows ("Datum", "Hin- und Rückfahrt" …).
struct TripEdIconTile: View {
    var symbol: String
    var tint: Color

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Icon tile + title + optional subtitle (label of toggles, steppers and plain rows).
struct TripEdRowLabel: View {
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            TripEdIconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Neutral outline capsule with the line category ("S", "U", "Bus", "Bim").
struct TripEdModeBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay { Capsule().strokeBorder(Theme.textTertiary, lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

/// Hairline between rows inside a form card (inset past the icon tile).
struct TripEdRowDivider: View {
    var inset: CGFloat = 60

    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// Subtle press feedback for custom tappable areas.
struct TripEdPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
