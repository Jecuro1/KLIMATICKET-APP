import SwiftUI
import MapKit
import SwiftData
import KlimaCore

// Zug-Radar (docs/OEBB_LIVE.md §R, §R7): an own full-screen view with its own train layer. The base map is MapKit, the
// system map underneath; markers, clusters, route, filter, search and status are ours. Nothing is handed to the Apple
// Maps app. Budget: one request per tile every 20 s, only while the view is visible and active, never in Low Power
// Mode and never in the background. A map move refreshes once when it ends. A truncated answer splits the view into
// quadrants (up to four requests), and the view says so when even that is cut off.

struct RadarView: View {
    var preset: RadarPreset = .live
    /// „Auf der Karte zeigen“ from a train search (docs/OEBB_LIVE.md §R9): the map centres on this trip once its pin is there.
    var focusTripID: String? = nil
    /// Set when the radar is opened from the train search: a departures board then closes the search as well, because the
    /// board opens in the Fahrplan underneath the search's cover.
    var closeSearch: (() -> Void)? = nil

    @Environment(AppState.self) var app
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State var model = RadarModel()
    @State var camera: MapCameraPosition = .region(RadarView.austriaRegion)
    @State var query = ""
    @State var showsFilter = false
    @State var sheetVehicle: RadarVehicle?
    @AppStorage("radar.mapStyle") var styleRaw = RadarMapStyle.standard.rawValue
    @FocusState var searchFocused: Bool
    @State private var focusDone = false
    // MARK: map – the layers of the Scotty-style map (docs/OEBB_LIVE.md §R10); the choice is per device
    @AppStorage("map.layers") var layersRaw = MapLayerSelection.initial.storageValue
    @State var allStations: [MapStationPin] = []
    @State var stationPins: [MapStationPin] = []
    @State var showsDisruptions = false
    @State var showsRoutes = false
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    var favorites: [FavoriteRouteEntity]

    private static var austriaRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: RadarBox.austria.center.clCoordinate, span: MKCoordinateSpan(latitudeDelta: 4.2, longitudeDelta: 9.0))
    }

    /// Restarts the refresh loop when the modes, the visible area or the activity change.
    private struct RunKey: Hashable {
        var products: ProductMask
        var box: [Int]
        var active: Bool
    }

    var mapStyle: RadarMapStyle { RadarMapStyle(rawValue: styleRaw) ?? .standard }

    /// The train layer is on and the live data is allowed. Without it no train request is sent, and the map still shows
    /// the layers that work offline (stations, saved routes).
    var trainsOn: Bool {
        layers.isOn(.trains) && app.live.timetableUnavailable == nil
    }

    private var isRunning: Bool {
        scenePhase == .active && trainsOn
    }

    /// The visible rectangle at 0.01° resolution, so small camera moves do not restart the loop.
    private var boxKey: [Int] {
        [model.box.north, model.box.west, model.box.south, model.box.east].map { Int(($0 * 100).rounded()) }
    }

    var body: some View {
        NavigationStack {
            mapLayer
            .navigationTitle("Zug-Radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterButton }
                ToolbarItem(placement: .topBarTrailing) { styleMenu }
                ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } }
            }
            .safeAreaInset(edge: .top, spacing: Theme.Spacing.xs) { topBar }
            .safeAreaInset(edge: .bottom, spacing: Theme.Spacing.xs) {
                // Large text sizes scroll the panel instead of covering the map: it takes its content's height, up to a cap.
                ScrollView { statusBar }
                    .scrollBounceBehavior(.basedOnSize)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: 360)
            }
            .task(id: RunKey(products: model.products, box: boxKey, active: isRunning)) {
                guard isRunning, let service = app.live.radar else { return }
                await model.run(service, interval: .seconds(20))
            }
            .onChange(of: model.pins.count) { _, _ in centerOnFocusedTrip() }
            .sheet(isPresented: $showsFilter) {
                RadarFilterSheet(filter: Binding(get: { model.filter }, set: { model.filter = $0 }),
                                 modes: Binding(get: { model.modes }, set: { model.modes = $0 }),
                                 // Selected lines stay in the list even when none of them is on the map right now, so an
                                 // active line filter is always visible and can be cleared.
                                 categories: Set(model.knownVehicles.map { RadarLine.category(of: $0.line) })
                                    .union(model.filter.categories).filter { !$0.isEmpty }.sorted())
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $sheetVehicle) { vehicle in
                RadarTripSheet(vehicle: vehicle,
                               onCenter: { center(on: vehicle.tripID) },
                               onRoute: { points in
                                   model.routeTripID = vehicle.tripID
                                   model.route = points
                               },
                               onStation: { stop in
                                   showBoard { app.planner.showBoard(live: stop) }
                               })
                    .presentationDetents([.fraction(0.32), .medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
            .sheet(isPresented: $showsDisruptions) { DisruptionsView() }
            .sheet(isPresented: $showsRoutes) { SavedRoutesView() }
            .task {
                if allStations.isEmpty { allStations = app.stations.stations.map(stationPin) }
                refreshStations(box: model.box, span: model.spanDegrees)
            }
            .onAppear(perform: applyPreset)
        }
    }

    // MARK: Map and train layer

    private var mapLayer: some View {
        Map(position: $camera) {
            if trainsOn {
            ForEach(clusters) { cluster in
                if cluster.isSingle, let id = cluster.tripIDs.first, let pin = pinsByID[id] {
                    Annotation(pin.vehicle.line.map { LinePresentation.title($0) } ?? "Zug",
                               coordinate: pin.coordinate.clCoordinate, anchor: .center) {
                        Button { select(pin) } label: {
                            RadarMarker(pin: pin, isSelected: model.selectedTripID == pin.id)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Annotation("\(cluster.count) \(vehicleNoun)", coordinate: cluster.center.clCoordinate, anchor: .center) {
                        Button { zoom(to: cluster) } label: { RadarClusterBubble(cluster: cluster, noun: vehicleNoun) }
                            .buttonStyle(.plain)
                    }
                }
            }
            }
            if layers.isOn(.stations), MapStations.isDrawn(latitudeSpan: model.spanDegrees) {
                stationLayer
            }
            if layers.isOn(.routes) {
                routeLayer
            }
            if model.routeTripID == model.selectedTripID, model.route.count > 1 {
                MapPolyline(coordinates: model.route.map(\.clCoordinate))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(mapStyle.style)
        .environment(\.colorScheme, mapStyle == .dark ? .dark : colorScheme)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            let r = context.region
            let box = RadarBox(north: r.center.latitude + r.span.latitudeDelta / 2,
                               west: r.center.longitude - r.span.longitudeDelta / 2,
                               south: r.center.latitude - r.span.latitudeDelta / 2,
                               east: r.center.longitude + r.span.longitudeDelta / 2).clamped
            model.setView(box: box, span: r.span.latitudeDelta)
            refreshStations(box: box, span: r.span.latitudeDelta)
        }
        .accessibilityLabel("Zug-Radar, \(model.summary)")
        .ignoresSafeArea(edges: .bottom)
        .haptic(.selection, trigger: model.selectedTripID)
    }

    /// The noun of the summary and the clusters: "Züge" when only rail is on, else "Fahrzeuge" (as the status line says).
    private var vehicleNoun: String { model.isRailOnly ? "Züge" : "Fahrzeuge" }

    private var pinsByID: [String: RadarPin] {
        Dictionary(model.pins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Markers merge into clusters only when they would overlap at the current zoom.
    private var clusters: [RadarCluster] {
        RadarClustering.group(model.pins.map { RadarPoint(tripID: $0.id, coordinate: $0.coordinate, delay: $0.delay) },
                              cellDegrees: RadarClustering.cellSize(forLatitudeSpan: model.spanDegrees))
    }

    private func select(_ pin: RadarPin) {
        if model.routeTripID != pin.id {
            model.route = []
            model.routeTripID = nil
        }
        model.selectedTripID = pin.id
        sheetVehicle = pin.vehicle
    }

    func zoom(to cluster: RadarCluster) {
        let span = max(model.spanDegrees / 3, 0.02)
        camera = .region(MKCoordinateRegion(center: cluster.center.clCoordinate,
                                            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span * 1.4)))
    }

    func center(on tripID: String) {
        guard let pin = pinsByID[tripID] else { return }
        camera = .region(MKCoordinateRegion(center: pin.coordinate.clCoordinate,
                                            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.5)))
    }

    /// Once, when the focused trip first appears among the pins.
    private func centerOnFocusedTrip() {
        guard !focusDone, let focusTripID, pinsByID[focusTripID] != nil else { return }
        focusDone = true
        center(on: focusTripID)
    }

    /// The focused trip was asked for, the trains are on, and the last answer did not put it on the map: said in the status
    /// area, instead of a map that silently stays where it is.
    var focusMissing: Bool {
        guard let focusTripID, !focusDone, trainsOn, model.load == .loaded else { return false }
        return pinsByID[focusTripID] == nil
    }

    private func applyPreset() {
        // "Auf der Karte zeigen" needs the train layer: it is switched on, and the choice stays (the layer bar shows it).
        if focusTripID != nil, !layers.isOn(.trains) { toggleLayer(.trains) }
        switch preset {
        case .live:
            break
        case .filter:
            model.filter = RadarFilter(categories: ["RJX"])
            showsFilter = true
        case .search:
            query = "RJX"
        case .cluster:
            camera = .region(MKCoordinateRegion(center: RadarBox.austria.center.clCoordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 8.5, longitudeDelta: 16)))
        case .layers:   // MARK: map – all layers on, zoomed to Wien so the station markers show (CI screenshots)
            layersRaw = MapLayerSelection.all.storageValue
            camera = .region(MKCoordinateRegion(center: GeoPoint(latitude: 48.20, longitude: 16.37).clCoordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 0.9, longitudeDelta: 1.3)))
        }
    }
}
