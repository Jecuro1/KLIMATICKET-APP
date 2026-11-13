import SwiftUI
import MapKit
import KlimaCore

// MARK: radarheat – the Pünktlichkeit layer on the radar's map (docs/RADAR_HEATMAP.md). The cells are map overlays (`MapPolygon`, at
// most `HeatLayer.maxOverlays` = 900 of them whatever the number of trains), drawn between the base map's roads and its labels;
// the trains stay on the map as small dots; a tap on the map finds the cell under the finger. Everything here hangs off the radar
// view through a few small hooks (`RadarView.swift`, `RadarView+Controls.swift`).

extension RadarView {
    /// The layer is on and the live data is allowed: the radar loads all of Austria for it (`RadarModel.setHeat`). Not while the Zeitreise
    /// shows another time (docs/RADAR_TIMETRAVEL.md): the numbers are about now, and next to a map of tonight they would be a lie.
    var heatOn: Bool {
        layers.isOn(.punctuality) && app.live.timetableUnavailable == nil && !travel.isAway
    }

    /// Something needs the radar's requests: the train layer or the Pünktlichkeit layer.
    var loadsRadar: Bool { trainsOn || heatOn }

    /// The base map's appearance as the cells see it (the "Dunkel" map style forces the dark palette).
    private var heatScheme: ColorScheme { mapStyle == .dark ? .dark : colorScheme }

    /// How wide a cell is on the screen now, in points (0.12° of latitude between two centres).
    private var heatCellPoints: Double {
        HeatGrid.spacingDegrees / max(model.spanDegrees, 0.001) * Double(model.mapSize.height)
    }

    // MARK: Map content

    /// The cells, the hot spot numbers and the outline of the selected cell.
    @MapContentBuilder var heatContent: some MapContent {
        let palette = HeatPalette(scheme: heatScheme)
        let detailed = heatCellPoints >= 28
        ForEach(model.heat.shown) { cell in
            if cell.isNeutral {
                // Too few trains for a colour: faint grey. Close enough to read the pattern (a cell about 28 points wide) it has a dashed
                // edge and diagonal hatching; on the country view, where a cell is 18 points, it is a faint outline (the pattern would
                // only be noise).
                MapPolygon(coordinates: HeatGeometry.ring(cell.id, scale: 0.9))
                    .foregroundStyle(palette.neutralFill)
                    .stroke(palette.neutralLine.opacity(detailed ? 1 : 0.55),
                            style: detailed ? StrokeStyle(lineWidth: 1, dash: [3, 3]) : StrokeStyle(lineWidth: 0.75))
                    .mapOverlayLevel(level: .aboveRoads)
                if detailed {
                    MapPolyline(coordinates: HeatGeometry.hatch(cell.id))
                        .stroke(palette.neutralLine, lineWidth: 1)
                        .mapOverlayLevel(level: .aboveRoads)
                }
            } else {
                // Three nested hexagons: a scrim (the cell's ground and bezel), the colour as a wide faint halo (the soft edge), and the
                // body with its crisp line. The strength of the cell (how many trains it rests on) scales every opacity.
                let colour = palette.color(cell.blend)
                MapPolygon(coordinates: HeatGeometry.ring(cell.id, scale: 1.12))
                    .foregroundStyle(palette.scrim.opacity(palette.scrimOpacity * cell.strength))
                    .mapOverlayLevel(level: .aboveRoads)
                MapPolygon(coordinates: HeatGeometry.ring(cell.id, scale: 1.45))
                    .foregroundStyle(colour.opacity(palette.haloOpacity * cell.strength))
                    .mapOverlayLevel(level: .aboveRoads)
                MapPolygon(coordinates: HeatGeometry.ring(cell.id, scale: 0.92))
                    .foregroundStyle(colour.opacity(palette.bodyOpacity * cell.strength))
                    .stroke(colour.opacity(palette.bodyLine * cell.strength), lineWidth: 1.2)
                    .mapOverlayLevel(level: .aboveRoads)
            }
        }
        if let selected = model.heat.selectedCell {
            MapPolygon(coordinates: HeatGeometry.ring(selected, scale: 1.0))
                .foregroundStyle(Color.clear)
                .stroke(Theme.textPrimary, lineWidth: 3)
                .mapOverlayLevel(level: .aboveRoads)
        }
        ForEach(model.heat.snapshot.hotspots) { spot in
            Annotation("Brennpunkt \(spot.rank)", coordinate: spot.center.clCoordinate, anchor: .center) {
                Button { openHotspot(spot) } label: {
                    HeatHotspotBadge(spot: spot, isSelected: model.heat.selectedCell == spot.cellID)
                }
                .buttonStyle(.plain)
            }
            .annotationTitles(.hidden)
        }
    }

    // MARK: Markers

    /// A train on the map: the marker with its line plate, or while the layer is on a small dot (the heat is the picture).
    @ViewBuilder func pinLabel(_ pin: RadarPin) -> some View {
        if heatOn {
            HeatTrainDot(pin: pin, isSelected: model.selectedTripID == pin.id)
        } else {
            RadarMarker(pin: pin, isSelected: model.selectedTripID == pin.id)
        }
    }

    @ViewBuilder func clusterLabel(_ cluster: RadarCluster, noun: String) -> some View {
        if heatOn {
            HeatClusterDot(cluster: cluster, noun: noun)
        } else {
            RadarClusterBubble(cluster: cluster, noun: noun)
        }
    }

    // MARK: Taps

    /// A tap on the map: the cell with trains under the finger (or the nearest within a finger's width) opens its sheet; a tap on
    /// nothing closes it. A train or a number is a button of its own and never gets here.
    func handleMapTap(at point: CGPoint, proxy: MapProxy) {
        // A trip sheet that is up (the map stays touchable behind it) keeps its place: a second sheet cannot be shown over it.
        guard heatOn, sheetVehicle == nil, let coordinate = proxy.convert(point, from: .local) else { return }
        // The gesture runs alongside the markers' own buttons, so a tap on a train dot, a group ring or a hot spot number would open
        // a cell as well as the train: it steps aside for them.
        guard !hitsMarker(at: point, proxy: proxy) else { return }
        let tap = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
        // A finger is about 24 points wide: that many kilometres at this zoom, never less than one cell.
        let height = max(Double(model.mapSize.height), 1)
        let kmPerPoint = model.spanDegrees * HeatGrid.kmPerDegreeLatitude / height
        let tolerance = max(HeatGrid.radiusKm, 24 * kmPerPoint)
        // The selection waits for a possible second tap (the map zooms in on a double tap).
        model.heat.selectAfterTap(RadarHeat.cell(at: tap, in: model.heat.snapshot, toleranceKm: tolerance)?.id)
    }

    /// The tap is on a marker of the map that is a button of its own: a hot spot number, or (with the train layer on) a train dot or a
    /// group ring. 18 points around its centre, a little more than the marker's tap area of 28 to 32.
    private func hitsMarker(at point: CGPoint, proxy: MapProxy) -> Bool {
        let reach: CGFloat = 18
        func near(_ coordinate: GeoPoint) -> Bool {
            guard let at = proxy.convert(coordinate.clCoordinate, to: .local) else { return false }
            return abs(at.x - point.x) <= reach && abs(at.y - point.y) <= reach
        }
        if model.heat.snapshot.hotspots.contains(where: { near($0.center) }) { return true }
        guard trainsOn else { return false }
        return model.clusters.contains { cluster in
            if cluster.isSingle, let id = cluster.tripIDs.first, let pin = model.pinsByID[id] { return near(pin.coordinate) }
            return near(cluster.center)
        }
    }

    /// A hot spot of the panel or the map: its cell opens and the map comes close enough to see the cells around it.
    func openHotspot(_ spot: HeatHotspot) {
        model.heat.select(spot.cellID)
        if model.spanDegrees > 1.5 {
            camera = .region(MKCoordinateRegion(center: spot.center.clCoordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 1.1, longitudeDelta: 1.5)))
        }
    }

    /// A train of the lists: its trip sheet opens (on top of the cell sheet when that is up) and the map follows.
    func openTrain(_ tripID: String) {
        guard let vehicle = model.vehicle(id: tripID) else { return }
        model.selectedTripID = tripID
        if model.heat.selectedCell != nil { model.heat.trainSheet = vehicle } else { sheetVehicle = vehicle }
    }

    // MARK: Panel and sheets

    var heatPanel: some View {
        RadarHeatPanel(model: model, onTrain: openTrain, onHotspot: openHotspot)
    }

    func heatCellSheet(for id: HeatCellID) -> some View {
        RadarHeatCellSheet(model: model, cellID: id) { vehicle in
            tripSheet(for: vehicle)
        }
        .presentationDetents([.fraction(0.42), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.42)))
    }

    /// The trip sheet as the radar shows it (the same wiring as the sheet of a tapped train).
    func tripSheet(for vehicle: RadarVehicle) -> some View {
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
    }

    /// The bottom area takes more room while the heat panel is up: the card (at most 62 % of the map, 80 % at the accessibility sizes,
    /// scrolling inside, see `RadarHeatPanel.maxHeight`) and under it the layer bar, which must stay reachable: it is how the layer is
    /// switched off again. The area grows with its content up to the card's own limit plus the room for the bar and a note.
    var statusMaxHeight: CGFloat {
        if travel.isOpen { return max(360, model.mapSize.height * 0.58) }   // MARK: radartime – the open scrubber card
        guard heatOn else { return 360 }
        let mapHeight = max(model.mapSize.height, 560)
        // Normal sizes: the card at its limit and the room under it for the layer bar and a note. Accessibility sizes: as before, the
        // whole area scrolls (the card alone is up to 80 % there).
        return heatTypeSize.isAccessibilitySize ? max(360, model.mapSize.height * 0.78) : max(360, mapHeight * 0.62 + 240)
    }

    // MARK: Presets

    /// CI screenshots launch one scene after another in one simulator, and the layer choice is stored per device (`@AppStorage`): a scene
    /// of another preset would show the heat layer a heat scene left behind. Only in screenshot and perf runs, never for a person.
    func dropHeatLayerInScreenshots() {
        guard LaunchMode.isSandboxed, !preset.isHeatDemo, layers.isOn(.punctuality) else { return }
        toggleLayer(.punctuality)
    }

    /// The CI scenes (`RadarHeatScreenshotHost`): demo trains with a delay cluster over Tirol and a quiet rest of the country.
    func applyHeatPreset(_ preset: RadarPreset) {
        layersRaw = MapLayerSelection(layers: [.stations, .trains, .punctuality]).storageValue
        switch preset {
        case .heatPanel, .heatAX5:
            model.heat.isExpanded = true
        case .heatLists:
            model.heat.isExpanded = true
            model.heat.scrollsToLists = true
        case .heatTrend:   // the open panel at its trend line, which needs six minutes of an open radar: made up for the scene
            model.heat.isExpanded = true
            model.heat.scrollsToTrend = true
            model.heat.seedDemoTrend(endingAt: Date())
        case .heatCell:   // the map close to Tirol, the cell of the largest hot spot open
            camera = .region(MKCoordinateRegion(center: GeoPoint(latitude: 47.28, longitude: 11.55).clCoordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 1.1, longitudeDelta: 1.5)))
            model.heat.opensFirstHotspot = true
        default:
            break
        }
    }
}

/// The hooks the radar view needs for the layer in one modifier: the layer's switch reaches the model, and the sheet of a cell.
struct RadarHeatHooks<CellSheet: View>: ViewModifier {
    var model: RadarModel
    var isOn: Bool
    var cellSheet: (HeatCellID) -> CellSheet

    func body(content: Content) -> some View {
        content
            .onChange(of: isOn, initial: true) { _, on in model.setHeat(enabled: on) }
            .sheet(item: Binding(get: { model.heat.selectedCell }, set: { model.heat.select($0) })) { id in
                cellSheet(id)
            }
    }
}
