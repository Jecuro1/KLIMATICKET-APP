import SwiftUI
import SwiftData
import KlimaCore

// Building blocks of the trip-editor module ("Fahrt hinzufügen" sheet + station picker).
// Everything non-private is prefixed `TripEd` to stay collision-free with modules written in parallel.

// MARK: - Enums shared by the editor's subviews

/// Which stop the station picker edits.
enum TripEdPick: Hashable, Identifiable {
    /// Start / destination of the whole route.
    case from, to
    // MARK: via – first / second via of the selected leg, or a new one (TripEdViaRows.swift)
    case via1, via2, viaNew
    // MARK: trips – a transfer stop of a journey (index into the model's stops) / the destination of a new leg
    case transfer(Int), legNew

    var id: String {
        switch self {
        case .from: "from"
        case .to: "to"
        case .via1: "via1"
        case .via2: "via2"
        case .viaNew: "viaNew"
        case .transfer(let stop): "transfer\(stop)"
        case .legNew: "legNew"
        }
    }

    var endpoint: TripEditorModel.Endpoint { self == .from ? .from : .to }

    var pickerTitle: String {
        switch self {
        case .from: "Start wählen"
        case .to: "Ziel wählen"
        case .via1, .via2, .viaNew: "Über"
        case .transfer: "Umstieg in"
        case .legNew: "Weiter nach"
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

    /// "23,50" for the inline fare field (empty when there is no price yet) – no grouping, see `EuroInput`.
    static func editableEuro(_ value: Double) -> String {
        EuroInput.editableText(value)
    }

    /// Parses de-AT input with comma or dot ("24,90", "24.90", "€ 1.024,50") → 24.9. Nil for empty/invalid/implausible
    /// values (`EuroInput.parse`).
    static func parseEuro(_ text: String) -> Double? {
        EuroInput.parse(text)
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

    /// Whether a favourite describes exactly the route currently in the form (a Kombi-Vorlage: every leg).
    func tripEdMatches(_ favorite: FavoriteRouteEntity) -> Bool {
        guard favorite.isRoundTrip == isRoundTrip else { return false }
        // MARK: trips – journeys match Kombi-Vorlagen leg by leg, single routes only single favourites.
        let favoriteLegs = favorite.legs
        guard isJourney == (favoriteLegs.count > 1) else { return false }
        if isJourney {
            guard favoriteLegs.count == legs.count else { return false }
            return favoriteLegs.indices.allSatisfy { index in
                let leg = favoriteLegs[index]
                return leg.mode == legs[index].mode
                    && Self.tripEdSameStop(leg.fromStationID, stops[index].station, leg.fromName, stops[index].resolvedName)
                    && Self.tripEdSameStop(leg.toStationID, stops[index + 1].station, leg.toName, stops[index + 1].resolvedName)
            }
        }
        guard favorite.modeRaw == mode.rawValue else { return false }
        guard tripEdViaMatches(favorite) else { return false }   // MARK: via
        return Self.tripEdSameStop(favorite.fromStationID, fromStation, favorite.fromName, resolvedFromName)
            && Self.tripEdSameStop(favorite.toStationID, toStation, favorite.toName, resolvedToName)
    }

    // MARK: trips – the station picker's result, wherever it goes (start, destination, via, transfer, new leg).
    func tripEdApply(_ station: Station, for pick: TripEdPick) {
        switch pick {
        case .transfer(let stop): setStop(stop, station: station)
        case .legNew: appendLeg(to: station)
        case .from, .to: setStation(station, for: pick.endpoint)
        case .via1, .via2, .viaNew: _ = tripEdSetVia(station, for: pick)
        }
    }

    func tripEdApplyCustomName(_ name: String, for pick: TripEdPick) {
        switch pick {
        case .transfer(let stop): setCustomStop(stop, name: name)
        case .legNew: appendLeg(customName: name)
        case .from, .to: setCustomName(name, for: pick.endpoint)
        case .via1, .via2, .viaNew: break
        }
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

/// Press feedback for the editor's own tappable areas – the motion system's `.pressable` at card depth (98 %,
/// Motion.press / .release, a dim instead of the scale under Reduce Motion).
struct TripEdPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableButtonStyle(scale: Motion.Distance.pressScaleCard).makeBody(configuration: configuration)
    }
}
