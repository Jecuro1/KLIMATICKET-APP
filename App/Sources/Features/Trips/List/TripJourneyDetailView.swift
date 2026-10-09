import SwiftUI
import SwiftData
import MapKit
import KlimaCore

/// Reise-Detail ("Reise mit Etappen", docs/JOURNEYS.md): the total on the sky, the leg timeline (each leg opens its own
/// detail), km / CO₂ / legs / share tiles, a map with every leg in its mode's colour, the note and the journey's actions.
///
/// Motion (docs/MOTION.md): zooms out of its list row; the total counts in once; the cards rise in one short stagger; the
/// numeral condenses while scrolling and the bar title becomes the route.
struct TripJourneyDetailView: View {
    let journeyID: UUID
    /// Opens a leg's detail (pushed on the list's stack).
    var openLeg: (TripEntity) -> Void = { _ in }

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var legs: [TripEntity]
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var favorites: [FavoriteRouteEntity]

    @State private var isConfirmingDelete = false
    @State private var favoriteBurst = 0
    @State private var repeatTurns = 0
    @State private var mapCache = TripJourneyMapCache()
    @State private var condense = ScrollCondense()
    @State private var showsRouteTitle = false

    init(journeyID: UUID, openLeg: @escaping (TripEntity) -> Void = { _ in }) {
        self.journeyID = journeyID
        self.openLeg = openLeg
        let id: UUID? = journeyID
        _legs = Query(filter: #Predicate<TripEntity> { $0.journeyID == id && $0.deletedAt == nil },
                      sort: [SortDescriptor(\TripEntity.legIndex), SortDescriptor(\TripEntity.createdAt)])
    }

    var body: some View {
        Group {
            if legs.isEmpty {
                ContentUnavailableView("Reise nicht mehr da", systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text("Diese Reise wurde gelöscht."))
            } else {
                content
            }
        }
        .ambientBackground()
        .navigationTitle(showsRouteTitle ? TripListActions.journeyTitle(legs) : "Reise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !legs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bearbeiten") { actions.edit(legs[0]) }
                }
            }
        }
        .confirmationDialog("Reise löschen?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Reise löschen", role: .destructive) { deleteJourney() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("\(TripListActions.journeyTitle(legs)) mit \(TripJourneyFormat.legCount(legs.count)) · \(Format.euroPrecise(totalValue)) wird aus deiner Bilanz entfernt.")
        }
    }

    private var content: some View {
        let map = mapCache.value(for: legs, app: app)
        return ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                hero
                    .padding(.bottom, Theme.Spacing.xs)
                    .heroCondense(condense, minScale: 0.86, fadeTo: 0.2)
                    .reveal(.focus)
                timelineCard
                    .reveal(order: 1)
                tiles
                    .reveal(order: 2)
                if let map {
                    TripJourneyMap(route: map)
                        .id(map.identity)
                        .reveal(.fade, order: 3)
                }
                if !note.isEmpty {
                    noteCard
                        .reveal(order: 4)
                }
                actionButtons
                    .reveal(order: 5)
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .tracksScrollCondense(condense, distance: 200)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 230
        } action: { _, isPast in
            if showsRouteTitle != isPast { showsRouteTitle = isPast }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .revealScope()
    }

    // MARK: Derived

    private var first: TripEntity { legs[0] }
    private var totalValue: Double { legs.reduce(0) { $0 + $1.totalValue } }
    private var farePerDirection: Double { legs.reduce(0) { $0 + $1.fareEUR } }
    private var totalKm: Double { legs.reduce(0) { $0 + $1.totalDistanceKm } }
    private var co2Kg: Double { legs.reduce(0) { $0 + app.catalog.emissions.savedKg(km: $1.totalDistanceKm, mode: $1.mode) } }
    private var note: String { (legs.lazy.map(\.note).first { !$0.isEmpty } ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private var actions: TripListActions { TripListActions(app: app, context: context) }
    private var isFavorite: Bool { actions.existingFavorite(forJourney: legs, in: favorites) != nil }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Kicker(text: TripListFormat.detailDateLine(first.date))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("€")
                    .font(Theme.Typography.priceNumeral)
                    .foregroundStyle(Theme.textSecondary)
                CountUpText(value: totalValue, delay: 0.1) { Format.number($0, decimals: 2) }
                    .font(Theme.Typography.hero.monospacedDigit())
                    .fontWeight(numeralWeight)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xs) { captionItems }
                VStack(spacing: Theme.Spacing.xs) { captionItems }
            }
            if first.category != nil || legs.contains(where: \.isInduced) {
                HStack(spacing: Theme.Spacing.xs) {
                    if let category = first.category {
                        MetaCategoryPill(title: category.displayName, symbol: category.symbolName,
                                         color: MetaCategoryStyle.color(category))
                    }
                    if legs.contains(where: \.isInduced) {
                        MetaCategoryPill(title: MetaCategoryStyle.inducedTitle, symbol: MetaCategoryStyle.inducedSymbol,
                                         color: MetaCategoryStyle.inducedColor)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wert dieser Reise")
        .accessibilityValue("\(Format.euroPrecise(totalValue)), \(TripJourneyFormat.legCount(legs.count))\(first.isRoundTrip ? ", hin und retour" : ""), \(TripListFormat.detailDateLine(first.date))")
    }

    @ViewBuilder
    private var captionItems: some View {
        TripListPill(title: TripJourneyFormat.legCount(legs.count), symbol: "point.3.connected.trianglepath.dotted",
                     foreground: Theme.accentText, fill: Theme.accent)
        if first.isRoundTrip {
            TripListPill(title: "Hin & Retour", symbol: "arrow.left.arrow.right")
        }
        Text(first.isRoundTrip ? "2 × \(Format.euroPrecise(farePerDirection)) Normalpreis" : "Normalpreis · eine Richtung")
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
    }

    private var numeralWeight: Font.Weight {
        if legibilityWeight == .bold || colorSchemeContrast == .increased { return .regular }
        return colorScheme == .light ? .light : .thin
    }

    // MARK: Timeline

    /// ◯ Von · [leg] · ● Umstieg · [leg] · … · ● Nach – every leg opens its own detail.
    private var timelineCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    TripJourneyModeStrip(modes: legs.map(\.mode))
                    Spacer(minLength: Theme.Spacing.xs)
                    Text(meta)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
                VStack(alignment: .leading, spacing: 0) {
                    TripJourneyStopRow(caption: "Von", name: first.fromName, kind: .start, color: Theme.modeColor(first.mode))
                    ForEach(Array(legs.enumerated()), id: \.element.id) { index, leg in
                        TripJourneyLegRow(leg: leg, index: index, count: legs.count) { openLeg(leg) }
                        if index < legs.count - 1 {
                            TripJourneyStopRow(caption: "Umstieg", name: leg.toName, kind: .transfer,
                                               color: Theme.modeColor(legs[index + 1].mode))
                        }
                    }
                    TripJourneyStopRow(caption: "Nach", name: legs[legs.count - 1].toName, kind: .end, color: Theme.summit)
                }
                if first.isRoundTrip {
                    Label("Zurück auf demselben Weg – jede Etappe zählt doppelt", systemImage: "arrow.uturn.backward")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    /// "632 km pro Richtung · 2. Klasse"
    private var meta: String {
        var parts: [String] = []
        let km = legs.reduce(0) { $0 + $1.distanceKm }
        if km > 0 { parts.append("\(Format.km(km)) pro Richtung") }
        if legs.contains(where: { $0.mode == .train || $0.mode == .sBahn }) { parts.append(first.travelClass.displayName) }
        if first.companions > 0 { parts.append(first.companions == 1 ? "+ 1 Person" : "+ \(first.companions) Personen") }
        return parts.joined(separator: " · ")
    }

    // MARK: Tiles

    @ViewBuilder
    private var tiles: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Theme.Spacing.s) {
                distanceTile
                co2Tile
                legsTile
                shareTile
            }
        } else {
            Grid(horizontalSpacing: Theme.Spacing.s, verticalSpacing: Theme.Spacing.s) {
                GridRow {
                    distanceTile
                    co2Tile
                }
                GridRow {
                    legsTile
                    shareTile
                }
            }
        }
    }

    private var distanceTile: some View {
        StatTile(value: totalKm > 0 ? Format.number(totalKm, decimals: totalKm < 10 ? 1 : 0) : "–", unit: totalKm > 0 ? "km" : nil,
                 label: "Distanz", symbol: "point.topleft.down.to.point.bottomright.curvepath", color: Theme.accentSecondary)
    }

    private var co2Tile: some View {
        StatTile(value: Format.number(co2Kg, decimals: co2Kg < 10 ? 1 : 0), unit: "kg", label: "CO₂ gespart",
                 symbol: "leaf.fill", color: Theme.eco)
    }

    private var legsTile: some View {
        StatTile(value: "\(legs.count)", unit: nil, label: "Etappen", symbol: "point.3.connected.trianglepath.dotted",
                 color: Theme.accent)
    }

    private var shareTile: some View {
        var value = "–"
        var unit: String?
        // Against the own share of the ticket this journey counts towards (as the trip detail).
        if let share = tickets.first(where: { $0.period.contains(first.date) })?.ownShare, share > 0 {
            let percent = totalValue / share * 100
            value = Format.number(percent, decimals: percent < 10 ? 1 : 0)
            unit = "%"
        }
        return StatTile(value: value, unit: unit, label: "Anteil am Ticket", symbol: "ticket.fill", color: Theme.summit)
    }

    // MARK: Note

    private var noteCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Kicker(text: "Notiz")
                }
                Text(note)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private var actionButtons: some View {
        VStack(spacing: Theme.Spacing.s) {
            Button {
                repeatTurns += 1
                actions.repeatJourneyToday(legs)
            } label: {
                Label {
                    Text("Heute nochmal fahren · \(Format.euroPrecise(totalValue))")
                } icon: {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, value: repeatTurns)
                        .symbolEffectsRemoved(reduceMotion || MotionPolicy.isStatic)
                }
            }
            .buttonStyle(.primary)

            HStack(spacing: Theme.Spacing.s) {
                Button {
                    actions.edit(first)
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    let was = isFavorite
                    withMotion(Motion.bouncy) {
                        actions.addFavorite(journey: legs, favorites: favorites)
                        if !was { favoriteBurst += 1 }
                    }
                } label: {
                    Label {
                        Text(isFavorite ? "Ist Vorlage" : "Als Vorlage")
                            .contentTransition(.interpolate)
                    } icon: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(Theme.gold)
                            .symbolReplaceTransition()
                            .symbolBounce(on: favoriteBurst)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isFavorite)
                .celebrationBurst(trigger: favoriteBurst, colors: [Theme.gold, Theme.dawn, Theme.summit])
                .accessibilityHint("Speichert alle Etappen als Kombi-Vorlage für die Schnellerfassung")
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Reise löschen", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.negative)
                    .padding(.vertical, Theme.Spacing.xs)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private func deleteJourney() {
        actions.deleteJourney(legs)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            dismiss()
        }
    }
}

// MARK: - Timeline rows

/// A stop of the journey timeline: ring (start), ring in the next leg's colour (transfer) or summit dot (end).
private struct TripJourneyStopRow: View {
    enum Kind { case start, transfer, end }

    let caption: String
    let name: String
    let kind: Kind
    let color: Color

    @ScaledMetric(relativeTo: .title3) private var dotTop: CGFloat = 28

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 3) {
                TripJourneyRail()
                    .frame(height: max(0, dotTop - 3))
                    .opacity(kind == .start ? 0 : 1)
                dot
                TripJourneyRail()
                    .frame(maxHeight: .infinity)
                    .opacity(kind == .end ? 0 : 1)
            }
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Text(name)
                    .font(kind == .transfer ? .body.weight(.semibold) : .title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, kind == .end ? 0 : Theme.Spacing.xs)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var dot: some View {
        switch kind {
        case .start, .transfer:
            Circle()
                .strokeBorder(color, lineWidth: 2.5)
                .frame(width: 12, height: 12)
        case .end:
            Circle()
                .fill(Theme.summit)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Theme.summit.opacity(0.25), lineWidth: 4))
        }
    }
}

/// A leg between two stops: the rail in the leg's colour · mode plate · "Zug · 612 km" · price › (opens the leg).
private struct TripJourneyLegRow: View {
    let leg: TripEntity
    let index: Int
    let count: Int
    var onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Capsule()
                .fill(Theme.modeColor(leg.mode).gradient)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 5)
                .accessibilityHidden(true)
            Button(action: onOpen) {
                HStack(spacing: Theme.Spacing.s) {
                    ModeIcon(mode: leg.mode, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(leg.mode.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            if let badge = TripListFormat.badge(for: leg.mode), badge != leg.mode.displayName {
                                TripListModeBadge(text: badge)
                            }
                        }
                        Text(legMeta)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: Theme.Spacing.xs)
                    Text(Format.euroPrecise(leg.fareEUR))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.surfaceSecondary.opacity(0.55), in: .rect(cornerRadius: Theme.Radius.chip, style: .continuous))
                .contentShape(.rect(cornerRadius: Theme.Radius.chip))
            }
            .buttonStyle(.pressableCard)
            .padding(.vertical, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Etappe \(index + 1) von \(count): \(leg.mode.displayName), \(leg.fromName) nach \(leg.toName)")
        .accessibilityValue("\(Format.euroPrecise(leg.fareEUR)) pro Richtung")
        .accessibilityHint("Zeigt die Details der Etappe")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { onOpen() }
    }

    /// "612 km · über Salzburg · Eigener Preis"
    private var legMeta: String {
        var parts: [String] = []
        if leg.distanceKm > 0 { parts.append(Format.km(leg.distanceKm)) }
        if let via = ViaText.subtitle(leg.via) { parts.append(via) }
        if leg.isFareManual { parts.append("Eigener Preis") }
        return parts.isEmpty ? "Etappe \(index + 1)" : parts.joined(separator: " · ")
    }
}

private struct TripJourneyRail: View {
    var body: some View {
        TripJourneyLine()
            .stroke(Theme.textTertiary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 4]))
            .frame(width: 2)
    }
}

private struct TripJourneyLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

// MARK: - Map

/// Stops of the journey on the map, one polyline per leg in its mode's colour.
struct TripJourneyMapRoute {
    struct Leg {
        var mode: TransportMode
        var path: [CLLocationCoordinate2D]
    }

    var legs: [Leg]
    var start: (label: String, coordinate: CLLocationCoordinate2D)
    var end: (label: String, coordinate: CLLocationCoordinate2D)
    var transfers: [(label: String, coordinate: CLLocationCoordinate2D)]
    var startMode: TransportMode

    var allPoints: [CLLocationCoordinate2D] { legs.flatMap(\.path) }
    var identity: String { allPoints.map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|") }
}

/// Resolves the stations once per version of the legs (ids + `updatedAt`), not on every body pass.
@MainActor
final class TripJourneyMapCache {
    private var key: [String] = []
    private var route: TripJourneyMapRoute?

    func value(for legs: [TripEntity], app: AppState) -> TripJourneyMapRoute? {
        let newKey = legs.map { "\($0.id)|\($0.updatedAt.timeIntervalSince1970)" }
        if newKey == key { return route }
        key = newKey
        route = Self.make(legs, stations: app.stations)
        return route
    }

    private static func make(_ legs: [TripEntity], stations: StationIndex) -> TripJourneyMapRoute? {
        func find(_ id: String?, _ name: String) -> Station? { id.flatMap { stations.station(id: $0) } ?? stations.station(named: name) }
        func coordinate(_ station: Station) -> CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon) }
        var mapped: [TripJourneyMapRoute.Leg] = []
        var transfers: [(label: String, coordinate: CLLocationCoordinate2D)] = []
        var startPoint: (String, CLLocationCoordinate2D)?
        var endPoint: (String, CLLocationCoordinate2D)?
        for (index, leg) in legs.enumerated() {
            // A leg without known stations (a custom place) is left out of the map; the others still show.
            guard let a = find(leg.fromStationID, leg.fromName), let b = find(leg.toStationID, leg.toName), a.id != b.id else { continue }
            let vias = leg.via.compactMap { find($0.stationID, $0.name) }
            mapped.append(.init(mode: leg.mode, path: ([a] + vias + [b]).map(coordinate)))
            if index == 0 { startPoint = (TripRow.short(leg.fromName), coordinate(a)) }
            if index == legs.count - 1 { endPoint = (TripRow.short(leg.toName), coordinate(b)) }
            if index < legs.count - 1 { transfers.append((TripRow.short(leg.toName), coordinate(b))) }
        }
        guard !mapped.isEmpty else { return nil }
        let start = startPoint ?? ("", mapped[0].path[0])
        let end = endPoint ?? ("", mapped[mapped.count - 1].path[mapped[mapped.count - 1].path.count - 1])
        return TripJourneyMapRoute(legs: mapped, start: start, end: end, transfers: transfers, startMode: legs[0].mode)
    }
}

/// Static, rounded map card: every leg in its mode's colour, the transfers as dots, start and destination as markers.
struct TripJourneyMap: View {
    let route: TripJourneyMapRoute

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            ForEach(Array(route.legs.enumerated()), id: \.offset) { _, leg in
                MapPolyline(coordinates: leg.path)
                    .stroke(Theme.modeColor(leg.mode), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            ForEach(Array(route.transfers.enumerated()), id: \.offset) { _, stop in
                Annotation(stop.label, coordinate: stop.coordinate, anchor: .center) {
                    TripListViaMapDot()
                }
            }
            if !route.start.label.isEmpty {
                Marker(route.start.label, systemImage: route.startMode.symbolName, coordinate: route.start.coordinate)
                    .tint(Theme.modeColor(route.startMode))
            }
            if !route.end.label.isEmpty {
                Marker(route.end.label, systemImage: "flag.fill", coordinate: route.end.coordinate)
                    .tint(Theme.summit)
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Karte der Reise")
        .accessibilityValue("\(route.start.label) nach \(route.end.label)\(route.transfers.isEmpty ? "" : ", " + (TripJourneyFormat.transfers(route.transfers.map(\.label)) ?? ""))")
    }

    /// Frames every stop with room for the marker balloons above them.
    private var region: MKCoordinateRegion {
        let points = route.allPoints
        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        let minLat = lats.min() ?? 47.5, maxLat = lats.max() ?? 47.5
        let minLon = lons.min() ?? 13, maxLon = lons.max() ?? 13
        let latDelta = max((maxLat - minLat) * 1.8, 0.03)
        let lonDelta = max((maxLon - minLon) * 1.45, 0.03)
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 + latDelta * 0.08, longitude: (minLon + maxLon) / 2)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }
}
