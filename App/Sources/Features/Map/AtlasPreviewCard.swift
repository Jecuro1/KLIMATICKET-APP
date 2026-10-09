import SwiftUI
import SwiftData
import MapKit
import KlimaCore

/// Compact, non-interactive "Meine Österreich-Karte" card for the statistics tab. Tapping opens the full map.
struct AtlasPreviewCard: View {
    /// The statistics snapshot of the shown ticket year (its `trips` are already limited to the period).
    let snapshot: AnalyticsSnapshot
    /// Ticket year to open the full map with.
    var ticketID: UUID? = nil

    @Environment(AppState.self) private var app

    var body: some View {
        let summary = Atlas.summarize(snapshot.trips, stations: app.stations)
        NavigationLink {
            AtlasView(initialTicketID: ticketID)
        } label: {
            AtlasPreviewCardContent(summary: summary)
        }
        .buttonStyle(AtlasPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meine Österreich-Karte")
        .accessibilityValue(accessibilityValue(summary))
        .accessibilityHint("Öffnet die interaktive Karte")
        .accessibilityAddTraits(.isButton)
    }

    private func accessibilityValue(_ summary: AtlasSummary) -> String {
        var parts = ["\(summary.visitedStateCount) von 9 Bundesländern bereist",
                     AtlasFormat.stations(summary.places.count),
                     AtlasFormat.routes(summary.routes.count)]
        if let top = summary.topRoute {
            parts.append("meistgefahren: \(top.from.name) und \(top.to.name)")
        }
        return parts.joined(separator: ", ")
    }
}

/// Card body (separate so the screenshot gallery can render it without navigation).
struct AtlasPreviewCardContent: View {
    let summary: AtlasSummary

    var body: some View {
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                header
                AtlasMiniMap(summary: summary)
                    .frame(height: 196)
                AtlasStateStamps(visited: summary.visitedStates, height: 26)
                footer
            }
        }
        .contentShape(.rect(cornerRadius: Theme.Radius.card))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Kicker(text: "Meine Österreich-Karte")
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.xs)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.14), in: .circle)
        }
    }

    private var title: String {
        if summary.tripCount == 0 { return "Deine Reisekarte wartet auf die erste Fahrt" }
        if summary.isAllAustria { return "Ganz Österreich – alle 9 Bundesländer bereist" }
        return "\(summary.visitedStateCount) von 9 Bundesländern bereist"
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.s) {
            Label(AtlasFormat.stations(summary.places.count), systemImage: "mappin.circle.fill")
            Label(AtlasFormat.routes(summary.routes.count), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            Spacer(minLength: 0)
            Text("Karte öffnen")
                .foregroundStyle(Theme.accentText)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.textSecondary)
        .labelStyle(AtlasCompactLabelStyle())
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}

/// Static map thumbnail: same arcs and dots as the full map, no labels, no interaction.
struct AtlasMiniMap: View {
    let summary: AtlasSummary

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let region = Atlas.region(fitting: summary.bounds ?? .austria,
                                      width: Double(max(geometry.size.width, 1)),
                                      height: Double(max(geometry.size.height, 1)),
                                      insets: AtlasInsets(top: summary.topRoute == nil ? 0 : 30),
                                      padding: 0.08, minimumSpanKm: 40)
            let palette = AtlasPalette(environment: environment, look: .standard, scheme: colorScheme)
            Map(initialPosition: .region(region.mkRegion), interactionModes: []) {
                AtlasRouteLayers(routes: summary.routes, selectedID: nil, palette: palette, scale: 0.8)
                ForEach(summary.places) { place in
                    Annotation(place.name, coordinate: place.location.coordinate, anchor: .center) {
                        Circle()
                            .fill(palette.color(place.dominantMode))
                            .frame(width: dot(place), height: dot(place))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(AtlasMapLook.standard.mapStyle)
            // A static camera: rebuild the map whenever the framing changes (size or another ticket year's bounds).
            .id(String(format: "%.4f|%.4f|%.4f|%.4f", region.centerLatitude, region.centerLongitude,
                       region.latitudeDelta, region.longitudeDelta))
        }
        .clipShape(.rect(cornerRadius: Theme.Radius.tile, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            // Top corner: MapKit keeps its attribution in the bottom-left corner, which must stay visible.
            if let top = summary.topRoute {
                topRouteChip(top)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func dot(_ place: AtlasPlace) -> CGFloat {
        let maxVisits = Double(max(summary.places.first?.visits ?? 1, 1))
        return 6 + 6 * CGFloat((Double(place.visits) / maxVisits).squareRoot())
    }

    private func topRouteChip(_ route: AtlasRoute) -> some View {
        HStack(spacing: 6) {
            AtlasModeDot(mode: route.dominantMode, size: 8)
            Text("\(AtlasFormat.routeTitle(route)) · \(AtlasFormat.legs(route.legs))")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .capsule)
        .padding(Theme.Spacing.s - 2)
    }
}

/// Icon + title with a tight gap (footer facts).
struct AtlasCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

/// Gentle press feedback for the tappable card.
struct AtlasPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Link from the Gipfelbuch ("Ganz Österreich" / "Bundesländer-Sammler:in") to the map.
struct AtlasAchievementLink: View {
    var body: some View {
        NavigationLink {
            AtlasView()
        } label: {
            Label("Auf der Karte ansehen", systemImage: "map.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glass)
        .accessibilityHint("Zeigt deine Strecken und Bundesländer auf der Österreich-Karte")
    }
}

/// CI screenshot "mapPreview": the statistics card on the sky, as it appears in the Statistik tab.
struct AtlasPreviewShowcase: View {
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date) private var trips: [TripEntity]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker(text: "Statistik")
                        Text("Deine Wege")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                    if let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) {
                        let snapshot = Analytics.make(ticket: ticket, trips: trips, catalog: app.catalog)
                        AtlasPreviewCard(snapshot: snapshot, ticketID: ticket.id)
                    }
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.xl)
            }
            .ambientBackground()
        }
    }
}
