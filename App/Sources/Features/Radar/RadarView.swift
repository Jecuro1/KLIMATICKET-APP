import SwiftUI
import MapKit
import KlimaCore

// Zug-Radar (docs/OEBB_LIVE.md §R): live vehicle positions in Austria on a map. Budget-aware: one request every 20 s,
// only while the screen is visible and the app is active; a map move refreshes once when it ends.

/// Transport modes the radar can show (server-side product filter).
enum RadarMode: CaseIterable, Identifiable {
    case rail, suburban, bus, tram, subway
    var id: Self { self }

    var title: String {
        switch self {
        case .rail: "Züge"
        case .suburban: "S-Bahn"
        case .bus: "Bus"
        case .tram: "Bim"
        case .subway: "U-Bahn"
        }
    }

    var symbol: String {
        switch self {
        case .rail: "tram.fill"
        case .suburban: "tram"
        case .bus: "bus"
        case .tram: "tram.fill.tunnel"
        case .subway: "tram.circle"
        }
    }

    var products: ProductMask {
        switch self {
        case .rail: .rail
        case .suburban: .suburban
        case .bus: .bus
        case .tram: .tram
        case .subway: .subway
        }
    }
}

/// Live copy for failures (Du-Form, no technical codes).
enum LiveMessage {
    static func text(for error: Error) -> String {
        guard let live = error as? LiveError else { return "Das hat gerade nicht geklappt. Versuch es gleich noch einmal." }
        switch live {
        case .offline, .network, .timeout: return "Keine Verbindung zu ÖBB – versuch es gleich noch einmal."
        case .rateLimited: return "ÖBB bittet um eine kurze Pause. Gleich geht es weiter."
        case .circuitOpen: return "Die Abfrage pausiert gerade. Probier es später noch einmal."
        case .blocked: return "ÖBB lässt gerade keine Abfragen zu. Bitte später erneut versuchen."
        case .disabled: return "Live-Daten sind gerade nicht verfügbar."
        default: return "Die Auskunft ist gerade nicht verfügbar."
        }
    }
}

@MainActor
@Observable
final class RadarModel {
    enum Load: Equatable { case idle, loading, loaded, failed(String) }

    var modes: Set<RadarMode> = [.rail]
    var box: RadarBox = .austria
    private(set) var vehicles: [RadarVehicle] = []
    private(set) var updatedAt: Date?
    private(set) var load: Load = .idle

    /// Server cap per answer (`maxJny`): a full answer means the map is zoomed out too far.
    static let serverCap = 256

    var products: ProductMask {
        modes.reduce(into: ProductMask(rawValue: 0)) { $0.formUnion($1.products) }
    }

    var isTruncated: Bool { vehicles.count >= Self.serverCap }

    func toggle(_ mode: RadarMode) {
        if modes.contains(mode) {
            guard modes.count > 1 else { return }   // at least one mode stays on
            modes.remove(mode)
        } else {
            modes.insert(mode)
        }
    }

    func refresh(_ service: any RadarService, now: Date = Date()) async {
        guard box.isValid else { return }
        if vehicles.isEmpty { load = .loading }
        do {
            let snapshot = try await service.radar(RadarQuery(box: box, when: now, products: products))
            vehicles = snapshot.vehicles
            updatedAt = snapshot.realtimeUpdatedAt ?? now
            load = .loaded
        } catch is CancellationError {
            return
        } catch {
            load = .failed(LiveMessage.text(for: error))
        }
    }
}

struct RadarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = RadarModel()
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: RadarBox.austria.center.clCoordinate, span: MKCoordinateSpan(latitudeDelta: 4.2, longitudeDelta: 9.0)))
    @State private var selected: RadarVehicle?

    /// Restarts the refresh loop when the filters, the visible area or the activity change.
    private struct RunKey: Hashable {
        var products: ProductMask
        var box: [Int]
        var active: Bool
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if let reason = app.live.timetableUnavailable {
                    ScrollView {
                        PlannerUnavailableView(reason: reason, onSettings: {})
                            .padding(Theme.Spacing.cardGutter)
                    }
                } else {
                    map
                    statusBar
                }
            }
            .ambientBackground(.standard, glow: 0.3)
            .navigationTitle("Zug-Radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) { modeChips }
            .task(id: RunKey(products: model.products, box: boxKey, active: isRunning)) {
                guard isRunning, let service = app.live.radar else { return }
                while !Task.isCancelled {
                    await model.refresh(service)
                    try? await Task.sleep(for: .seconds(20))
                }
            }
            .sheet(item: $selected) { vehicle in
                RadarTripSheet(vehicle: vehicle)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var isRunning: Bool {
        scenePhase == .active && app.live.timetableUnavailable == nil
    }

    /// The visible rectangle at 0.01° resolution, so small camera moves do not restart the loop.
    private var boxKey: [Int] {
        [model.box.north, model.box.west, model.box.south, model.box.east].map { Int(($0 * 100).rounded()) }
    }

    private var map: some View {
        Map(position: $camera, interactionModes: .all) {
            ForEach(model.vehicles) { vehicle in
                Annotation(vehicle.line.map { LinePresentation.title($0) } ?? "Zug",
                           coordinate: vehicle.coordinate.clCoordinate, anchor: .center) {
                    Button { selected = vehicle } label: { RadarMarker(vehicle: vehicle) }
                        .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            let r = context.region
            model.box = RadarBox(north: r.center.latitude + r.span.latitudeDelta / 2,
                                 west: r.center.longitude - r.span.longitudeDelta / 2,
                                 south: r.center.latitude - r.span.latitudeDelta / 2,
                                 east: r.center.longitude + r.span.longitudeDelta / 2)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var modeChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(RadarMode.allCases) { mode in
                    Chip(title: mode.title, symbol: mode.symbol, isSelected: model.modes.contains(mode)) {
                        model.toggle(mode)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .scrollIndicators(.hidden)
    }

    private var statusBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            switch model.load {
            case .failed(let message):
                PlannerNoticeCard(symbol: "wifi.exclamationmark", title: "Radar pausiert", message: message,
                                  actionTitle: "Erneut versuchen") { Task { if let s = app.live.radar { await model.refresh(s) } } }
            default:
                EmptyView()
            }
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "dot.radiowaves.left.and.right")
                if let updatedAt = model.updatedAt {
                    Text("Stand \(Format.time(updatedAt)) · \(model.vehicles.count) Fahrzeuge")
                } else {
                    Text(model.load == .loading ? "Lade Fahrzeuge …" : "Noch keine Positionen")
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            if model.isTruncated {
                Text("Nur die ersten \(RadarModel.serverCap) Fahrzeuge im Ausschnitt. Zoom näher heran, dann siehst du alle.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.l)
            }
        }
        .padding(.bottom, Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .motionAnimation(Motion.smooth, value: model.load)
    }
}

/// One vehicle on the map: its line plate in the mode colour.
struct RadarMarker: View {
    var vehicle: RadarVehicle

    var body: some View {
        let mode = vehicle.line?.mode ?? .other
        Text(vehicle.line.map { LinePresentation.plate($0) }.flatMap { $0.isEmpty ? nil : $0 } ?? "•")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.modeColor(mode), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .accessibilityLabel(vehicle.line.map { LinePresentation.title($0) } ?? "Fahrzeug")
            .accessibilityHint(vehicle.direction.map { "Richtung \($0)" } ?? "")
    }
}

extension RadarVehicle {
    /// Follows the whole run: first stop to last stop (the vehicle has no planner context).
    var followTarget: LiveFollowTarget? {
        guard let first = stopovers.first, let last = stopovers.last else { return nil }
        return LiveFollowTarget(tripID: tripID, lineName: line.map { LinePresentation.title($0) } ?? "Zug",
                                boardingStop: first.location, alightStop: last.location,
                                plannedDeparture: first.departure?.planned, plannedArrival: last.arrival?.planned)
    }
}

extension GeoPoint {
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// Details of one vehicle: direction, the run with realtime, and „Live verfolgen“.
struct RadarTripSheet: View {
    let vehicle: RadarVehicle

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if let line = vehicle.line {
                        HStack(spacing: Theme.Spacing.s) {
                            PlannerLinePlate(line: line, size: .m)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LinePresentation.title(line)).font(Theme.Typography.title)
                                if let direction = vehicle.direction {
                                    Text("Richtung \(direction)").font(.subheadline).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    Button { startFollowing() } label: {
                        Label("Live verfolgen", systemImage: "location.fill").frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.primary)
                    .disabled(vehicle.stopovers.count < 2)
                    stopsList
                }
                .padding(Theme.Spacing.cardGutter)
            }
            .ambientBackground(.standard, glow: 0.3)
            .navigationTitle("Fahrt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Schließen") { dismiss() } } }
        }
    }

    private var stopsList: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(Array(vehicle.stopovers.enumerated()), id: \.offset) { _, stop in
                    let event = stop.departure ?? stop.arrival
                    HStack {
                        Text(stop.location.name).font(.body)
                        Spacer()
                        if let event {
                            let label = RealtimePresentation.label(event)
                            if let text = label.text {
                                Text(text).font(.footnote.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(label.state == .onTime ? Theme.positiveText : Theme.summitText)
                            }
                        }
                    }
                }
            }
        }
    }

    private func startFollowing() {
        guard let target = vehicle.followTarget else { return }
        LiveFollowTracker.shared.start(target, live: app.live)
        dismiss()
    }
}
