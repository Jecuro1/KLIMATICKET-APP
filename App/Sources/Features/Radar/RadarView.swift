import SwiftUI
import MapKit
import KlimaCore

// Zug-Radar (docs/OEBB_LIVE.md §R, §R7): an own full-screen view with its own train layer. The base map is MapKit, the
// system map underneath; markers, clusters, route, filter, search and status are ours. Nothing is handed to the Apple
// Maps app. Budget: one request per tile every 20 s, only while the view is visible and active, never in Low Power
// Mode and never in the background. A map move refreshes once when it ends. A truncated answer splits the view into
// quadrants (up to four requests), and the view says so when even that is cut off.

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

/// Base map styles. The train layer is the same in all of them; „Dunkel“ forces the dark map palette.
enum RadarMapStyle: String, CaseIterable, Identifiable {
    case standard, satellite, dark
    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .satellite: "Satellit"
        case .dark: "Dunkel"
        }
    }

    var symbol: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe.europe.africa"
        case .dark: "moon"
        }
    }

    var style: MapStyle {
        switch self {
        case .standard, .dark: .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
        case .satellite: .imagery(elevation: .flat)
        }
    }
}

/// Screenshot presets (CI): the same view with the filter sheet, a search or a zoomed-out map already open.
enum RadarPreset: String, Sendable {
    case live, filter, search, cluster
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

/// A vehicle as drawn: its position at the moment (server position, or an estimate between two answers).
struct RadarPin: Identifiable, Hashable {
    var vehicle: RadarVehicle
    var coordinate: GeoPoint
    var isEstimate: Bool
    var delay: RadarDelayState
    var delaySeconds: Int?
    /// Direction to the next stop, clockwise from north; nil when the next stop has no coordinate.
    var bearing: Double?

    var id: String { vehicle.tripID }

    /// VoiceOver text: "RJX 66, nach Innsbruck Hbf, 5 Minuten verspätet, Position geschätzt".
    var accessibilityText: String {
        var parts = [vehicle.line.map { LinePresentation.title($0) } ?? "Zug"]
        if let direction = vehicle.direction { parts.append("nach \(direction)") }
        switch delay {
        case .cancelled: parts.append("fällt aus")
        case .onTime: parts.append("pünktlich")
        case .late:
            let minutes = max((delaySeconds ?? 0) / 60, 5)
            parts.append("\(minutes) Minuten verspätet")
        case .unknown: parts.append("Verspätung unbekannt")
        }
        if isEstimate { parts.append("Position geschätzt") }
        return parts.joined(separator: ", ")
    }
}

extension RadarDelayState {
    /// The ring colour of a marker: on time green, five minutes or more late orange, cancelled red, unknown grey.
    var tint: Color {
        switch self {
        case .onTime: Theme.positive
        case .late: Theme.summit
        case .cancelled: Theme.negative
        case .unknown: Theme.textTertiary
        }
    }
}

@MainActor
@Observable
final class RadarModel {
    enum Load: Equatable { case idle, loading, loaded, failed(String) }

    var modes: Set<RadarMode> = [.rail]
    var filter = RadarFilter() {
        didSet { rebuildPins(at: Date()) }
    }
    private(set) var box: RadarBox = .austria
    /// Latitude span of the visible map. The cluster grid follows it.
    private(set) var spanDegrees: Double = 4.2
    private(set) var pins: [RadarPin] = []
    private(set) var updatedAt: Date?
    private(set) var load: Load = .idle
    /// The last answer was cut off at the server cap. Said in the UI: „Zoom hinein für alle Züge“.
    private(set) var cutOff = false
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var selectedTripID: String?
    /// Route of the selected trip (JourneyDetails polyline); drawn only while `routeTripID` is the selection.
    var route: [GeoPoint] = []
    var routeTripID: String?

    @ObservationIgnored private var store = RadarFrameStore()
    /// Set after a truncated answer: the next refresh asks for the four quadrants. Reset when the map moves.
    @ObservationIgnored private var splitNext = false

    var products: ProductMask {
        modes.reduce(into: ProductMask(rawValue: 0)) { $0.formUnion($1.products) }
    }

    var isRailOnly: Bool { modes == [.rail] }

    /// "12 Züge im Ausschnitt, 3 verspätet": the label of the train layer (status pill, VoiceOver).
    var summary: String {
        RadarSummary.line(count: pins.count, late: pins.filter { $0.delay == .late }.count, rail: isRailOnly)
    }

    /// Every vehicle of the last 60 s, whatever the map shows. Search and the filter's line list use it.
    var knownVehicles: [RadarVehicle] {
        store.entries.values.map(\.vehicle).sorted { $0.tripID < $1.tripID }
    }

    func toggle(_ mode: RadarMode) {
        if modes.contains(mode) {
            guard modes.count > 1 else { return }   // at least one mode stays on
            modes.remove(mode)
        } else {
            modes.insert(mode)
        }
    }

    /// The visible rectangle and span. A new rectangle restarts the split and the next refresh.
    func setView(box newBox: RadarBox, span: Double) {
        spanDegrees = span
        guard newBox != box else { return }
        box = newBox
        splitNext = false
        cutOff = false
        rebuildPins(at: Date())
    }

    func refresh(_ service: any RadarService, now: Date = Date()) async {
        guard box.isValid else { return }
        if pins.isEmpty { load = .loading }
        var answered: [RadarVehicle] = []
        var truncated = false
        var failure: Error?
        var stamp: Date?
        for tile in RadarTiling.tiles(for: box, split: splitNext) {
            do {
                let snapshot = try await service.radar(RadarQuery(box: tile, when: now, products: products))
                answered += snapshot.vehicles
                truncated = truncated || RadarTiling.isTruncated(count: snapshot.vehicles.count)
                stamp = snapshot.realtimeUpdatedAt ?? stamp ?? now
            } catch is CancellationError {
                return
            } catch {
                failure = error
            }
        }
        if answered.isEmpty, let failure {
            load = .failed(LiveMessage.text(for: failure))
            rebuildPins(at: now)
            return
        }
        store.merge(answered, at: now)
        updatedAt = stamp ?? now
        if truncated { splitNext = true }
        cutOff = truncated
        if let failure {
            // A quadrant failed while the others answered: the map keeps what came in and says that some is missing.
            load = .failed(LiveMessage.text(for: failure))
        } else {
            load = .loaded
        }
        rebuildPins(at: now)
    }

    /// Refreshes every `interval` and moves the markers every second in between. Low Power Mode pauses the requests
    /// (the clock still runs, so the pins stay where the last answer put them). Ends with the task.
    func run(_ service: any RadarService, interval: Duration) async {
        // A map that is still moving restarts this loop on every move: the short pause makes a burst of moves cost one
        // request instead of one each (the shared 40 requests/min budget also serves the live follow).
        try? await Task.sleep(for: .milliseconds(800))
        while !Task.isCancelled {
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            if !lowPower {
                await refresh(service)
            }
            var waited: Duration = .zero
            while waited < interval, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                waited += .seconds(1)
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                rebuildPins(at: Date())
            }
        }
    }

    private func rebuildPins(at now: Date) {
        pins = store.visible(at: now).compactMap { entry -> RadarPin? in
            let (point, estimate) = RadarEstimate.shown(entry, now: now)
            guard box.contains(point) else { return nil }
            let vehicle = entry.vehicle
            guard filter.matches(vehicle, now: now) else { return nil }
            let next = RadarRun.nextStop(of: vehicle, now: now)
            return RadarPin(vehicle: vehicle, coordinate: point, isEstimate: estimate,
                            delay: RadarDelay.state(of: vehicle, now: now),
                            delaySeconds: RadarDelay.currentDelay(of: vehicle, now: now),
                            bearing: next?.location.coordinate.map { RadarBearing.degrees(from: point, to: $0) })
        }
    }
}

struct RadarView: View {
    var preset: RadarPreset = .live

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var model = RadarModel()
    @State private var camera: MapCameraPosition = .region(RadarView.austriaRegion)
    @State private var query = ""
    @State private var showsFilter = false
    @State private var sheetVehicle: RadarVehicle?
    @AppStorage("radar.mapStyle") private var styleRaw = RadarMapStyle.standard.rawValue
    @FocusState private var searchFocused: Bool

    private static var austriaRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: RadarBox.austria.center.clCoordinate, span: MKCoordinateSpan(latitudeDelta: 4.2, longitudeDelta: 9.0))
    }

    /// Restarts the refresh loop when the modes, the visible area or the activity change.
    private struct RunKey: Hashable {
        var products: ProductMask
        var box: [Int]
        var active: Bool
    }

    private var mapStyle: RadarMapStyle { RadarMapStyle(rawValue: styleRaw) ?? .standard }

    private var isRunning: Bool {
        scenePhase == .active && app.live.timetableUnavailable == nil
    }

    /// The visible rectangle at 0.01° resolution, so small camera moves do not restart the loop.
    private var boxKey: [Int] {
        [model.box.north, model.box.west, model.box.south, model.box.east].map { Int(($0 * 100).rounded()) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let reason = app.live.timetableUnavailable {
                    ScrollView {
                        PlannerUnavailableView(reason: reason, onSettings: { app.isShowingSettings = true })
                            .padding(Theme.Spacing.cardGutter)
                    }
                } else {
                    mapLayer
                }
            }
            .navigationTitle("Zug-Radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterButton }
                ToolbarItem(placement: .topBarTrailing) { styleMenu }
                ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } }
            }
            .safeAreaInset(edge: .top, spacing: Theme.Spacing.xs) { topBar }
            .safeAreaInset(edge: .bottom, spacing: Theme.Spacing.xs) { statusBar }
            .task(id: RunKey(products: model.products, box: boxKey, active: isRunning)) {
                guard isRunning, let service = app.live.radar else { return }
                await model.run(service, interval: .seconds(20))
            }
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
                                   dismiss()
                                   app.selectedTab = .planner
                                   app.planner.showBoard(live: stop)
                               })
                    .presentationDetents([.fraction(0.32), .medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
            .onAppear(perform: applyPreset)
        }
    }

    // MARK: Map and train layer

    private var mapLayer: some View {
        Map(position: $camera) {
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
            model.setView(box: RadarBox(north: r.center.latitude + r.span.latitudeDelta / 2,
                                        west: r.center.longitude - r.span.longitudeDelta / 2,
                                        south: r.center.latitude - r.span.latitudeDelta / 2,
                                        east: r.center.longitude + r.span.longitudeDelta / 2).clamped,
                          span: r.span.latitudeDelta)
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

    private func zoom(to cluster: RadarCluster) {
        let span = max(model.spanDegrees / 3, 0.02)
        camera = .region(MKCoordinateRegion(center: cluster.center.clCoordinate,
                                            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span * 1.4)))
    }

    private func center(on tripID: String) {
        guard let pin = pinsByID[tripID] else { return }
        camera = .region(MKCoordinateRegion(center: pin.coordinate.clCoordinate,
                                            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.5)))
    }

    private func applyPreset() {
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
        }
    }

    // MARK: Controls

    private var filterButton: some View {
        Button { showsFilter = true } label: {
            Image(systemName: model.filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter")
        .accessibilityValue(model.filter.isActive ? "aktiv" : "aus")
    }

    private var styleMenu: some View {
        Menu {
            Picker("Kartenstil", selection: $styleRaw) {
                ForEach(RadarMapStyle.allCases) { style in
                    Label(style.title, systemImage: style.symbol).tag(style.rawValue)
                }
            }
        } label: {
            Image(systemName: mapStyle.symbol)
        }
        .accessibilityLabel("Kartenstil")
        .accessibilityValue(mapStyle.title)
    }

    private var topBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            searchField
            modeChips
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Zugnummer oder Linie, z. B. RJX 66", text: $query)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .font(.body)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Suche löschen")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)

            if searchFocused || !query.isEmpty, let parsed = RadarSearchQuery(query) {
                suggestionCard(for: parsed)
            }
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
    }

    private func suggestionCard(for parsed: RadarSearchQuery) -> some View {
        let matches = RadarSearch.suggestions(for: parsed, in: model.knownVehicles)
        return GlassCard(padding: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 4) {
                if matches.isEmpty {
                    Text("Kein Zug in den letzten Minuten gefunden. Zoom näher heran oder probier eine andere Nummer.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(matches) { vehicle in
                    Button { choose(vehicle) } label: {
                        HStack(spacing: Theme.Spacing.s) {
                            if let line = vehicle.line {
                                PlannerLinePlate(line: line, size: .s)
                            }
                            Text(vehicle.line.map { LinePresentation.title($0) } ?? "Zug")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 8)
                            if let direction = vehicle.direction {
                                Text("nach \(direction)")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func choose(_ vehicle: RadarVehicle) {
        query = ""
        searchFocused = false
        model.selectedTripID = vehicle.tripID
        sheetVehicle = vehicle
        center(on: vehicle.tripID)
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
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Status

    private var statusBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if model.lowPower {
                PlannerNoticeCard(symbol: "battery.25percent", title: "Stromspar-Modus",
                                  message: "Das Radar aktualisiert sich nicht, solange der Stromspar-Modus an ist.",
                                  actionTitle: "Jetzt aktualisieren") {
                    Task { if let s = app.live.radar { await model.refresh(s) } }
                }
            }
            if case .failed(let message) = model.load {
                PlannerNoticeCard(symbol: "wifi.exclamationmark", title: "Radar pausiert", message: message,
                                  actionTitle: "Erneut versuchen") {
                    Task { if let s = app.live.radar { await model.refresh(s) } }
                }
            }
            if model.cutOff {
                Text("Zoom hinein für alle Züge. Gerade sind nur die ersten \(RadarTiling.serverCap) Fahrzeuge je Abfrage zu sehen.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.l)
            }
            statusPill
            if !model.route.isEmpty {
                Button("Route ausblenden") {
                    model.route = []
                    model.routeTripID = nil
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .frame(maxWidth: .infinity)
        .motionAnimation(Motion.smooth, value: model.load)
    }

    private var statusPill: some View {
        let text: String
        if let updatedAt = model.updatedAt {
            text = "Stand \(Format.time(updatedAt)) · \(model.summary)"
        } else {
            text = model.load == .loading ? "Lade Fahrzeuge …" : "Noch keine Positionen"
        }
        return HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "dot.radiowaves.left.and.right")
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// One vehicle on the map: its line plate in the mode colour, the delay ring, a dashed ring for estimates and the
/// direction arrow towards the next stop.
struct RadarMarker: View {
    var pin: RadarPin
    var isSelected = false

    var body: some View {
        let mode = pin.vehicle.line?.mode ?? .other
        let plate = pin.vehicle.line.map { LinePresentation.plate($0) } ?? ""
        VStack(spacing: 1) {
            Text(plate.isEmpty ? "•" : plate)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.modeColor(mode), in: .capsule)
                .overlay(Capsule().strokeBorder(pin.delay.tint,
                                                style: StrokeStyle(lineWidth: 2, dash: pin.isEstimate ? [3, 2] : [])))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            if let bearing = pin.bearing {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.modeColor(mode))
                    .rotationEffect(.degrees(bearing))
                    .frame(height: 8)
            }
        }
        .scaleEffect(isSelected ? 1.18 : 1)
        .motionAnimation(Motion.snappy, value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pin.accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A cluster of vehicles at this zoom. The ring shows the worst state inside it.
struct RadarClusterBubble: View {
    var cluster: RadarCluster
    var noun = "Fahrzeuge"

    var body: some View {
        let worst: RadarDelayState = cluster.cancelledCount > 0 ? .cancelled : (cluster.lateCount > 0 ? .late : .onTime)
        Text("\(cluster.count)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: 34, minHeight: 34)
            .padding(.horizontal, 4)
            .background(Theme.accent, in: .circle)
            .overlay(Circle().strokeBorder(worst.tint, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(cluster.count) \(noun) an dieser Stelle, \(cluster.lateCount) verspätet")
            .accessibilityHint("Tippen zum Heranzoomen")
            .accessibilityAddTraits(.isButton)
    }
}

extension GeoPoint {
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
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
