import SwiftUI
import MapKit
import KlimaCore

/// What the connection map draws: every ride leg in its mode's colour along its polyline (or, until that is loaded, along
/// its stops), walks dashed, the changes as dots and start and destination as markers (docs/OEBB_LIVE.md §E3 „Detail“).
struct PlannerMapRoute: Equatable {
    struct Leg: Equatable {
        var path: [CLLocationCoordinate2D]
        var mode: TransportMode
        var isWalk: Bool

        static func == (a: Leg, b: Leg) -> Bool {
            a.mode == b.mode && a.isWalk == b.isWalk && a.path.count == b.path.count
                && zip(a.path, b.path).allSatisfy { $0.latitude == $1.latitude && $0.longitude == $1.longitude }
        }
    }

    struct Stop: Equatable {
        var name: String
        var coordinate: CLLocationCoordinate2D

        static func == (a: Stop, b: Stop) -> Bool {
            a.name == b.name && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
        }
    }

    var legs: [Leg]
    var start: Stop?
    var end: Stop?
    var changes: [Stop]
    var startMode: TransportMode

    var allPoints: [CLLocationCoordinate2D] { legs.flatMap(\.path) }
    var isEmpty: Bool { allPoints.count < 2 }

    /// The route of a journey. `polylines` holds the full run of a ride leg by leg id (cut to the leg here); a leg without
    /// one is drawn through its stops, a walk as a straight line.
    static func make(journey: Journey, polylines: [String: [GeoPoint]]) -> PlannerMapRoute {
        func c(_ p: GeoPoint) -> CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude) }
        var legs: [Leg] = []
        for leg in journey.legs {
            var points: [GeoPoint] = []
            if leg.kind == .ride {
                if let line = leg.polyline, line.count >= 2 {
                    points = line
                } else if let full = polylines[leg.id], full.count >= 2, let a = leg.origin.coordinate, let b = leg.destination.coordinate {
                    points = cut(full, from: a, to: b)
                }
                if points.count < 2 { points = leg.stopovers.filter { !$0.passesWithoutStop }.compactMap(\.location.coordinate) }
            }
            if points.count < 2 { points = [leg.origin.coordinate, leg.destination.coordinate].compactMap { $0 } }
            guard points.count >= 2 else { continue }
            legs.append(Leg(path: points.map(c), mode: leg.line?.mode ?? .other, isWalk: leg.kind != .ride))
        }
        let rides = journey.rideLegs
        let first = rides.first ?? journey.legs.first, last = rides.last ?? journey.legs.last
        func stop(_ location: Location?) -> Stop? {
            guard let location, let coordinate = location.coordinate else { return nil }
            return Stop(name: DisplayNames.name(location.name), coordinate: c(coordinate))
        }
        let changes = zip(rides, rides.dropFirst()).compactMap { stop($0.0.destination) }
        return PlannerMapRoute(legs: legs, start: stop(first?.origin), end: stop(last?.destination), changes: changes,
                               startMode: first?.line?.mode ?? .train)
    }

    /// The part of a run between the points nearest to `a` and `b`.
    static func cut(_ full: [GeoPoint], from a: GeoPoint, to b: GeoPoint) -> [GeoPoint] {
        func nearest(_ target: GeoPoint) -> Int {
            full.indices.min { full[$0].distanceKm(to: target) < full[$1].distanceKm(to: target) } ?? 0
        }
        let i = nearest(a), j = nearest(b)
        if i == j { return [a, b] }
        return i < j ? Array(full[i...j]) : Array(full[j...i].reversed())
    }
}

/// The inline map card: not interactive, a button opens the full map.
struct ConnectionMapView: View {
    var route: PlannerMapRoute
    var interactive = false
    var height: CGFloat? = 190
    var onExpand: (() -> Void)? = nil

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: interactive ? .all : []) {
            ForEach(Array(route.legs.enumerated()), id: \.offset) { _, leg in
                if leg.isWalk {
                    MapPolyline(coordinates: leg.path)
                        .stroke(Theme.textSecondary, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 6]))
                } else {
                    MapPolyline(coordinates: leg.path)
                        .stroke(Theme.modeColor(leg.mode), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            ForEach(Array(route.changes.enumerated()), id: \.offset) { _, stop in
                Annotation(stop.name, coordinate: stop.coordinate, anchor: .center) { TripListViaMapDot() }
            }
            if let start = route.start {
                Marker(start.name, systemImage: route.startMode.symbolName, coordinate: start.coordinate).tint(Theme.modeColor(route.startMode))
            }
            if let end = route.end {
                Marker(end.name, systemImage: "flag.fill", coordinate: end.coordinate).tint(Theme.summit)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(minHeight: height ?? 0, maxHeight: height ?? .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.formGroup, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if let onExpand {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 38, height: 38)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .padding(8)
                .accessibilityLabel("Karte vergrößern")
            }
        }
        .allowsHitTesting(interactive || onExpand != nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Karte der Verbindung")
        .accessibilityValue("\(route.start?.name ?? "") nach \(route.end?.name ?? "")")
    }

    /// Frames every point with room for the marker balloons above the line.
    private var region: MKCoordinateRegion {
        let points = route.allPoints
        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        let minLat = lats.min() ?? 47.5, maxLat = lats.max() ?? 47.5
        let minLon = lons.min() ?? 13, maxLon = lons.max() ?? 13
        let latDelta = max((maxLat - minLat) * 1.7, 0.03)
        let lonDelta = max((maxLon - minLon) * 1.35, 0.03)
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 + latDelta * 0.06, longitude: (minLon + maxLon) / 2)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }
}

/// The full-screen map (pan and zoom).
struct ConnectionMapSheet: View {
    var route: PlannerMapRoute
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ConnectionMapView(route: route, interactive: true, height: nil)
                .clipShape(Rectangle())
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Karte")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.fontWeight(.semibold) } }
        }
    }
}
