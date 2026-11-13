import SwiftUI
import MapKit
import KlimaCore

// MARK: radartime – the Zeitreise on the radar's map (docs/RADAR_TIMETRAVEL.md). The scrubber, the card, the banner, the trail and the tint live in
// this folder; the radar view needs a few small hooks for them (`RadarView.swift`, `RadarView+Controls.swift`). While the scrubber is away from now the
// map draws the Zeitreise's pins instead of the live ones, and the live loop is paused.

extension RadarView {
    /// The Zeitreise is offered: trains are on and allowed, only trains (the snapshots are of rail vehicles), and the Pünktlichkeit layer
    /// (about now) is off. Asked of the layer itself, not of `heatOn` (which is off while away): switching the layer on during a Zeitreise
    /// ends it, so the chip does what it says instead of waiting silently behind the Zeitreise.
    var timeAvailable: Bool { trainsOn && !layers.isOn(.punctuality) && model.isRailOnly }

    /// The Cockpit follows a train live (docs/RADAR_COCKPIT.md). From a Zeitreise only a train the live radar knows: a train that starts
    /// later has no live position, and the Zeitreise's calculated one must not be handed on as one that was seen now.
    func cockpitEntry(for vehicle: RadarVehicle) -> ((RadarVehicle, TripDetails?) -> Void)? {
        guard !travel.isAway || model.latestVehicle(vehicle.tripID) != nil else { return nil }
        return { run, details in pendingCockpit = cockpitLaunch(run, details) }
    }

    /// The groups the map draws: the Zeitreise's while away from now, the live radar's otherwise.
    var shownClusters: [RadarCluster] { travel.isAway ? travel.clusters : model.clusters }

    func shownPin(_ id: String) -> RadarPin? { travel.isAway ? travel.pinsByID[id] : model.pinsByID[id] }

    /// What answers the Zeitreise's requests: the real radar through the gate, or the synthetic fleet in every demo.
    var timeService: (any RadarService)? {
        if preset.isTimeDemo { return RadarTimeDemoService(stallAfter: preset == .timeTravelLoading ? 3 : nil) }
        if app.live.isDemo || preset.isDenseDemo || preset.isHeatDemo { return RadarTimeDemoService() }
        return radarService
    }

    /// The last ten minutes of the selected train's projected path: one line on a light casing, fading from pale (ten minutes ago) to strong
    /// (now). Two overlays, not one per minute: they are replaced 12 times a second while the markers glide, and with eleven of them the CI
    /// capture of the playing scene showed one short piece one to two seconds of playback behind its train (run 43415316339). Review 1 also
    /// found the first half of the old trail invisible (18 % on no casing).
    @MapContentBuilder var timeTrailLayer: some MapContent {
        let points = travel.trail.map(\.clCoordinate)
        if points.count > 1 {
            let dark = mapStyle == .dark || colorScheme == .dark
            MapPolyline(coordinates: points)
                .stroke(.white.opacity(dark ? 0.30 : 0.85), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
            MapPolyline(coordinates: points)
                .stroke(LinearGradient(colors: [Theme.dusk.opacity(0.35), Theme.dusk], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
        }
    }

    /// The CI scenes (`RadarTimeScreenshotHost`): synthetic trains, the scrubber open at +45 minutes; playing from 30 minutes back, zoomed to the Westbahn with
    /// one train selected; loading, stuck at three snapshots.
    func applyTimePreset(_ preset: RadarPreset) {
        layersRaw = MapLayerSelection(layers: [.trains]).storageValue   // only the trains: the scene is about them
        travel.demo = true
        switch preset {
        case .timeTravelPlaying:
            // Close enough that ten minutes of a fast train (about 22 km) are a trail longer than its plate (review 1: at a span of one
            // degree the trail was one plate long and hid under it and its neighbours).
            camera = .region(MKCoordinateRegion(center: GeoPoint(latitude: 48.2, longitude: 15.6).clCoordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.6)))
            travel.applyDemo(minutes: -30, playing: true, featured: ("RJX 60", GeoPoint(latitude: 48.2, longitude: 15.6)))
        case .timeTravelLoading:
            travel.applyDemo(minutes: 45, playing: false)
        case .timeTravelChip:   // the past, with the card folded to its chip: "Rückblick" in the banner, the time and the way back in the chip
            travel.applyDemo(minutes: -15, playing: false)
            travel.close()
        default:
            travel.applyDemo(minutes: 45, playing: false)
        }
    }
}

/// The hooks the radar view needs for the Zeitreise in one modifier: the loop, and what changes under the picture.
struct RadarTimeHooks: ViewModifier {
    var travel: RadarTimeModel
    var model: RadarModel
    var service: (any RadarService)?
    var available: Bool
    var sceneActive: Bool

    private var runs: Bool { available && sceneActive && travel.isActive }

    func body(content: Content) -> some View {
        content
            // The loop runs while the Zeitreise is open or away from now and the radar is visible; leaving the radar or the layer ends it
            // together with every request on its way.
            .task(id: runs) {
                guard runs, let service else { return }
                await travel.run(service: service, live: model)
            }
            .onChange(of: available) { _, on in if !on { travel.reset() } }
            .onChange(of: model.filter) { _, _ in travel.filterChanged() }
            .onChange(of: model.box) { _, _ in travel.viewChanged() }
            .onChange(of: model.mapSize) { _, _ in travel.viewChanged() }
            .onChange(of: model.selectedTripID) { _, _ in travel.selectionChanged() }
            .onChange(of: model.routeTripID) { _, id in if let id { travel.noteDetails(tripID: id) } }
            .onChange(of: model.route.count) { _, _ in if let id = model.routeTripID { travel.noteDetails(tripID: id) } }
    }
}
