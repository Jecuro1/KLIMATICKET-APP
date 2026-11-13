import SwiftUI
import MapKit
import SwiftData
import KlimaCore

// Zug-Radar (docs/OEBB_LIVE.md §R, §R7): an own full-screen view with its own train layer. The base map is MapKit, the
// system map underneath; markers, clusters, route, filter, search and status are ours. Nothing is handed to the Apple
// Maps app. Every train in the visible area is on the map at every zoom (docs/OEBB_LIVE.md §R11): the view is covered by
// tiles of a fixed grid, a tile that is cut off at the request cap is split into four, and a scheduler keeps the radar's
// requests within 24 a minute. Requests only while the view is visible and active, never in Low Power Mode and never in the
// background.

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
    @Environment(\.colorScheme) var colorScheme   // MARK: radarheat – read by the Pünktlichkeit layer (RadarView+Heat.swift)
    @Environment(\.dynamicTypeSize) var heatTypeSize   // MARK: radarheat – the bottom area's limit follows the text size
    @State var model = RadarModel()
    @State var travel = RadarTimeModel()   // MARK: radartime – the time scrubber (docs/RADAR_TIMETRAVEL.md)
    @State var camera: MapCameraPosition = .region(RadarView.austriaRegion)
    @State var query = ""
    @State var showsFilter = false
    @State var showsLegend = false   // MARK: radarmodes – „Legende“ from the status card
    @State var sheetVehicle: RadarVehicle?
    @State var cockpit: CockpitLaunch?   // MARK: radarcockpit – the full-screen view that follows one train (docs/RADAR_COCKPIT.md)
    @State var pendingCockpit: CockpitLaunch?
    @State private var statusHeight: CGFloat = 0
    @AppStorage("radar.mapStyle") var styleRaw = RadarMapStyle.standard.rawValue
    @FocusState var searchFocused: Bool
    @State private var focusDone = false
    // MARK: map – the layers of the Scotty-style map (docs/OEBB_LIVE.md §R10); the choice is per device
    @AppStorage("map.layers") var layersRaw = MapLayerSelection.initial.storageValue
    // MARK: radarmodes – the chosen transport modes, per device (docs/RADAR_MODES.md §2); reset in screenshot launches
    @AppStorage(RadarModeSelection.storageKey) var modesRaw = RadarModeSelection.default.storageValue
    @State var allStations: [MapStationPin] = []
    /// The stations in view, grouped for the zoom, and their lookup by id. Computed when the camera stops (`refreshStations`), not
    /// in the view body: the body runs every second, and a lookup that is rebuilt per marker is thousands of inserts each time.
    @State var stationClusters: [MapCluster] = []
    @State var stationIndex: [String: MapStationPin] = [:]
    @State var showsDisruptions = false
    @State var showsRoutes = false
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    var favorites: [FavoriteRouteEntity]

    private static var austriaRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: RadarBox.austria.center.clCoordinate, span: MKCoordinateSpan(latitudeDelta: 4.2, longitudeDelta: 9.0))
    }

    var mapStyle: RadarMapStyle { RadarMapStyle(rawValue: styleRaw) ?? .standard }

    /// What is on and open, for the rules the live loop, the Pünktlichkeit layer, the Zeitreise and the cockpit share (`RadarFeatureGate`,
    /// docs/OEBB_LIVE.md §R11.3).
    var gate: RadarFeatureGate {
        RadarFeatureGate(layers: layers, access: liveAccess, railOnly: model.carriesOnlyTrains, sceneActive: scenePhase == .active,
                         cockpitOpen: cockpit != nil, timeOpen: travel.isOpen, timeAway: travel.isAway)
    }

    /// Whether the live data may be asked: offline alone is told apart, it suspends a Zeitreise instead of ending it.
    private var liveAccess: RadarFeatureGate.Access {
        guard let reason = app.live.timetableUnavailable else { return .open }
        return reason == .offline ? .offline : .closed
    }

    /// The train layer is on and the live data is allowed. Without it no train request is sent, and the map still shows
    /// the layers that work offline (stations, saved routes).
    var trainsOn: Bool { gate.trainsOn }

    /// The live loop runs: a layer needs it (trains or Pünktlichkeit), the Zeitreise is at now (radartime) and no cockpit covers the radar
    /// (radarcockpit: it asks for its one train instead).
    private var isRunning: Bool { gate.liveLoopRuns }

    var body: some View {
        NavigationStack {
            mapLayer
            .overlay { RadarSkyTint(travel: travel) }   // MARK: radartime
            .navigationTitle("Zug-Radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterButton }
                ToolbarItem(placement: .topBarTrailing) { styleMenu }
                ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } }
            }
            .safeAreaInset(edge: .top, spacing: Theme.Spacing.xs) { topBar }
            .safeAreaInset(edge: .bottom, spacing: Theme.Spacing.xs) {
                // Large text sizes scroll the panel instead of covering the map: it takes exactly its content's height (measured),
                // up to a cap. A scroll view that is only asked to fit its content stays at the cap and leaves a gap under the panel.
                ScrollView {
                    statusBar
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            statusHeight = height
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: statusHeight > 0 ? min(statusHeight, statusMaxHeight) : statusMaxHeight)   // MARK: radarheat
            }
            // The loop only restarts when the view becomes (in)active. A new map area or mode goes to the scheduler directly:
            // it settles for a moment, so a series of moves costs one round of requests.
            .task(id: isRunning) {
                guard isRunning, let service = radarService else { return }
                await model.run(service)
            }
            .onChange(of: model.pins.count) { _, _ in centerOnFocusedTrip() }
            .sheet(isPresented: $showsFilter) {
                RadarFilterSheet(filter: Binding(get: { model.filter }, set: { model.filter = $0 }),
                                 modes: Binding(get: { model.modes }, set: { setModes($0) }),   // MARK: radarmodes
                                 // Selected lines stay in the list even when none of them is on the map right now, so an
                                 // active line filter is always visible and can be cleared.
                                 categories: Set(model.knownVehicles.map { RadarLine.category(of: $0.line) })
                                    .union(model.filter.categories).filter { !$0.isEmpty }.sorted(),
                                 parts: model.radar2)   // MARK: radar2
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $sheetVehicle, onDismiss: openPendingCockpit) { vehicle in   // MARK: radarcockpit
                RadarTripSheet(vehicle: vehicle,
                               onCenter: { center(on: vehicle.tripID) },
                               onRoute: { points in
                                   model.routeTripID = vehicle.tripID
                                   model.route = points
                               },
                               onStation: { stop in
                                   showBoard { app.planner.showBoard(live: stop) }
                               },
                               onCockpit: cockpitEntry(for: vehicle),   // MARK: radarcockpit; radartime – from a Zeitreise only a train the live radar knows
                               radar2: model.radar2)   // MARK: radar2
                    .presentationDetents([.fraction(0.32), .medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
            .fullScreenCover(item: $cockpit) { launch in   // MARK: radarcockpit
                CockpitView(launch: launch, services: .live(app, budget: model)) { cockpit = nil }
            }
            .sheet(isPresented: $showsLegend) { RadarLegendSheet().presentationDetents([.medium, .large]) }   // MARK: radarmodes
            .sheet(isPresented: $showsDisruptions) { DisruptionsView() }
            .sheet(isPresented: $showsRoutes) { SavedRoutesView() }
            .modifier(RadarHeatHooks(model: model, isOn: heatOn, cellSheet: heatCellSheet))   // MARK: radarheat
            .modifier(RadarTimeHooks(travel: travel, model: model, service: timeService, gate: gate))   // MARK: radartime – paused under the cockpit, like the live loop
            .modifier(Radar2Hooks(parts: model.radar2, access: gate.access, timeOpen: travel.isOpen))   // MARK: radar2
            .onChange(of: trainsOn, initial: true) { _, on in model.setMarkersOn(on) }   // MARK: radarmodes – the city lane only for drawn markers
            .task {
                if allStations.isEmpty { allStations = app.stations.stations.map(stationPin) }
                refreshStations(box: model.box, span: model.spanDegrees)
            }
            .onAppear(perform: applyPreset)
        }
    }

    // MARK: Map and train layer

    private var mapLayer: some View {
        MapReader { proxy in   // MARK: radarheat – a tap on the map finds the cell under the finger
        Map(position: $camera) {
            if heatOn {   // MARK: radarheat
                heatContent
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
            // Trains are declared last, but that does not decide what is on top: MapKit orders annotation views itself (the one
            // further south is drawn over the one further north) and SwiftUI's Map has no z-index for annotations (CI screenshot
            // radarAllZoom, run 1: a station bubble over a train bubble). So trains have priority by collision: a station marker
            // that would sit under a train marker is left out (`MapDeclutter`, `visibleStationClusters`).
            radar2MapContent   // MARK: radar2 – trails, the stop of „Meine“ (drawn under the markers)
            if trainsOn {
            if travel.isAway { timeTrailLayer }   // MARK: radartime
            ForEach(shownClusters) { cluster in   // MARK: radartime – the Zeitreise's pins while away from now
                if cluster.isSingle, let id = cluster.tripIDs.first, let pin = shownPin(id) {
                    Annotation(pin.vehicle.line.map { LinePresentation.title($0) } ?? "Zug",
                               coordinate: pin.coordinate.clCoordinate, anchor: .center) {
                        Button { select(pin) } label: {
                            pinLabel(pin)   // MARK: radarheat – the marker, or a dot while the Pünktlichkeit layer is on
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)   // the marker carries its plate; a caption under each would be a wall of text
                } else {
                    Annotation("\(cluster.count) \(vehicleNoun)", coordinate: cluster.center.clCoordinate, anchor: .center) {
                        Button { zoom(to: cluster) } label: { clusterLabel(cluster, noun: vehicleNoun) }   // MARK: radarheat
                            .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)   // the bubble carries its count
                }
            }
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
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            model.setMapSize(size)
        }
        .accessibilityLabel("Zug-Radar, \(travel.isAway ? travel.summary : model.summary)")   // MARK: radartime
        .haptic(.selection, trigger: model.selectedTripID)
        .simultaneousGesture(SpatialTapGesture().onEnded { handleMapTap(at: $0.location, proxy: proxy) })   // MARK: radarheat
        }
    }

    /// The noun of the summary and the clusters: "Züge" when only rail is on, else "Fahrzeuge" (as the status line says).
    private var vehicleNoun: String { model.carriesOnlyTrains ? "Züge" : "Fahrzeuge" }

    /// The radar service. The dense demo scenes bring their own (synthetic, no network); everything else goes through the gate.
    var radarService: (any RadarService)? {
        if preset.isCityDemo { return RadarCityDemoService(crowded: preset == .modesCrowded) }   // MARK: radarmodes
        return preset.isTimeDemo ? RadarTimeDemoService() : (preset.isDenseDemo ? DemoRadarService(dense: true) : (preset.isHeatDemo ? DemoRadarService(heat: true) : app.live.radar))   // MARK: radarheat, radartime
    }

    private func select(_ pin: RadarPin) {
        if model.routeTripID != pin.id {
            model.route = []
            model.routeTripID = nil
        }
        model.selectedTripID = pin.id
        if model.heat.selectedCell != nil { model.heat.trainSheet = pin.vehicle } else { sheetVehicle = pin.vehicle }   // MARK: radarheat – on top of the cell sheet when that is up
    }

    func zoom(to cluster: RadarCluster) {
        let span = max(model.spanDegrees / 3, 0.02)
        camera = .region(MKCoordinateRegion(center: cluster.center.clCoordinate,
                                            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span * 1.4)))
    }

    func center(on tripID: String) {
        guard let pin = shownPin(tripID) else { return }   // MARK: radartime
        camera = .region(MKCoordinateRegion(center: pin.coordinate.clCoordinate,
                                            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.5)))
    }

    /// Once, when the focused trip first appears among the pins.
    private func centerOnFocusedTrip() {
        guard !focusDone, let focusTripID, model.pinsByID[focusTripID] != nil else { return }
        focusDone = true
        center(on: focusTripID)
    }

    /// The focused trip was asked for, the trains are on, and the last answer did not put it on the map: said in the status
    /// area, instead of a map that silently stays where it is.
    var focusMissing: Bool {
        guard let focusTripID, !focusDone, trainsOn, model.load == .loaded else { return false }
        return model.pinsByID[focusTripID] == nil
    }

    private func applyPreset() {
        // MARK: radartime – screenshot and perf launches start every scene from the layers of a fresh install. The layer choice is stored
        // per device, and a scene that sets its own (Zeitreise: trains only; Pünktlichkeit) changed the scenes captured after it in the same
        // simulator: the default radar lost its stations (CI run 43408109942, scene "radar" after the Zeitreise scenes).
        if LaunchMode.isSandboxed { layersRaw = MapLayerSelection.initial.storageValue }
        // MARK: radarmodes – the modes as stored (a screenshot launch starts from the default, like the layers)
        if LaunchMode.isSandboxed { modesRaw = RadarModeSelection.default.storageValue }
        model.modes = RadarModeSelection(storage: modesRaw)
        // "Auf der Karte zeigen" needs the train layer: it is switched on, and the choice stays (the layer bar shows it).
        if focusTripID != nil, !layers.isOn(.trains) { toggleLayer(.trains) }
        dropHeatLayerInScreenshots()   // MARK: radarheat – a scene of another preset does not inherit the layer a heat scene stored
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
        case .allTrains:   // MARK: radarall – about 1500 synthetic trains, Austria-wide view: clusters with counts
            break
        case .allTrainsZoom:   // MARK: radarall – the same trains, zoomed to Wien and its S-Bahn: single trains and small clusters
            camera = .region(MKCoordinateRegion(center: GeoPoint(latitude: 48.17, longitude: 16.30).clCoordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.55)))
        case .timeTravel, .timeTravelPlaying, .timeTravelLoading, .timeTravelChip:   // MARK: radartime
            applyTimePreset(preset)
        case .heat, .heatPanel, .heatLists, .heatTrend, .heatCell, .heatAX5:   // MARK: radarheat
            applyHeatPreset(preset)
        case .modesCity, .modesZoomHint, .modesLegend, .modesCrowded:   // MARK: radarmodes
            applyModesPreset(preset)
        case .layers:   // MARK: map – all layers on, zoomed to Wien so the station markers show (CI screenshots)
            layersRaw = MapLayerSelection(layers: [.stations, .trains, .disruptions, .routes]).storageValue   // radarheat: not the Pünktlichkeit layer
            camera = .region(MKCoordinateRegion(center: GeoPoint(latitude: 48.20, longitude: 16.37).clCoordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 0.9, longitudeDelta: 1.3)))
        }
    }
}
