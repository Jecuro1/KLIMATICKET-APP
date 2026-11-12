import SwiftUI
import KlimaCore

// The Zug-Radar's model: what is loaded for the visible map box and the pins drawn from it (split from RadarView.swift).
// Which tile is asked when is decided by `RadarScheduler` (docs/OEBB_LIVE.md §R11): this model sends the requests it names
// (a few at a time, never waiting for an answer in the loop that moves the markers), stores the answers per vehicle and
// rebuilds the pins and clusters as often as a move can be seen.

@MainActor
@Observable
final class RadarModel {
    enum Load: Equatable { case idle, loading, loaded, failed(String) }

    var modes: Set<RadarMode> = [.rail] {
        didSet { if modes != oldValue { modesChanged() } }
    }
    var filter = RadarFilter() {
        didSet { rebuildPins(at: Date()) }
    }
    private(set) var box: RadarBox = .austria
    /// Latitude span of the visible map. The tile level and the tick follow it.
    private(set) var spanDegrees: Double = 4.2
    /// Size of the map on the screen in points. The cluster grid follows it: one cell is about one marker.
    private(set) var mapSize: CGSize = .zero
    private(set) var pins: [RadarPin] = []
    /// The pins grouped for the current zoom: the markers the map draws. Their number follows the grid, not the vehicles.
    private(set) var clusters: [RadarCluster] = []
    private(set) var pinsByID: [String: RadarPin] = [:]
    /// Tiles, answers, freshness and budget state of the visible area, for the status line.
    private(set) var status = RadarStatus.empty
    private(set) var load: Load = .idle
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var selectedTripID: String?
    /// Route of the selected trip (JourneyDetails polyline); drawn only while `routeTripID` is the selection.
    var route: [GeoPoint] = []
    var routeTripID: String?

    @ObservationIgnored private var store = RadarFrameStore()
    @ObservationIgnored private var scheduler = RadarScheduler()
    @ObservationIgnored private var lastError: Error?
    @ObservationIgnored private var lastRebuild = Date.distantPast
    @ObservationIgnored private var lastPinRebuild = Date.distantPast
    /// Counts the mode changes: an answer that was asked for before a change is dropped.
    @ObservationIgnored private var generation = 0
    /// „Jetzt aktualisieren“ / „Erneut versuchen“: the loop sends the due tiles even in Low Power Mode until none is due. There is no
    /// second loop for it: one loop, one budget, and it ends with the view.
    @ObservationIgnored private var manualRefresh = false

    var products: ProductMask {
        modes.reduce(into: ProductMask(rawValue: 0)) { $0.formUnion($1.products) }
    }

    var isRailOnly: Bool { modes == [.rail] }

    /// "12 Züge im Ausschnitt, 3 verspätet": the label of the train layer (VoiceOver).
    var summary: String {
        RadarSummary.line(count: pins.count, late: pins.filter { $0.delay == .late }.count, rail: isRailOnly)
    }

    /// The status pill: the vehicles in the visible area and the age of the oldest answer behind them.
    var pillText: String? {
        guard status.answeredTiles > 0 || !pins.isEmpty else { return nil }
        return RadarStatusText.pill(count: pins.count, rail: isRailOnly, age: status.oldestAnswerAge)
    }

    /// The notes under the pill: cut-off tiles, a partial failure, a slow refresh.
    var notes: [String] {
        RadarStatusText.notes(status, rail: isRailOnly, hasVehicles: !pins.isEmpty || status.answeredTiles > 0)
    }

    /// Every vehicle of the last minutes, whatever the map shows. Search and the filter's line list use it.
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

    /// The old answers are for other vehicles: the tiles start over, vehicles of a mode that was switched off go at once.
    private func modesChanged() {
        generation += 1
        scheduler.reset()
        let mask = products
        store.removeAll { vehicle in
            guard let line = vehicle.line, line.productClass != 0 else { return false }
            return line.productClass & mask.rawValue == 0
        }
        scheduler.setViewport(box, latitudeSpan: spanDegrees, now: Date())
        rebuildPins(at: Date())
    }

    func setMapSize(_ size: CGSize) {
        guard size != mapSize, size.width > 0, size.height > 0 else { return }
        mapSize = size
        rebuildPins(at: Date())
    }

    /// The visible rectangle and span. The scheduler picks the tiles; tiles that left the view are not asked again, their
    /// vehicles stay until their retention ends, so the map does not flicker while it moves.
    func setView(box newBox: RadarBox, span: Double) {
        spanDegrees = span
        guard newBox != box else { return }
        box = newBox
        scheduler.setViewport(newBox, latitudeSpan: span, now: Date())
        rebuildPins(at: Date())
    }

    // MARK: Requests

    /// Sends the requests the scheduler names (up to `maxInFlight` at once) and moves the markers and the status in between: a
    /// slow answer (0.4 to 21 s measured, docs/OEBB_LIVE.md §R11.1) neither freezes the map nor holds up the other tiles. Low Power Mode
    /// pauses the requests (the clock still runs, so the pins stay where the last answer put them). The requests end with the
    /// task: cancelling it cancels every request on its way, and each gives its tile back to the scheduler.
    func run(_ service: any RadarService) async {
        scheduler.setViewport(box, latitudeSpan: spanDegrees, now: Date())
        await withTaskGroup(of: Void.self) { group in
            while !Task.isCancelled {
                let now = Date()
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                tick(now)
                if lowPower && !manualRefresh {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                switch scheduler.next(now: now) {
                case .request(let tile):
                    group.addTask { await self.fetch(tile, service) }
                case .wait(let until):
                    if manualRefresh, !scheduler.hasDueTiles(now: now) { manualRefresh = false }
                    try? await Task.sleep(for: .seconds(min(max(until.timeIntervalSinceNow, 0.05), 1)))
                case .idle:
                    manualRefresh = false
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    /// „Jetzt aktualisieren“ and „Erneut versuchen“: every visible tile is asked once more, spaced as the budget wants it. The
    /// running loop does the work; nothing is sent when the radar is not running (the buttons are only there while it is).
    func refreshNow() {
        scheduler.refreshAll()
        manualRefresh = true
    }

    private func fetch(_ tile: RadarTileKey, _ service: any RadarService) async {
        let asked = generation
        let requestedAt = Date()
        do {
            let snapshot = try await service.radar(RadarQuery(box: RadarTileGrid.box(of: tile), when: requestedAt, products: products,
                                                               maxVehicles: RadarTiling.requestCap))
            guard asked == generation else { return }   // the modes changed while this was on its way
            // The positions in the answer are those of `requestedAt` (`RadarQuery.when`), however long the answer took: that is
            // the time they belong to. So a slow answer (up to 21 s measured) is as old in the status as it is, and an answer of
            // an older request never replaces a newer one (`RadarFrameStore.merge`), now that several requests are on their way.
            // The count is what the server answered, not the vehicles left after dropping the entries without a position: that
            // is what shows an answer cut off at the request cap.
            scheduler.recordAnswer(tile, count: snapshot.answeredCount, at: requestedAt)
            store.merge(snapshot.vehicles, at: requestedAt, retention: scheduler.retention(for: tile))
            lastError = nil
        } catch is CancellationError {
            scheduler.recordCancelled(tile)
        } catch {
            guard asked == generation else { return }
            lastError = error
            scheduler.recordFailure(tile, error: error, at: Date())
        }
        rebuildPins(at: Date())
    }

    /// The status line moves every second; the markers only as often as a move can be seen: a train covers about 30 m a second,
    /// which is a pixel at the country zoom and several at a city zoom. Fewer rebuilds keep up to a thousand markers cheap.
    private func tick(_ now: Date) {
        guard now.timeIntervalSince(lastRebuild) >= 0.95 else { return }
        let pinInterval: TimeInterval = spanDegrees > 2 ? 5 : (spanDegrees > 0.6 ? 2 : 1)
        if now.timeIntervalSince(lastPinRebuild) >= pinInterval - 0.05 {
            rebuildPins(at: now)
        } else {
            lastRebuild = now
            updateStatus(at: now)
        }
    }

    private func updateStatus(at now: Date) {
        status = scheduler.status(now: now)
        if status.isPaused {
            load = .failed(lastError.map(LiveMessage.text(for:)) ?? "Das hat gerade nicht geklappt. Versuch es gleich noch einmal.")
        } else if status.answeredTiles > 0 {
            load = .loaded
        } else if status.visibleTiles > 0 {
            load = .loading
        } else {
            load = .idle
        }
    }

    private func rebuildPins(at now: Date) {
        lastRebuild = now
        lastPinRebuild = now
        let mask = products
        pins = store.visible(at: now).compactMap { entry -> RadarPin? in
            let vehicle = entry.vehicle
            // A mode that was switched off is gone at once, whatever its retention says.
            if let line = vehicle.line, line.productClass != 0, line.productClass & mask.rawValue == 0 { return nil }
            let (point, estimate) = RadarEstimate.shown(entry, now: now)
            guard box.contains(point) else { return nil }
            guard filter.matches(vehicle, now: now) else { return nil }
            let next = RadarRun.nextStop(of: vehicle, now: now)
            return RadarPin(vehicle: vehicle, coordinate: point, isEstimate: estimate,
                            delay: RadarDelay.state(of: vehicle, now: now),
                            delaySeconds: RadarDelay.currentDelay(of: vehicle, now: now),
                            bearing: next?.location.coordinate.map { RadarBearing.degrees(from: point, to: $0) })
        }
        pinsByID = Dictionary(pins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        clusters = RadarClustering.group(
            pins.map { RadarPoint(tripID: $0.id, coordinate: $0.coordinate, delay: $0.delay) },
            cellDegrees: RadarClustering.cellSize(latitudeSpan: spanDegrees, longitudeSpan: box.east - box.west,
                                                  widthPoints: Double(mapSize.width), heightPoints: Double(mapSize.height)))
        updateStatus(at: now)
    }
}
