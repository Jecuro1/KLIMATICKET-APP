import SwiftUI
import MapKit
import SwiftData
import KlimaCore

// The map layers of the Zug-Radar: stations, route sketches, layer panel (split from RadarView.swift).

extension RadarView {
    // MARK: Layers (docs/OEBB_LIVE.md §R10)

    var layers: MapLayerSelection { MapLayerSelection(storageValue: layersRaw) }

    func toggleLayer(_ layer: MapLayer) {
        var next = layers
        next.toggle(layer)
        layersRaw = next.storageValue
    }

    /// Why the train layer is off, in words that match the reason: without consent it names the setting, offline it says the
    /// trains come back online. Stations and saved routes do not depend on any of this.
    @ViewBuilder func trainsOffNotice(_ reason: LiveDataService.Unavailable) -> some View {
        switch reason {
        case .consentUndecided, .declined, .switchedOff:
            PlannerNoticeCard(symbol: "train.side.front.car", title: "Züge brauchen Live-Daten",
                              message: "Die Zugpositionen fragt KlimaBilanz bei der ÖBB ab. Das geht erst, wenn du Live-Daten einschaltest. Stationen und Routen funktionieren weiter.",
                              actionTitle: "Einstellungen") {
                app.isShowingSettings = true
            }
        case .killSwitch(let notice):
            PlannerNoticeCard(symbol: "exclamationmark.shield", title: "Züge gerade aus",
                              message: notice ?? "Die Zugpositionen sind gerade abgeschaltet. Stationen und Routen funktionieren weiter.",
                              actionTitle: nil, action: nil)
        case .offline:
            PlannerNoticeCard(symbol: "wifi.slash", title: "Züge offline",
                              message: "Ohne Internet gibt es keine Zugpositionen. Stationen und Routen funktionieren weiter.",
                              actionTitle: nil, action: nil)
        }
    }

    func stationPin(_ station: Station) -> MapStationPin {
        MapStationPin(id: station.id, name: station.name, coordinate: GeoPoint(latitude: station.lat, longitude: station.lon))
    }

    /// Stations in the box, only when the view is close enough. Computed from the bundled index: no request.
    func refreshStations(box: RadarBox, span: Double) {
        stationPins = MapStations.isDrawn(latitudeSpan: span) ? MapStations.visible(allStations, in: box) : []
    }

    private var stationClusters: [MapCluster] {
        MapClustering.group(stationPins, cellDegrees: RadarClustering.cellSize(forLatitudeSpan: model.spanDegrees))
    }

    private var stationsByID: [String: MapStationPin] {
        Dictionary(stationPins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The straight-line sketch of each saved route whose places are known, and the number of routes without a place.
    private var routeSketches: [[GeoPoint]] {
        favorites.compactMap { route in
            MapRouteSketch.points([place(route.fromStationID), place(route.toStationID)])
        }
    }

    private var routesWithoutPlace: Int { favorites.count - routeSketches.count }

    private func place(_ stationID: String?) -> GeoPoint? {
        guard let stationID, let station = app.stations.station(id: stationID) else { return nil }
        return GeoPoint(latitude: station.lat, longitude: station.lon)
    }

    @MapContentBuilder var stationLayer: some MapContent {
        ForEach(stationClusters) { cluster in
            if cluster.isSingle, let id = cluster.memberIDs.first, let station = stationsByID[id] {
                Annotation(station.name, coordinate: station.coordinate.clCoordinate, anchor: .bottom) {
                    Button { openDepartures(stationID: id) } label: { StationMapMarker(name: station.name) }
                        .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)   // the marker has its name on a capsule
            } else {
                Annotation("\(cluster.count) Stationen", coordinate: cluster.center.clCoordinate, anchor: .center) {
                    Button { zoom(toStations: cluster.center) } label: { StationClusterBubble(count: cluster.count) }
                        .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
        }
    }

    @MapContentBuilder var routeLayer: some MapContent {
        ForEach(Array(routeSketches.enumerated()), id: \.offset) { _, points in
            MapPolyline(coordinates: points.map(\.clCoordinate))
                .stroke(Theme.accent.opacity(0.85), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [7, 6]))
        }
    }

    /// Station → its departures in the Fahrplan, the same way the trip sheet opens a stop.
    private func openDepartures(stationID: String) {
        showBoard { app.planner.showBoard(stationID: stationID) }
    }

    /// Closes the radar and shows a departures board in the Fahrplan. Opened from the train search, the search closes too:
    /// the board would otherwise open behind its cover and the tap would seem to do nothing.
    func showBoard(_ show: () -> Void) {
        if let closeSearch {
            show()
            closeSearch()
        } else {
            dismiss()
            app.selectedTab = .planner
            show()
        }
    }

    func zoom(toStations center: GeoPoint) {
        let span = max(model.spanDegrees / 3, 0.02)
        camera = .region(MKCoordinateRegion(center: center.clCoordinate,
                                            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span * 1.4)))
    }

    /// The layer bar with what each layer needs: the zoom hint, the disruption list, the routes without a place.
    var mapLayerPanel: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if layers.isOn(.stations), !MapStations.isDrawn(latitudeSpan: model.spanDegrees) {
                Text("Zoom näher heran, dann erscheinen die Stationen.")
                    .radarHint()
            }
            if layers.isOn(.disruptions) {
                Button { showsDisruptions = true } label: {
                    Label("Störungen ansehen", systemImage: "exclamationmark.triangle")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
            }
            if layers.isOn(.routes) {
                if !routeSketches.isEmpty {
                    Text("Luftlinie zwischen den Haltestellen, nicht die Strecke.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                if routesWithoutPlace > 0 {
                    Button { showsRoutes = true } label: {
                        Label("\(routesWithoutPlace) ohne Ort: Liste", systemImage: "list.bullet")
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                }
            }
            MapLayerBar(selection: layers, onToggle: toggleLayer)
        }
    }
}
