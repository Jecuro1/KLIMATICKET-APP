import SwiftUI
import KlimaCore

// The Zug-Radar's model: what is loaded for the visible map box and the pins drawn from it (split from RadarView.swift).

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
