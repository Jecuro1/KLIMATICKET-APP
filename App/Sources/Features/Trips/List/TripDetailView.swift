import SwiftUI
import SwiftData
import MapKit
import KlimaCore

/// Fahrt-Detail: big value on the sky, route hero, stat tiles, map, fare explanation, note and actions.
struct TripDetailView: View {
    let trip: TripEntity

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var favorites: [FavoriteRouteEntity]

    @State private var shownValue: Double
    @State private var revealed: Bool
    @State private var isConfirmingDelete = false
    @State private var isShowingFareInfo = false
    @State private var successTick = 0
    @State private var warningTick = 0

    init(trip: TripEntity) {
        self.trip = trip
        let settled = LaunchMode.isScreenshot
        _shownValue = State(initialValue: settled ? trip.totalValue : 0)
        _revealed = State(initialValue: settled)
    }

    var body: some View {
        let info = makeInfo()
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                hero
                    .padding(.bottom, Theme.Spacing.xs)
                Group {
                    routeCard(info)
                    tiles(info)
                    if let route = info.route {
                        TripListDetailMap(route: route, mode: trip.mode)
                    }
                    fareCard(info)
                    if !trimmedNote.isEmpty {
                        noteCard
                    }
                    actionButtons(info)
                }
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 18)
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .ambientBackground()
        .navigationTitle("Fahrt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bearbeiten") { actions.edit(trip) }
            }
        }
        .confirmationDialog("Fahrt löschen?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Fahrt löschen", role: .destructive) { deleteTrip() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("\(TripListFormat.routeTitle(trip.fromName, trip.toName)) · \(Format.euroPrecise(trip.totalValue)) wird aus deiner Bilanz entfernt.")
        }
        .sensoryFeedback(.success, trigger: successTick, condition: { _, _ in hapticsEnabled })
        .sensoryFeedback(.warning, trigger: warningTick, condition: { _, _ in hapticsEnabled })
        .onAppear(perform: animateIn)
        .onChange(of: trip.totalValue) { _, newValue in
            withAnimation(.spring(duration: 0.6)) { shownValue = newValue }
        }
    }

    // MARK: Hero

    /// Apple-Weather-style thin numeral straight on the sky.
    private var hero: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Kicker(text: TripListFormat.detailDateLine(trip.date))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("€")
                    .font(Theme.Typography.priceNumeral)
                    .foregroundStyle(Theme.textSecondary)
                Text(Format.number(shownValue, decimals: 2))
                    .font(Theme.Typography.hero)
                    .fontWeight(numeralWeight)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: shownValue))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            heroCaption
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wert dieser Fahrt")
        .accessibilityValue(heroAccessibilityValue)
    }

    private var heroCaption: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) {
                heroCaptionItems
            }
            VStack(spacing: Theme.Spacing.xs) {
                heroCaptionItems
            }
        }
    }

    @ViewBuilder
    private var heroCaptionItems: some View {
        if trip.isRoundTrip {
            TripListPill(title: "Hin & Retour", symbol: "arrow.left.arrow.right")
        }
        Text(heroCaptionText)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
    }

    private var heroCaptionText: String {
        trip.isRoundTrip ? "2 × \(Format.euroPrecise(trip.fareEUR)) Normalpreis" : "Normalpreis · eine Richtung"
    }

    /// Ultralight like Apple Weather, sturdier for Bold Text / Increase Contrast and glare in light mode.
    private var numeralWeight: Font.Weight {
        if legibilityWeight == .bold || colorSchemeContrast == .increased { return .regular }
        return colorScheme == .light ? .light : .thin
    }

    private var heroAccessibilityValue: String {
        var text = Format.euroPrecise(trip.totalValue)
        if trip.isRoundTrip { text += ", hin und retour, 2 mal \(Format.euroPrecise(trip.fareEUR))" }
        return "\(text), \(TripListFormat.detailDateLine(trip.date))"
    }

    // MARK: Route

    private func routeCard(_ info: TripListDetailInfo) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    ModeIcon(mode: trip.mode, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(trip.mode.displayName)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.textPrimary)
                            if let badge = TripListFormat.badge(for: trip.mode), badge != trip.mode.displayName {
                                TripListModeBadge(text: badge)
                            }
                        }
                        Text(routeMeta)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
                VStack(alignment: .leading, spacing: 0) {
                    TripListDetailStop(caption: "Von", name: trip.fromName,
                                       subtitle: TripListFormat.stationSubtitle(info.fromStation),
                                       isOrigin: true, color: Theme.modeColor(trip.mode))
                    TripListDetailStop(caption: "Nach", name: trip.toName,
                                       subtitle: TripListFormat.stationSubtitle(info.toStation),
                                       isOrigin: false, color: Theme.modeColor(trip.mode))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var routeMeta: String {
        var parts: [String] = []
        if trip.distanceKm > 0 { parts.append("\(Format.km(trip.distanceKm)) pro Richtung") }
        if trip.mode == .train || trip.mode == .sBahn { parts.append(trip.travelClass.displayName) }
        if trip.companions > 0 { parts.append(trip.companions == 1 ? "+ 1 Person" : "+ \(trip.companions) Personen") }
        return parts.isEmpty ? "Öffis" : parts.joined(separator: " · ")
    }

    // MARK: Tiles

    @ViewBuilder
    private func tiles(_ info: TripListDetailInfo) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Theme.Spacing.s) {
                distanceTile
                co2Tile(info)
                perKmTile
                shareTile(info)
            }
        } else {
            Grid(horizontalSpacing: Theme.Spacing.s, verticalSpacing: Theme.Spacing.s) {
                GridRow {
                    distanceTile
                    co2Tile(info)
                }
                GridRow {
                    perKmTile
                    shareTile(info)
                }
            }
        }
    }

    private var distanceTile: some View {
        let km = trip.totalDistanceKm
        return StatTile(value: km > 0 ? Format.number(km, decimals: km < 10 ? 1 : 0) : "–",
                        unit: km > 0 ? "km" : nil,
                        label: "Distanz",
                        symbol: "point.topleft.down.to.point.bottomright.curvepath",
                        color: Theme.accentSecondary)
    }

    private func co2Tile(_ info: TripListDetailInfo) -> some View {
        let kg = info.co2Kg
        return StatTile(value: Format.number(kg, decimals: kg < 10 ? 1 : 0),
                        unit: "kg",
                        label: "CO₂ gespart",
                        symbol: "leaf.fill",
                        color: Theme.eco)
    }

    private var perKmTile: some View {
        let hasDistance = trip.distanceKm > 0
        return StatTile(value: hasDistance ? Format.euroPrecise(trip.fareEUR / trip.distanceKm) : "–",
                        unit: hasDistance ? "/ km" : nil,
                        label: "Preis pro km",
                        symbol: "eurosign",
                        color: Theme.accent)
    }

    private func shareTile(_ info: TripListDetailInfo) -> some View {
        var value = "–"
        var unit: String?
        if let ticket = info.ticket, ticket.price > 0 {
            let percent = trip.totalValue / ticket.price * 100
            value = Format.number(percent, decimals: percent < 10 ? 1 : 0)
            unit = "%"
        }
        return StatTile(value: value, unit: unit, label: "Anteil am Ticket", symbol: "ticket.fill", color: Theme.summit)
    }

    // MARK: Fare

    private func fareCard(_ info: TripListDetailInfo) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        fareTitle
                        fareBadge(info)
                    }
                } else {
                    HStack(alignment: .center, spacing: 6) {
                        fareTitle
                        Spacer(minLength: Theme.Spacing.xs)
                        fareBadge(info)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.euroPrecise(trip.fareEUR))
                        .font(Theme.Typography.numberMedium)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("pro Richtung")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                if trip.isRoundTrip {
                    Text("2 × \(Format.euroPrecise(trip.fareEUR)) · Hin + Rück = \(Format.euroPrecise(trip.totalValue))")
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(fareExplanation(info))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fareTitle: some View {
        HStack(spacing: 6) {
            Kicker(text: "Normalpreis")
            Button {
                isShowingFareInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("So wird der Normalpreis berechnet")
            .popover(isPresented: $isShowingFareInfo) {
                Text(Copy.fareExplanation)
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Theme.Spacing.m)
                    .frame(width: 320)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    @ViewBuilder
    private func fareBadge(_ info: TripListDetailInfo) -> some View {
        if trip.isFareManual {
            TripListPill(title: "Eigener Preis", symbol: "pencil", foreground: Theme.summitText, fill: Theme.summit)
        } else if let estimate = info.estimate {
            if estimate.method == .officialTable && abs(estimate.fareEUR - trip.fareEUR) < 0.05 {
                TripListPill(title: "Offizieller ÖBB-Preis", symbol: "checkmark.seal.fill", foreground: Theme.positiveText, fill: Theme.positive)
            } else {
                TripListPill(title: "Geschätzt", symbol: "wand.and.stars", foreground: Theme.accentText, fill: Theme.accent)
            }
        } else {
            TripListPill(title: "Erfasster Preis", symbol: "checkmark.circle", foreground: Theme.accentText, fill: Theme.accent)
        }
    }

    private func fareExplanation(_ info: TripListDetailInfo) -> String {
        if trip.isFareManual {
            if let estimate = info.estimate {
                return "Diesen Preis hast du selbst eingetragen. Unsere Schätzung für die Strecke: \(Format.euroPrecise(estimate.fareEUR)) (\(estimate.explanation))."
            }
            return "Diesen Preis hast du selbst eingetragen."
        }
        if let estimate = info.estimate {
            if abs(estimate.fareEUR - trip.fareEUR) >= 0.05 {
                return "\(estimate.explanation) · aktuell geschätzt \(Format.euroPrecise(estimate.fareEUR))"
            }
            return estimate.explanation
        }
        return "Für diese Haltestelle liegen keine Tarifdaten vor – der Normalpreis stammt aus deiner Erfassung."
    }

    // MARK: Note

    private var trimmedNote: String { trip.note.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var noteCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Kicker(text: "Notiz")
                }
                Text(trimmedNote)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func actionButtons(_ info: TripListDetailInfo) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Button {
                repeatToday()
            } label: {
                Label("Heute nochmal fahren · \(Format.euroPrecise(trip.totalValue))", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.primary)

            HStack(spacing: Theme.Spacing.s) {
                Button {
                    actions.edit(trip)
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    addFavorite()
                } label: {
                    Label {
                        Text(favoriteButtonTitle(info))
                    } icon: {
                        Image(systemName: info.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(Theme.gold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(info.isFavorite)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Fahrt löschen", systemImage: "trash")
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

    private func favoriteButtonTitle(_ info: TripListDetailInfo) -> String {
        info.isFavorite ? "Ist Favorit" : "Als Favorit"
    }

    private var actions: TripListActions { TripListActions(app: app, context: context) }
    private var hapticsEnabled: Bool { app.settings.hapticsEnabled }

    private func repeatToday() {
        actions.repeatToday(trip)
        successTick += 1
    }

    private func addFavorite() {
        actions.addFavorite(trip, favorites: favorites)
        successTick += 1
    }

    private func deleteTrip() {
        actions.delete(trip)
        warningTick += 1
        // Give the warning haptic a beat before popping back to the list.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            dismiss()
        }
    }

    // MARK: Entrance

    private func animateIn() {
        guard !revealed || shownValue != trip.totalValue else { return }
        if reduceMotion || LaunchMode.isScreenshot {
            shownValue = trip.totalValue
            revealed = true
            return
        }
        withAnimation(.smooth(duration: 0.55)) { revealed = true }
        withAnimation(.spring(duration: 0.9, bounce: 0.12)) { shownValue = trip.totalValue }
    }

    // MARK: Derived data

    private func makeInfo() -> TripListDetailInfo {
        let stations = app.stations
        let fromStation = trip.fromStationID.flatMap { stations.station(id: $0) } ?? stations.station(named: trip.fromName)
        let toStation = trip.toStationID.flatMap { stations.station(id: $0) } ?? stations.station(named: trip.toName)

        var estimate: FareEstimate?
        var route: TripListDetailRoute?
        if let fromStation, let toStation, fromStation.id != toStation.id {
            // Re-run the estimator to explain the price (and to compare with manual prices).
            estimate = app.estimator.estimate(from: fromStation, to: toStation, mode: trip.mode,
                                              travelClass: trip.travelClass, discount: app.settings.defaultDiscount,
                                              date: trip.date)
            route = TripListDetailRoute(
                from: CLLocationCoordinate2D(latitude: fromStation.lat, longitude: fromStation.lon),
                to: CLLocationCoordinate2D(latitude: toStation.lat, longitude: toStation.lon),
                fromName: trip.fromName,
                toName: trip.toName,
                fromLabel: TripRow.short(trip.fromName),
                toLabel: TripRow.short(trip.toName),
                straightKm: fromStation.location.distanceKm(to: toStation.location)
            )
        }

        let ticket = tickets.first { $0.period.contains(trip.date) }
            ?? Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID)

        return TripListDetailInfo(
            fromStation: fromStation,
            toStation: toStation,
            estimate: estimate,
            route: route,
            ticket: ticket,
            co2Kg: app.catalog.emissions.savedKg(km: trip.totalDistanceKm, mode: trip.mode),
            isFavorite: actions.existingFavorite(for: trip, in: favorites) != nil
        )
    }
}

// MARK: - Supporting types

private struct TripListDetailInfo {
    var fromStation: Station?
    var toStation: Station?
    var estimate: FareEstimate?
    var route: TripListDetailRoute?
    var ticket: TicketEntity?
    var co2Kg: Double
    var isFavorite: Bool
}

private struct TripListDetailRoute {
    var from: CLLocationCoordinate2D
    var to: CLLocationCoordinate2D
    var fromName: String
    var toName: String
    var fromLabel: String
    var toLabel: String
    var straightKm: Double
}

/// One stop of the route hero: ring/dot on a dotted rail that lines up with the station name at any text size.
private struct TripListDetailStop: View {
    let caption: String
    let name: String
    let subtitle: String?
    let isOrigin: Bool
    let color: Color

    /// Distance from the top of the stop to the top of its dot (caption line + half the name line − dot radius).
    @ScaledMetric(relativeTo: .title3) private var dotTop: CGFloat = 28

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 3) {
                rail
                    .frame(height: max(0, dotTop - 3))
                    .opacity(isOrigin ? 0 : 1)
                dot
                rail
                    .frame(maxHeight: .infinity)
                    .opacity(isOrigin ? 1 : 0)
            }
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Text(name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.bottom, isOrigin ? Theme.Spacing.m : 0)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rail: some View {
        TripListVerticalLine()
            .stroke(Theme.textTertiary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 4]))
            .frame(width: 2)
    }

    @ViewBuilder
    private var dot: some View {
        if isOrigin {
            Circle()
                .strokeBorder(color, lineWidth: 2.5)
                .frame(width: 12, height: 12)
        } else {
            Circle()
                .fill(Theme.summit)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Theme.summit.opacity(0.25), lineWidth: 4))
        }
    }
}

private struct TripListVerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// Static, rounded MapKit card: both stations as markers joined by a route-gradient line.
private struct TripListDetailMap: View {
    let route: TripListDetailRoute
    let mode: TransportMode

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            MapPolyline(coordinates: [route.from, route.to])
                .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            Marker(route.fromLabel, systemImage: mode.symbolName, coordinate: route.from)
                .tint(Theme.modeColor(mode))
            Marker(route.toLabel, systemImage: "flag.fill", coordinate: route.to)
                .tint(Theme.summit)
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 1)
        }
        .overlay(alignment: .bottomLeading) { distanceChip }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Karte der Strecke")
        .accessibilityValue("\(route.fromName) nach \(route.toName), Luftlinie \(Format.km(route.straightKm))")
    }

    private var distanceChip: some View {
        Label("Luftlinie \(Format.km(route.straightKm))", systemImage: "scope")
            .labelStyle(.titleAndIcon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: .capsule)
            .padding(Theme.Spacing.s)
    }

    /// Frames both stations with room for the marker balloons above them.
    private var region: MKCoordinateRegion {
        let latDelta = max(abs(route.from.latitude - route.to.latitude) * 1.8, 0.03)
        let lonDelta = max(abs(route.from.longitude - route.to.longitude) * 1.45, 0.03)
        let center = CLLocationCoordinate2D(latitude: (route.from.latitude + route.to.latitude) / 2 + latDelta * 0.08,
                                            longitude: (route.from.longitude + route.to.longitude) / 2)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }
}
