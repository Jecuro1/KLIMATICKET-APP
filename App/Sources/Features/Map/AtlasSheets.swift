import SwiftUI
import KlimaCore

// MARK: - Route sheet

/// Opens when a route is tapped on the map: its value, numbers and all trips. Medium height keeps the map visible
/// (and tappable) above it, so tapping another route simply updates the sheet.
struct AtlasRouteSheet: View {
    let route: AtlasRoute
    let trips: [TripEntity]
    let ticketPrice: Double?
    let routeCount: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                AtlasRouteDetail(route: route, trips: trips, ticketPrice: ticketPrice, routeCount: routeCount)
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.top, Theme.Spacing.xxs)
                    .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(AtlasFormat.routeTitle(route))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Strecke")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
    }
}

/// Route content: hero value, share of the ticket price, key numbers and the trip list.
struct AtlasRouteDetail: View {
    let route: AtlasRoute
    let trips: [TripEntity]
    let ticketPrice: Double?
    let routeCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            header
            valueBlock
            tiles
            tripList
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            ModeIcon(mode: route.dominantMode, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Kicker(text: route.rank == 1 ? "Deine meistgefahrene Strecke" : "Platz \(route.rank) von \(routeCount)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(TripRow.short(route.from.name)) ⇄ \(TripRow.short(route.to.name))")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(modesLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var modesLine: String {
        let modes = route.modes.map(\.displayName).joined(separator: " · ")
        return "\(modes) · Luftlinie \(Format.km(route.straightKm))"
    }

    private var valueBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("€")
                    .font(.system(size: 30, weight: .light, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Text(Format.number(route.value, decimals: route.value >= 1000 ? 0 : 2))
                    .font(.system(size: 58, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text("Normalpreis-Wert aller Fahrten auf dieser Strecke")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            if let ticketPrice, ticketPrice > 0 {
                let share = route.value / ticketPrice
                ProgressRail(progress: min(share, 1), height: 6)
                    .padding(.top, Theme.Spacing.xxs)
                Text(share >= 1 ? "Allein diese Strecke hat dein Ticket schon bezahlt."
                                : "Allein diese Strecke deckt \(Format.percent(share)) deines Ticketpreises.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(share >= 1 ? Theme.positiveText : Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var tiles: some View {
        HStack(spacing: Theme.Spacing.xs) {
            AtlasMiniStat(value: Format.number(Double(route.legs)), label: route.legs == 1 ? "Fahrt" : "Fahrten",
                          symbol: "arrow.left.arrow.right", color: Theme.accent)
            AtlasMiniStat(value: Format.km(route.distanceKm), label: "gefahren", symbol: "road.lanes", color: Theme.dusk)
            AtlasMiniStat(value: Format.euroPrecise(route.value / Double(max(route.legs, 1))), label: "pro Fahrt",
                          symbol: "eurosign", color: Theme.summit)
        }
    }

    private var tripList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fahrten")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(dateRange)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                    TripRow(trip: trip)
                    if index < trips.count - 1 {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: 0.5)
                            .padding(.leading, 62)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.s + 2)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.formGroup, style: .continuous))
        }
    }

    private var dateRange: String {
        let first = Format.dayMonth(route.firstDate), last = Format.dayMonth(route.lastDate)
        return first == last ? first : "\(first) – \(last)"
    }
}

/// Compact number tile for sheets ("26 · Fahrten").
struct AtlasMiniStat: View {
    let value: String
    let label: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.14), in: .circle)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Details sheet

/// Everything the map can't say at a glance: the four extreme points (tap to fly there), all nine states,
/// border stations abroad, the full route ranking and the trips without coordinates.
struct AtlasDetailsSheet: View {
    let summary: AtlasSummary
    let scopeLabel: String
    /// Opens at full height scrolled to the route ranking (screenshots).
    var startsAtRoutes = false
    var onSelectRoute: (String) -> Void
    var onFocusPlace: (AtlasPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl - 4) {
                    if !summary.extremes.isEmpty {
                        extremesSection
                    }
                    statesSection
                    if !summary.abroadPlaces.isEmpty {
                        abroadSection
                    }
                    if !summary.routes.isEmpty {
                        routesSection
                    }
                    if !summary.unmapped.isEmpty {
                        unmappedSection
                    }
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .task {
                guard startsAtRoutes else { return }
                detent = .large
                try? await Task.sleep(for: .milliseconds(450))
                reader.scrollTo("routes", anchor: .top)
            }
            }
            .navigationTitle("Deine Karte")
            .navigationSubtitle(scopeLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    // MARK: Extremes

    private var extremesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            sectionTitle("Extrempunkte", trailing: "Tippen zum Hinfliegen")
            LazyVGrid(columns: gridColumns, spacing: Theme.Spacing.xs) {
                ForEach(AtlasCompass.allCases) { direction in
                    if let place = summary.extremes.place(direction) {
                        extremeTile(direction, place)
                    }
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs, alignment: .top), count: count)
    }

    private func extremeTile(_ direction: AtlasCompass, _ place: AtlasPlace) -> some View {
        Button {
            onFocusPlace(place)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack {
                    Image(systemName: direction.symbolName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 26, height: 26)
                        .background(Theme.accent.opacity(0.14), in: .circle)
                    Spacer(minLength: 4)
                    Text(AtlasFormat.coordinate(for: direction, of: place))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.bottom, 2)
                Text(direction.superlative)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(TripRow.short(place.name))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AtlasFormat.stateSubtitle(place))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Spacing.s + 2)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
            .contentShape(.rect(cornerRadius: Theme.Radius.tile))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(direction.superlative): \(place.name)")
        .accessibilityValue("\(AtlasFormat.coordinate(for: direction, of: place)), \(AtlasFormat.stateSubtitle(place))")
        .accessibilityHint("Zeigt den Bahnhof auf der Karte")
    }

    // MARK: States

    private var statesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            sectionTitle("Bundesländer", trailing: "\(summary.visitedStateCount) von 9")
            LazyVGrid(columns: gridColumns, spacing: Theme.Spacing.xs) {
                ForEach(Atlas.austrianStates) { state in
                    AtlasStateChip(state: state, isVisited: summary.visitedStates.contains(state))
                }
            }
            if summary.isAllAustria {
                note(symbol: "flag.checkered", tint: Theme.positive,
                     text: "Ganz Österreich! Du warst in allen neun Bundesländern unterwegs.")
            } else if let missing = Atlas.austrianStates.first(where: { !summary.visitedStates.contains($0) }) {
                note(symbol: "lightbulb.fill", tint: Theme.gold,
                     text: "Noch offen: \(missingStates). Wie wär’s mit einem Ausflug \(AtlasFormat.excursion(to: missing))?")
            }
        }
    }

    private var missingStates: String {
        Atlas.austrianStates.filter { !summary.visitedStates.contains($0) }.map(\.displayName).joined(separator: ", ")
    }

    // MARK: Abroad

    private var abroadSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            sectionTitle("Über die Grenze", trailing: nil)
            note(symbol: "globe.europe.africa.fill", tint: Theme.dusk,
                 text: "Du warst in \(summary.abroadPlaces.map(\.name).joined(separator: ", ")). "
                    + "Das KlimaTicket Ö gilt im Ausland bis zu den Gemeinschaftsbahnhöfen – etwa "
                    + "\(Atlas.borderStations.prefix(4).joined(separator: ", ")) oder Sopron.")
        }
    }

    // MARK: Routes

    private var routesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            sectionTitle("Alle Strecken", trailing: "\(summary.routes.count)")
                .id("routes")
            LazyVStack(spacing: 0) {
                ForEach(summary.routes) { route in
                    Button {
                        onSelectRoute(route.id)
                    } label: {
                        routeRow(route)
                    }
                    .buttonStyle(.plain)
                    if route.id != summary.routes.last?.id {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: 0.5)
                            .padding(.leading, 78)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.s + 2)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.formGroup, style: .continuous))
        }
    }

    private func routeRow(_ route: AtlasRoute) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("\(route.rank)")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(route.rank == 1 ? Theme.summitText : Theme.textTertiary)
                .frame(minWidth: 20, alignment: .leading)
            ModeIcon(mode: route.dominantMode, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(AtlasFormat.routeTitle(route))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(AtlasFormat.legs(route.legs)) · \(Format.km(route.distanceKm))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            Text(Format.euro(route.value, decimals: 0))
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, Theme.Spacing.s - 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Platz \(route.rank): \(route.from.name) und \(route.to.name)")
        .accessibilityValue("\(AtlasFormat.legs(route.legs)), \(Format.euro(route.value, decimals: 0)), \(Format.km(route.distanceKm))")
        .accessibilityHint("Zeigt die Strecke auf der Karte")
    }

    // MARK: Unmapped

    private var unmappedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            sectionTitle("Ohne Kartenposition", trailing: AtlasFormat.legs(summary.unmappedTripCount))
            Text("Für diese Haltestellen kennt die App keine Koordinaten. Die Fahrten zählen trotzdem voll in deiner Bilanz.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVStack(spacing: 0) {
                ForEach(summary.unmapped) { item in
                    unmappedRow(item)
                    if item.id != summary.unmapped.last?.id {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: 0.5)
                            .padding(.leading, 46)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.s + 2)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.formGroup, style: .continuous))
        }
    }

    private func unmappedRow(_ item: AtlasUnmappedRoute) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            ModeIcon(mode: item.mode, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(AtlasFormat.unmappedTitle(item))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(unmappedCaption(item))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            Text(Format.euro(item.value, decimals: 0))
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.vertical, Theme.Spacing.s - 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.fromName) und \(item.toName), \(item.mode.displayName)")
        .accessibilityValue("\(AtlasFormat.legs(item.legs)), \(Format.euro(item.value, decimals: 0)), ohne Kartenposition")
    }

    private func unmappedCaption(_ item: AtlasUnmappedRoute) -> String {
        var parts = [AtlasFormat.legs(item.legs)]
        if let known = item.knownPlaceName { parts.append("nur \(TripRow.short(known)) bekannt") }
        return parts.joined(separator: " · ")
    }

    // MARK: Helpers

    private func sectionTitle(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Spacing.xs)
            if let trailing {
                Text(trailing)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func note(symbol: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.s + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
