#if DEBUG
import SwiftUI
import WidgetKit
import KlimaCore

/// CI screenshot routes of the widget track (`-KBScreenshot <route>`, RootView › ScreenshotRouter, `// MARK: widgets`).
/// The simulator cannot capture widgets, so these screens render the same SwiftUI views the widget extension renders, at
/// widget sizes, with demo data (WidSamples / WidgetSnapshot.sample) and no network. DEBUG builds only.
struct WidgetPreviewHost: View {
    static let screens: Set<String> = ["widgetsGallery", "widgetsGalleryDark", "widgetsNextConnection", "widgetsHeatmap",
                                       "widgetsLockScreen", "widgetsStandBy", "widgetsEquipment"]

    let screen: String

    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        switch screen {
        case "widgetsNextConnection":
            page() { nextConnectionTiles }
        // MARK: review-widgets – equipment on top of the page (the other tiles stay below the fold of a capture)
        case "widgetsEquipment":
            page() { equipmentTiles }
        case "widgetsHeatmap":
            page() { heatmapTiles }
        case "widgetsLockScreen":
            lockScreen
        case "widgetsStandBy":
            standBy
        case "widgetsGalleryDark":
            page(dark: true) { galleryTiles }
        default:
            page() { galleryTiles }
        }
    }

    // MARK: Pages

    /// A scrollable page of tiles. Light and dark follow the system appearance (the CI captures both); `dark` forces the
    /// dark variant for the gallery route that shows it.
    private func page<Tiles: View>(dark: Bool = false, @ViewBuilder _ tiles: () -> Tiles) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(verbatim: dark ? "Widgets · dunkel" : "Widgets")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                tiles()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .environment(\.colorScheme, dark ? .dark : systemScheme)
        .environment(\.widNow, now)
    }

    private var lockScreen: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#1B2A4A"), Color(hex: "#0B1222")], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(verbatim: "Sperrbildschirm")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    HStack(spacing: 18) {
                        lockTile(.accessoryCircular, "Ticket-Restzeit") {
                            TicketRemainingWidgetView(snapshot: snapshot, family: .accessoryCircular, now: now)
                        }
                        lockTile(.accessoryCircular, "Break-even") {
                            BreakEvenWidgetView(snapshot: snapshot, family: .accessoryCircular, now: now)
                        }
                    }
                    lockTile(.accessoryRectangular, "Nächste Verbindung") {
                        NextConnectionWidgetView(title: "Pendeln", state: fresh, items: connections, family: .accessoryRectangular)
                    }
                    lockTile(.accessoryRectangular, "Abfahrten") {
                        DeparturesWidgetView(stationName: "Innsbruck Hbf", facilities: [.bikeRide], state: fresh,
                                             items: departures, family: .accessoryRectangular)
                    }
                    lockTile(.accessoryRectangular, "Break-even") {
                        BreakEvenWidgetView(snapshot: snapshot, family: .accessoryRectangular, now: now)
                    }
                    lockTile(.accessoryRectangular, "Gipfel") {
                        SummitWidgetView(snapshot: snapshot, family: .accessoryRectangular, now: now)
                    }
                    lockTile(.accessoryRectangular, "Störungen") {
                        DisruptionsWidgetView(state: fresh, items: disruptions, followedLines: ["S 4"], family: .accessoryRectangular)
                    }
                    lockTile(.accessoryInline, "Nächste Verbindung") {
                        NextConnectionWidgetView(title: "Pendeln", state: fresh, items: connections, family: .accessoryInline)
                    }
                    lockTile(.accessoryInline, "Gipfel") {
                        SummitWidgetView(snapshot: snapshot, family: .accessoryInline, now: now)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .environment(\.colorScheme, .dark)
        .environment(\.widNow, now)
    }

    private var standBy: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            HStack(spacing: 14) {
                tileFrame(.systemSmall, scale: 1) {
                    SummitWidgetView(snapshot: snapshot, family: .systemSmall, now: now)
                        .environment(\.isLuminanceReduced, true)
                }
                tileFrame(.systemSmall, scale: 1) {
                    TicketRemainingWidgetView(snapshot: snapshot, family: .systemSmall, now: now)
                        .widContent(.systemSmall, WidLayout.defaultMargins)
                        .environment(\.isLuminanceReduced, true)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .environment(\.widNow, now)
    }

    // MARK: Tiles

    @ViewBuilder
    private var galleryTiles: some View {
        caption("Nächste Verbindung · Abfahrten")
        tile(.systemMedium) { NextConnectionWidgetView(title: "Pendeln", state: fresh, items: connections, family: .systemMedium) }
        tile(.systemMedium) { DeparturesWidgetView(stationName: "Innsbruck Hbf", facilities: [.bikeRide, .barrierFree], state: fresh, items: departures, family: .systemMedium) }
        caption("Störungen · Heatmap")
        tile(.systemMedium) { DisruptionsWidgetView(state: fresh, items: disruptions, followedLines: ["S 4", "R 51"], family: .systemMedium) }
        tile(.systemMedium) { HeatmapWidgetView(counts: heatmap, storedDay: now, now: now, family: .systemMedium) }
        caption("Ticket · Gipfel")
        HStack(spacing: 14) {
            tile(.systemSmall) { TicketRemainingWidgetView(snapshot: snapshot, family: .systemSmall, now: now) }
            tile(.systemSmall) { BreakEvenWidgetView(snapshot: snapshot, family: .systemSmall, now: now) }
        }
        HStack(spacing: 14) {
            tileFrame(.systemSmall, scale: 1) { SummitWidgetView(snapshot: snapshot, family: .systemSmall, now: now) }
            tile(.systemSmall) { YearReviewWidgetView(snapshot: snapshot, family: .systemSmall, now: now) }
        }
    }

    @ViewBuilder
    private var equipmentTiles: some View {
        caption("Abfahrten · Ausstattung aus OpenStreetMap, mit Quellenvermerk")
        tile(.systemLarge) { DeparturesWidgetView(stationName: "Innsbruck Hbf", facilities: [.bikeRide, .barrierFree, .elevator, .toilets], state: fresh, items: departures, family: .systemLarge) }
        tile(.systemLarge) { DeparturesWidgetView(stationName: "Landeck-Zams", facilities: [.elevator, .toilets, .bicycleParking, .barrierFreePartial], state: fresh, items: departures, family: .systemLarge) }
        caption("Mit Zwischenhalt · wird nicht live abgefragt")
        tile(.systemMedium) { NextConnectionWidgetView(title: "Pendeln über Landeck", state: fresh, items: connections, family: .systemMedium, viaStops: true) }
    }

    @ViewBuilder
    private var nextConnectionTiles: some View {
        caption("Nächste Verbindung · klein")
        tile(.systemSmall) { NextConnectionWidgetView(title: "Pendeln", state: fresh, items: connections, family: .systemSmall) }
        caption("Mittel und groß")
        tile(.systemMedium) { NextConnectionWidgetView(title: "Pendeln", state: fresh, items: connections, family: .systemMedium) }
        tile(.systemLarge) { NextConnectionWidgetView(title: "Pendeln", state: fresh, items: connections, family: .systemLarge) }
        // MARK: review-widgets – the station equipment from the place data and OpenStreetMap, and a via favourite
        caption("Abfahrten · groß mit Ausstattung und Quellenvermerk")
        tile(.systemLarge) { DeparturesWidgetView(stationName: "Innsbruck Hbf", facilities: [.bikeRide, .barrierFree, .elevator, .toilets], state: fresh, items: departures, family: .systemLarge) }
        caption("Mit Zwischenhalt · wird nicht live abgefragt")
        tile(.systemMedium) { NextConnectionWidgetView(title: "Pendeln über Landeck", state: fresh, items: connections, family: .systemMedium, viaStops: true) }
        caption("Keine Lieblingsfahrt gewählt · Live-Daten aus")
        tile(.systemMedium) { NextConnectionWidgetView(title: nil, state: .off, items: [], family: .systemMedium) }
        tile(.systemMedium) { NextConnectionWidgetView(title: "Pendeln", state: .stale(now.addingTimeInterval(-3 * 3_600)),
                                                       items: [], family: .systemMedium) }
    }

    @ViewBuilder
    private var heatmapTiles: some View {
        caption("Fahrten-Kalender · mittel")
        tile(.systemMedium) { HeatmapWidgetView(counts: heatmap, storedDay: now, now: now, family: .systemMedium) }
        caption("Fahrten-Kalender · groß")
        tile(.systemLarge) { HeatmapWidgetView(counts: heatmap, storedDay: now, now: now, family: .systemLarge) }
    }

    private func tile<Content: View>(_ family: WidgetFamily, @ViewBuilder _ content: () -> Content) -> some View {
        tileFrame(family, scale: 1) {
            content()
                .widContent(family, WidLayout.defaultMargins)
        }
    }

    /// One widget at its size on its brand sky, with the home-screen corners.
    private func tileFrame<Content: View>(_ family: WidgetFamily, scale: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        let size = WidLayout.size(for: family)
        let shape = RoundedRectangle(cornerRadius: WidLayout.cornerRadius, style: .continuous)
        return content()
            .frame(width: size.width, height: size.height)
            .background { WidSkyBackground(family: family) }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 0.6) }
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
    }

    private func lockTile<Content: View>(_ family: WidgetFamily, _ caption: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            content()
                .frame(width: WidLayout.size(for: family).width, height: WidLayout.size(for: family).height, alignment: .leading)
                .padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.08)))
        }
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
    }

    // MARK: Demo data

    private var now: Date { Date() }
    private var snapshot: WidgetSnapshot { .sample }
    private var fresh: WidgetLiveState { .fresh(now) }
    private var connections: [WidgetConnection] { WidSamples.connections(now: now) }
    private var departures: [WidgetDeparture] { WidSamples.departures(now: now) }
    private var disruptions: [WidgetDisruption] { WidSamples.disruptions }
    private var heatmap: [Int] { WidSamples.heatmapCounts() }
}
#endif
