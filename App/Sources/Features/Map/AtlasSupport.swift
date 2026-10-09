import SwiftUI
import MapKit
import KlimaCore

// Shared building blocks of "Meine Österreich-Karte": data shaping, formatting, map styling and the state stamps.

// MARK: - Scope & data

/// Which trips the map shows.
enum AtlasScope: Hashable {
    case ticket(UUID)
    case allYears
}

/// Turns SwiftData entities into map-ready values (presentation shaping only – all logic lives in `KlimaCore.Atlas`).
@MainActor
enum AtlasData {
    static func records(for scope: AtlasScope, trips: [TripEntity], tickets: [TicketEntity]) -> [TripRecord] {
        let live = trips.filter { $0.deletedAt == nil }
        switch scope {
        case .allYears:
            return live.map(\.record)
        case .ticket(let id):
            guard let ticket = tickets.first(where: { $0.id == id }) else { return live.map(\.record) }
            let period = ticket.period
            return live.filter { period.contains($0.date) }.map(\.record)
        }
    }

    static func summary(_ records: [TripRecord], mode: TransportMode?, stations: StationIndex) -> AtlasSummary {
        let filtered = mode.map { m in records.filter { $0.mode == m } } ?? records
        return Atlas.summarize(filtered, stations: stations)
    }

    /// Modes present in the selection, most legs first (filter chips).
    static func modes(in records: [TripRecord]) -> [TransportMode] {
        var legs: [TransportMode: Int] = [:]
        for r in records { legs[r.mode, default: 0] += r.legs }
        return legs.sorted { ($0.value, $1.key.rawValue) > ($1.value, $0.key.rawValue) }.map(\.key)
    }

    /// Default scope: the ticket the rest of the app shows, otherwise all trips.
    static func defaultScope(tickets: [TicketEntity], preferred: UUID?, selected: UUID?) -> AtlasScope {
        if let preferred, tickets.contains(where: { $0.id == preferred }) { return .ticket(preferred) }
        if let ticket = Analytics.activeTicket(in: tickets, selectedID: selected) { return .ticket(ticket.id) }
        return .allYears
    }

    static func ticket(for scope: AtlasScope, in tickets: [TicketEntity]) -> TicketEntity? {
        guard case .ticket(let id) = scope else { return nil }
        return tickets.first { $0.id == id }
    }

    /// Eyebrow for the panel ("Ticketjahr 2026/27", "Alle Ticketjahre").
    static func scopeLabel(_ scope: AtlasScope, tickets: [TicketEntity]) -> String {
        guard let ticket = ticket(for: scope, in: tickets) else { return "Alle Ticketjahre" }
        return "Ticketjahr \(AtlasFormat.ticketYear(ticket.period))"
    }
}

// MARK: - Formatting

enum AtlasFormat {
    /// "2026/27" (or "2026" when the period lies within one calendar year).
    static func ticketYear(_ period: TicketPeriod) -> String {
        let cal = Calendar.vienna
        let y1 = cal.component(.year, from: period.start)
        let y2 = cal.component(.year, from: period.end)
        guard y1 != y2 else { return String(y1) }
        return "\(y1)/\(String(format: "%02d", y2 % 100))"
    }

    static func legs(_ n: Int) -> String { n == 1 ? "1 Fahrt" : "\(Format.number(Double(n))) Fahrten" }
    static func visits(_ n: Int) -> String { n == 1 ? "1 Besuch" : "\(Format.number(Double(n))) Besuche" }
    static func stations(_ n: Int) -> String { n == 1 ? "1 Bahnhof" : "\(n) Bahnhöfe" }

    /// "St. Anton ⇄ Landeck-Zams"
    static func routeTitle(_ route: AtlasRoute) -> String {
        "\(TripRow.short(route.from.name)) ⇄ \(TripRow.short(route.to.name))"
    }

    static func unmappedTitle(_ route: AtlasUnmappedRoute) -> String {
        "\(TripRow.short(route.fromName)) ⇄ \(TripRow.short(route.toName))"
    }

    /// "47,26° N"
    static func latitude(_ value: Double) -> String {
        "\(Format.number(abs(value), decimals: 2))° \(value >= 0 ? "N" : "S")"
    }

    /// "11,40° O"
    static func longitude(_ value: Double) -> String {
        "\(Format.number(abs(value), decimals: 2))° \(value >= 0 ? "O" : "W")"
    }

    /// Coordinate that matters for an extreme point (latitude for north/south, longitude for west/east).
    static func coordinate(for direction: AtlasCompass, of place: AtlasPlace) -> String {
        switch direction {
        case .north, .south: latitude(place.location.latitude)
        case .west, .east: longitude(place.location.longitude)
        }
    }

    /// "nach Tirol", "ins Burgenland", "in die Steiermark".
    static func excursion(to state: FederalState) -> String {
        switch state {
        case .burgenland: "ins Burgenland"
        case .steiermark: "in die Steiermark"
        default: "nach \(state.displayName)"
        }
    }

    static func stateSubtitle(_ place: AtlasPlace) -> String {
        guard let state = place.state else { return "Bahnhof" }
        return state == .foreign ? "Ausland · Grenzbahnhof" : state.displayName
    }
}

// MARK: - Geo bridging

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension AtlasRegion {
    var mkRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude),
                           span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }
}

extension AtlasRoute {
    var coordinates: [CLLocationCoordinate2D] { path.map(\.coordinate) }
}

// MARK: - Map look

/// Map base layer: calm "Karte" (muted standard style, so the routes pop) or "Satellit" (hybrid imagery with labels).
enum AtlasMapLook: String, CaseIterable, Identifiable {
    case standard
    case satellite

    var id: String { rawValue }
    var title: String { self == .standard ? "Karte" : "Satellit" }
    var symbol: String { self == .standard ? "map" : "globe.europe.africa.fill" }

    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)
        case .satellite: .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false)
        }
    }
}

/// Line width / opacity by frequency – shared by the full map and the preview card.
enum AtlasLineStyle {
    static func width(_ route: AtlasRoute, scale: CGFloat = 1) -> CGFloat { (3 + 4.5 * CGFloat(route.weight)) * scale }
    static func opacity(_ route: AtlasRoute) -> Double { 0.72 + 0.28 * route.weight }

    /// Thin halo under every line so routes read on both the muted map and satellite imagery.
    static func casing(look: AtlasMapLook, scheme: ColorScheme) -> Color {
        if look == .satellite { return Color.black.opacity(0.45) }
        return scheme == .dark ? Color.black.opacity(0.32) : Color.white.opacity(0.9)
    }

    static func round(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

// MARK: - State stamps

/// The nine federal states, west → east, as compact stamps – filled when visited (with a check mark in the
/// accessible variant, never colour alone). Large accessibility sizes switch to a labelled grid.
struct AtlasStateStamps: View {
    let visited: Set<FederalState>
    var height: CGFloat = 30

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.xs), GridItem(.flexible())],
                          alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(Atlas.austrianStates) { state in
                        AtlasStateChip(state: state, isVisited: visited.contains(state))
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(Atlas.austrianStates) { state in
                        stamp(state, isVisited: visited.contains(state))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bundesländer")
        .accessibilityValue(accessibilityValue)
    }

    private func stamp(_ state: FederalState, isVisited: Bool) -> some View {
        Text(Atlas.abbreviation(state))
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(isVisited ? AtlasStateStamps.visitedInk : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                if isVisited {
                    Capsule().fill(LinearGradient(colors: [Theme.pine, Theme.pine.mix(with: Theme.glacier, by: 0.28)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    Capsule().fill(Theme.textTertiary.opacity(0.10))
                }
            }
            .overlay {
                if !isVisited {
                    Capsule().strokeBorder(Theme.textTertiary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                }
            }
    }

    private var accessibilityValue: String {
        let done = Atlas.austrianStates.filter { visited.contains($0) }.map(\.displayName)
        let open = Atlas.austrianStates.filter { !visited.contains($0) }.map(\.displayName)
        var parts = ["\(done.count) von 9 bereist"]
        if !done.isEmpty { parts.append("bereist: " + done.joined(separator: ", ")) }
        if !open.isEmpty { parts.append("noch offen: " + open.joined(separator: ", ")) }
        return parts.joined(separator: ". ")
    }

    /// Text on the filled stamp (white on pine in light, deep navy on the bright dark-mode pine).
    static let visitedInk = Color(light: "#FFFFFF", dark: "#04261C")
}

/// Full-name state chip (details sheet, accessibility sizes).
struct AtlasStateChip: View {
    let state: FederalState
    let isVisited: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isVisited ? "checkmark.circle.fill" : "circle.dashed")
                .font(.footnote.weight(.bold))
            Text(state.displayName)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isVisited ? Theme.positiveText : Theme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isVisited ? Theme.positive.opacity(0.15) : Theme.textTertiary.opacity(0.08), in: .capsule)
        .overlay(Capsule().strokeBorder(isVisited ? Theme.positive.opacity(0.35) : Theme.separator, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.displayName)
        .accessibilityValue(isVisited ? "bereist" : "noch nicht bereist")
    }
}

/// Small coloured dot + label used in legends and list rows.
struct AtlasModeDot: View {
    let mode: TransportMode
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(Theme.modeColor(mode))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
            .accessibilityHidden(true)
    }
}
