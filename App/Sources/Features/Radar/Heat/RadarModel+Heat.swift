import SwiftUI
import KlimaCore

// MARK: radarheat – what the radar model does for the Pünktlichkeit layer (docs/RADAR_HEATMAP.md §1): while the layer is on the radar
// loads all of Austria whatever the map shows (the scheduler gets the country's rectangle as its view: two tiles of the grid, the
// same budget of 24 requests a minute, the same loop – no second loop), and every answer and every ten seconds the trains it holds
// become the numbers and cells of the layer.

extension RadarModel {
    /// The latitude span handed to the scheduler while the layer is on: that of the whole coverage (2.8°), so its two level-0 tiles
    /// are asked every 20 s (the scheduler counts a view up to 3° as zoomed in).
    static var heatSpan: Double { RadarTileGrid.coverage.north - RadarTileGrid.coverage.south }

    /// The layer was switched on or off. On: the scheduler's view becomes the country; off: it follows the map again.
    func setHeat(enabled: Bool) {
        guard heat.isEnabled != enabled else { return }
        heat.setEnabled(enabled)
        applyViewport()
        if enabled { refreshHeat(at: Date()) }
    }

    /// What the scheduler is told the view is: the map's, or while the layer is on, all of Austria. Moving or zooming the map then
    /// changes no request.
    func applyViewport(now: Date = Date()) {
        if heat.isEnabled {
            scheduler.setViewport(RadarTileGrid.coverage, latitudeSpan: Self.heatSpan, now: now)
        } else {
            scheduler.setViewport(box, latitudeSpan: spanDegrees, now: now)
        }
    }

    /// Recomputes the layer when an answer came in or ten seconds went by. The trains are the trains and S-Bahnen the radar holds (the
    /// layer is about trains: a bus or a tram that the mode chips ask for does not count, and neither does the marker filter), at the
    /// positions the map shows them.
    func refreshHeat(at now: Date) {
        guard heat.needsUpdate(at: now) else { return }
        // Trains older than their retention never count: switched on after a while without the loop (the train layer off, the map
        // still), the store can hold the answers of minutes ago until the next rebuild prunes it.
        store.prune(now: now)
        let mask = products.intersection(.rail)
        let samples = store.entries.values.compactMap { entry -> HeatSample? in
            let vehicle = entry.vehicle
            // A mode that was switched off is gone at once, whatever its retention says (as for the pins); buses, trams and
            // subways never count (a vehicle with an unknown product class is kept, as for the pins).
            if let line = vehicle.line, line.productClass != 0, line.productClass & mask.rawValue == 0 { return nil }
            return HeatSample(vehicle: vehicle, coordinate: RadarEstimate.shown(entry, now: now).coordinate, now: now)
        }
        // The trend line only takes complete answers: with one of the two tiles still on its way the share would jump for the area
        // that is missing, not for the punctuality. A tile whose last answer is older than its retention is missing too (back from
        // the background after minutes: the first new answer covers half the country, the other half's trains are gone).
        let complete = status.answeredTiles > 0 && status.pendingTiles == 0 && status.failedTiles == 0 && status.cappedTiles == 0
            && status.staleTiles == 0 && !status.isPaused
        // The time the numbers belong to: the request time of the oldest answer behind them (the share image says it, not the
        // moment the panel was drawn).
        heat.update(samples, at: now, isComplete: complete, dataTime: status.oldestAnswerAge.map { now.addingTimeInterval(-$0) })
    }

    /// No mode that carries trains is on (only buses, trams or subways): the layer has nothing to count and says so.
    var heatHasNoRail: Bool { products.intersection(.rail).isEmpty }

    /// A vehicle the radar holds, by trip id (the panel's lists and the cell sheet open its trip sheet from the id).
    func vehicle(id: String) -> RadarVehicle? { store.entries[id]?.vehicle }
}
