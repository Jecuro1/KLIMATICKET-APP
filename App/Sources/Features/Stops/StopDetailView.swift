import KlimaCore
import SwiftData
import SwiftUI

/// The stop detail (ENRICH_SPEC §3.2, LOGO_SPEC §4.4): map, hero card with Gebietsleiste and line families, lines by
/// mode, ski-pass card, KlimaTicket, facts and sources. Presented as a sheet (`View.stopDetail(placeID:)`) or pushed
/// inside an existing `NavigationStack` (`StopDetailView(placeID:)`).
struct StopDetailView: View {
    let placeID: String

    @State private var model: StopDetailModel
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }) private var trips: [TripEntity]

    private static let mapHeight: CGFloat = 300
    private static let overlap: CGFloat = 56

    init(placeID: String) {
        self.placeID = placeID
        _model = State(initialValue: StopDetailModel(placeID: placeID))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.sheetBackground.ignoresSafeArea()
            switch model.phase {
            case .loading:
                ProgressView().frame(maxHeight: .infinity)
            case .missing:
                ContentUnavailableView("Haltestelle nicht gefunden", systemImage: "mappin.slash",
                                       description: Text("Diese Haltestelle gibt es in den Daten nicht."))
            case .loaded:
                if let details = model.details {
                    content(details)
                }
            }
            toolbarOverlay
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load() }
    }

    // MARK: Content

    private func content(_ details: StopDetails) -> some View {
        let ctx = StopContext(details: details, index: model.index, dark: scheme == .dark)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    StopMapHero(place: details.place, neighbours: details.neighbours, snowcap: details.tags.showsSnowcap)
                        .frame(height: Self.mapHeight)
                        .clipped()
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        StopHeroCard(ctx: ctx, onBrandTap: showBrand) {
                            withMotion(Motion.smooth) { proxy.scrollTo("lines", anchor: .top) }
                        }
                        .reveal(.rise, order: 0)
                        StopDeparturesSection(state: model.departures)
                        StopLinesSection(ctx: ctx).id("lines").reveal(.rise, order: 1)
                        if !details.facilities.isEmpty {
                            StopFacilitiesSection(facilities: details.facilities, buildDate: model.index?.dataInfo.buildDate)
                                .id("facilities").reveal(.rise, order: 2)
                        }
                        StopSkiSection(ctx: ctx, onWebsite: showBrand).id("ski").reveal(.rise, order: 2)
                        StopKlimaTicketCard(ctx: ctx, tripCount: tripStats.count, tripValue: tripStats.value, onTrips: showTrips)
                            .id("ticket").reveal(.rise, order: 3)
                        StopFactsSection(ctx: ctx, onBrandTap: showBrand).id("facts").reveal(.rise, order: 4)
                        StopSourcesFooter(ctx: ctx).id("footer")
                    }
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.top, -Self.overlap)
                    .padding(.bottom, 24)
                }
            }
            .revealScope()
            .task { await scrollForScreenshot(proxy) }
            .ignoresSafeArea(edges: .top)
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if app.tripDraft == nil {
                StopActionBar(onFrom: { startTrip(details.place, from: true) }, onTo: { startTrip(details.place, from: false) })
            }
        }
    }

    private var toolbarOverlay: some View {
        HStack {
            glassButton("chevron.left", label: "Zurück") { dismiss() }
            Spacer()
            if let place = model.details?.place {
                ShareLink(item: shareURL(place), subject: Text(PlaceNames.display(place.name)),
                          message: Text(PlaceNames.display(place.name))) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary).frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel("Teilen")
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, 8)
    }

    private func glassButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// CI screenshots (`stopDetailWarthMid`, `…End`): scroll to the ski card or the end of the page.
    private func scrollForScreenshot(_ proxy: ScrollViewProxy) async {
        guard let screen = LaunchMode.screenshotScreen else { return }
        let target: (String, UnitPoint)?
        if screen.hasSuffix("Mid") { target = ("ski", .top) }
        else if screen.hasSuffix("End") { target = ("footer", .bottom) }
        else if screen.hasSuffix("Lines") { target = ("lines", .top) }
        else if screen.hasSuffix("Facilities") { target = ("facilities", .top) }
        else { target = nil }
        guard let target else { return }
        try? await Task.sleep(for: .milliseconds(900))
        proxy.scrollTo(target.0, anchor: target.1)
    }

    // MARK: Actions

    private func shareURL(_ place: Place) -> URL {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "ll", value: "\(place.coordinate.latitude),\(place.coordinate.longitude)"),
                        URLQueryItem(name: "q", value: PlaceNames.display(place.name))]
        return c.url ?? URL(string: "https://maps.apple.com/")!
    }

    private func showBrand(_ brand: LogoPackManifest.Brand) {
        if let url = URL(string: brand.web), url.scheme == "https" { openURL(url) }
    }

    private var tripStats: (count: Int, value: Double) {
        let ids = model.tripStationIDs
        let mine = trips.filter { t in
            (t.fromStationID.map(ids.contains) ?? false) || (t.toStationID.map(ids.contains) ?? false)
        }
        return (mine.count, mine.reduce(0) { $0 + $1.totalValue })
    }

    private func showTrips() {
        dismiss()
        app.selectedTab = .trips
    }

    /// „Fahrt von/nach hier“: closes the detail, then opens „Neue Fahrt“ (a second sheet cannot open on top of it).
    private func startTrip(_ place: Place, from: Bool) {
        var draft = TripDraft()
        let name = place.station.name
        if from {
            draft.fromStationID = place.stationID
            draft.fromName = name
        } else {
            draft.toStationID = place.stationID
            draft.toName = name
        }
        draft.mode = place.products.primaryMode
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            app.presentAddTrip(draft)
        }
    }
}
