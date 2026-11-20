import SwiftUI
import UIKit
import MapKit
import KlimaCore

// MARK: radar2-mine – „Meine Fahrzeuge“ on the radar view (docs/RADAR_MINE.md, specs/radar2/radarmine.md). Through the radar2 seam only: the chip
// „Meine“ at the start of the mode chips (it also carries the hooks that hand the model what is on and open), the panel above the status card, the map
// content of the stop page (the stop, the numbered board pins, the dashed lines) and of „In der Nähe“ (the radius and the dot), and the decoration of
// each marker (star, number, dimmed).

/// One numbered arrival on the map: where its vehicle is drawn (the radar's marker or the board's position) and whether that is a board pin of its own.
struct RadarMineMapArrival: Identifiable {
    var id: String
    var number: Int
    var point: GeoPoint
    var isBoardPin: Bool
    /// MARK: radar2-review-radarmine – the position is the board's (dashed outline); false: the radar's, whose marker the filter hides.
    var fromBoard: Bool
    var mode: TransportMode
    var title: String
    var isStale: Bool
}

extension RadarView {
    // MARK: Seam

    @MapContentBuilder var mineMapContent: some MapContent {
        let mine = model.radar2.mine
        if trainsOn, mine.stopPageShown, let stop = mine.stop {
            let arrivals = mineMapArrivals
            ForEach(arrivals) { arrival in
                MapPolyline(coordinates: [arrival.point.clCoordinate, stop.coordinate.clCoordinate])
                    .stroke(Theme.textSecondary, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
            }
            // MARK: radar2-review-radarmine – the stop first; while numbers are on the map only its dot (the name stands in the panel's „Ab …“): in the
            // CI screenshots number 3 hid under the capsule „Neubaugasse (Demo)“
            Annotation(stop.name, coordinate: stop.coordinate.clCoordinate, anchor: .bottom) {
                RadarMineStopMarker(name: stop.name, showsName: arrivals.isEmpty)
            }
            .annotationTitles(.hidden)
            ForEach(arrivals.filter(\.isBoardPin)) { arrival in
                Annotation(arrival.title, coordinate: arrival.point.clCoordinate, anchor: .center) {
                    Button { mineFocus(arrival.point, with: stop.coordinate) } label: {
                        RadarMineBoardPin(number: arrival.number, mode: arrival.mode, isStale: arrival.isStale, fromBoard: arrival.fromBoard)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Nummer \(arrival.number), \(arrival.title), Position berechnet")
                }
                .annotationTitles(.hidden)
            }
        }
        if let fix = mine.fix, mine.isOpen, mine.page == .near {
            MapCircle(center: fix.clCoordinate, radius: RadarNearby.radiusKm * 1000)
                .foregroundStyle(Theme.accent.opacity(0.06))
                .stroke(Theme.accent, lineWidth: 1)
            if mine.hasLiveFix {
                UserAnnotation()   // only after the tap, while its fix is held
            } else if mine.fixIsSynthetic {
                Annotation(RadarMineText.demoPlace, coordinate: fix.clCoordinate, anchor: .center) { RadarMineUserDot() }
                    .annotationTitles(.hidden)
            }
        }
    }

    @ViewBuilder var mineTopBarChip: some View {
        if RadarMineEntry.isShown {
            RadarMineChip(mine: model.radar2.mine) { toggleMinePanel() }
                .modifier(RadarMineHooks(model: model, gate: gate, live: app.live, shownModes: mineShownModes, camera: $camera))
        }
    }

    @ViewBuilder var minePanel: some View {
        let mine = model.radar2.mine
        if mine.isOpen {
            RadarMinePanel(mine: mine, context: mineContext, windowHeight: mineWindowHeight)
                .motionTransition(.lift)
        }
    }

    var minePanelIsOpen: Bool { model.radar2.mine.isOpen }

    /// The height of the radar's screen. Not the map's: the map shrinks while the panel takes room at the bottom, and a panel sized from it shrank
    /// with it (CI screenshots run 2). About a third of it leaves the stop and its numbered arrivals on the map above.
    var mineWindowHeight: CGFloat {
        let height = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.height ?? 0
        return height > 0 ? height : 844
    }

    func mineDecoration(_ pin: RadarPin) -> RadarMarkerDecoration {
        model.radar2.mine.decoration(for: pin)
    }

    /// The opacity of a group of markers (read by the radar's group bubble, one marked line in `Heat/RadarView+Heat.swift`).
    func mineGroupOpacity(_ cluster: RadarCluster) -> Double {
        model.radar2.mine.groupOpacity(cluster.tripIDs) { model.pinsByID[$0]?.vehicle }
    }

    /// MARK: radar2-review-radarmine – the star on a group that holds a vehicle of your lines (more than 60 of them are on the map), and its words for
    /// VoiceOver; nothing otherwise.
    func mineGroupDecoration(_ cluster: RadarCluster) -> RadarMarkerDecoration {
        model.radar2.mine.groupHoldsMine(cluster.tripIDs) { model.pinsByID[$0]?.vehicle } ? RadarMarkerDecoration(badge: .star) : .plain
    }

    func mineGroupSpoken(_ cluster: RadarCluster) -> String {
        mineGroupDecoration(cluster).badge == .star ? RadarMineText.groupValue : ""
    }

    // MARK: Actions

    /// „Meine“: opens the panel (the Zeitreise card closes: one bottom panel at a time) or closes it.
    func toggleMinePanel() {
        let mine = model.radar2.mine
        withMotion(Motion.smooth) {
            if mine.isOpen {
                mine.close()
            } else {
                if travel.isOpen { travel.close() }
                mine.open()
            }
        }
    }

    /// What the pages need of the radar: its vehicles, the camera, the chips and the layers.
    var mineContext: RadarMineContext {
        RadarMineContext(
            radar: model, gate: gate, shownModes: mineShownModes, mapCentre: model.box.center, stations: app.stations,
            focus: { point, span in mineFocus(point, span: span) },
            focusPair: { point, stop in mineFocus(point, with: stop) },
            select: { pin in mineSelect(pin) },
            switchOn: { modes in
                var next = model.modes
                for mode in modes { next.set(mode, on: true) }
                setModes(next)
            },
            trainsOn: { if !layers.isOn(.trains) { toggleLayer(.trains) } },
            openSettings: { app.isShowingSettings = true },
            allDepartures: { stop in
                showBoard { app.planner.showBoard(stationID: stop.id) }
            })
    }

    /// The modes whose markers are on the map now (a city mode only while the city lane is in zoom).
    var mineShownModes: Set<RadarMode> {
        Set(model.modes.ordered.filter { !$0.isCity || !model.cityOutOfZoom })
    }

    func mineFocus(_ point: GeoPoint, span: Double) {
        withMotion(Motion.smooth) {
            camera = .region(MKCoordinateRegion(center: point.clCoordinate,
                                                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span * 1.5)))
        }
    }

    /// The stop and a vehicle in one view.
    func mineFocus(_ point: GeoPoint, with stop: GeoPoint) {
        let latSpan = max(abs(point.latitude - stop.latitude) * 2.6, 0.012)
        let lonSpan = max(abs(point.longitude - stop.longitude) * 2.6, latSpan * 1.5)
        let centre = GeoPoint(latitude: (point.latitude + stop.latitude) / 2, longitude: (point.longitude + stop.longitude) / 2)
        withMotion(Motion.smooth) {
            camera = .region(MKCoordinateRegion(center: centre.clCoordinate, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)))
        }
    }

    /// A row of the panel: the vehicle is selected on the map (no second sheet over the panel), the camera comes to it.
    func mineSelect(_ pin: RadarPin) {
        model.selectedTripID = pin.id
        mineFocus(pin.coordinate, span: min(max(model.spanDegrees, 0.012), 0.05))
    }

    /// The numbered arrivals of the stop page, each at its drawn position.
    var mineMapArrivals: [RadarMineMapArrival] {
        let mine = model.radar2.mine
        let now = Date()
        return mine.arrivals.compactMap { arrival -> RadarMineMapArrival? in
            guard let number = mine.numbers[arrival.id], let board = arrival.point else { return nil }
            let isRadar = arrival.source == .radar
            let drawn = isRadar ? (model.pinsByID[arrival.tripID]?.coordinate ?? board) : board
            return RadarMineMapArrival(id: arrival.id, number: number, point: drawn, isBoardPin: !isRadar || model.pinsByID[arrival.tripID] == nil,
                                       fromBoard: !isRadar, mode: arrival.line?.mode ?? arrival.row.mode, title: arrival.row.lineTitle,
                                       isStale: RadarStopArrivals.isStale(arrival.positionAt, now: now))
        }
    }
}

/// MARK: radar2-review-radarmine – the id of a page's or hook's loop: what it is about and whether the app is active (the loop rests in the background).
struct RadarMineLoopID<Value: Equatable>: Equatable {
    var value: Value
    var active: Bool
}

/// What the pages of the panel need of the radar.
struct RadarMineContext {
    var radar: RadarModel
    var gate: RadarFeatureGate
    var shownModes: Set<RadarMode>
    var mapCentre: GeoPoint
    var stations: StationIndex
    var focus: (GeoPoint, Double) -> Void
    /// The stop and a vehicle in one view.
    var focusPair: (GeoPoint, GeoPoint) -> Void
    var select: (RadarPin) -> Void
    var switchOn: (Set<RadarMode>) -> Void
    var trainsOn: () -> Void
    var openSettings: () -> Void
    var allDepartures: (RadarMineStop) -> Void
}

/// The hooks of the part, carried by its chip (always on screen with the radar): the gate and Low Power Mode for the side job, the board source,
/// the regrouping, the highlight's single markers, the stop page's rows from the radar's newest positions, and the CI scene.
struct RadarMineHooks: ViewModifier {
    var model: RadarModel
    var gate: RadarFeatureGate
    var live: LiveDataService
    var shownModes: Set<RadarMode>
    @Binding var camera: MapCameraPosition

    private var mine: RadarMineModel { model.radar2.mine }

    func body(content: Content) -> some View {
        content
            .onChange(of: gate, initial: true) { _, gate in mine.update(gate: gate, lowPower: model.lowPower) }
            .onChange(of: model.lowPower) { _, lowPower in mine.update(gate: gate, lowPower: lowPower) }
            .onChange(of: mine.isOpen) { _, _ in mine.update(gate: gate, lowPower: model.lowPower) }
            .onChange(of: mine.page) { _, _ in mine.update(gate: gate, lowPower: model.lowPower) }
            .task {
                mine.source = RadarStopBoardSource(live: live)
                mine.regroup = { [weak model] in model?.rebuildPinsNow() }
                await applyScene()
            }
            // The highlight's single markers follow the map: every two seconds while it is on (at once when it changes). MARK: radar2-review-radarmine –
            // these loops rest while the app is not active (it may run on in the background for the Aussteige-Wecker or a recording, the radar does not
            // load then, and nothing here can change); back in front they start at once.
            // A line remembered or forgotten while the highlight is on gets its pass at once as well (its vehicles group until then).
            .task(id: RadarMineLoopID(value: mine.highlightOn ? mine.lines : nil, active: gate.sceneActive)) {
                while !Task.isCancelled {
                    mine.refreshHighlightSingles(pins: model.pins, centre: model.box.center)
                    guard mine.highlightOn, gate.sceneActive else { return }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            // The stop page's rows: with every board and every five seconds from the radar's newest markers.
            .task(id: RadarMineLoopID(value: mine.stopPageShown, active: gate.sceneActive)) {
                while !Task.isCancelled && mine.stopPageShown && gate.sceneActive {
                    refreshArrivals()
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            .onChange(of: mine.boardFetchedAt) { _, _ in
                refreshArrivals()
                frameFirstBoard()   // MARK: radar2-review-radarmine
            }
            // The modes go to the model: the loops above run in the closure of their start and would keep an old value.
            .onChange(of: shownModes, initial: true) { _, modes in
                mine.shownModes = modes
                refreshArrivals()
            }
    }

    private func refreshArrivals() {
        mine.refreshArrivals(held: RadarMineHooks.held(in: model))
    }

    /// What the radar holds of the board's trips: the drawn position and the time of the answer behind it.
    static func held(in model: RadarModel) -> [String: RadarHeldVehicle] {
        var held: [String: RadarHeldVehicle] = [:]
        for id in model.radar2.mine.boardTripIDs {
            guard let entry = model.store.entries[id] else { continue }
            held[id] = RadarHeldVehicle(coordinate: model.pinsByID[id]?.coordinate ?? entry.vehicle.coordinate, seenAt: entry.seenAt)
        }
        return held
    }

    /// MARK: radar2-review-radarmine – the chosen stop's first board: the camera frames the stop with its numbered arrivals (`RadarStopArrivals.frame`),
    /// once per stop; nothing to frame (no number on the map) keeps the stop's own view.
    private func frameFirstBoard() {
        guard mine.framePending, mine.stopPageShown, let stop = mine.stop, mine.board != nil else { return }
        mine.didFrame()
        let points = mine.arrivals.compactMap { arrival -> GeoPoint? in
            guard mine.numbers[arrival.id] != nil else { return nil }
            return arrival.source == .radar ? (model.pinsByID[arrival.tripID]?.coordinate ?? arrival.point) : arrival.point
        }
        guard !points.isEmpty, let frame = RadarStopArrivals.frame(stop: stop.coordinate, points: points) else { return }
        withMotion(Motion.smooth) {
            camera = .region(MKCoordinateRegion(center: frame.centre.clCoordinate,
                                                span: MKCoordinateSpan(latitudeDelta: frame.latitudeSpan, longitudeDelta: frame.longitudeSpan)))
        }
    }

    /// The CI scene: the camera, once the radar's own preset has run (a stop scene whose first board already framed its arrivals keeps that view).
    private func applyScene() async {
        guard let scene = RadarMineDemo.scene, let (centre, span) = scene.camera else { return }
        try? await Task.sleep(for: .milliseconds(400))
        if mine.stop != nil, !mine.framePending { return }   // MARK: radar2-review-radarmine
        camera = .region(MKCoordinateRegion(center: centre.clCoordinate, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span * 1.5)))
    }
}
