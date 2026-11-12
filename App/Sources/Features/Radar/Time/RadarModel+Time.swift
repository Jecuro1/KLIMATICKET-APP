import SwiftUI
import KlimaCore

// MARK: radartime – what the radar model gives the Zeitreise (docs/RADAR_TIMETRAVEL.md §4): the vehicles it holds, a slot of its request
// budget, and a pause for the whole radar. The live loop and the Zeitreise share one budget (24 requests a minute), so they can never add up.

extension RadarModel {
    /// The answers the radar holds, with the time each one belongs to: the first snapshot of a Zeitreise.
    func knownEntries(at now: Date) -> [(vehicle: RadarVehicle, time: Date)] {
        store.entries.values.compactMap { entry in
            now.timeIntervalSince(entry.seenAt) <= entry.retention ? (entry.vehicle, entry.seenAt) : nil
        }
    }

    /// One slot of the radar's budget for a Zeitreise request: nil when it is taken (send now), else the time one frees.
    func claimRequestSlot(now: Date) -> Date? {
        scheduler.claimSlot(now: now)
    }

    /// A rate limit or an open circuit answered a Zeitreise request: the live radar waits too.
    func pauseRadar(until time: Date) {
        scheduler.pause(until: time)
    }

    /// The live radar holds all of Austria and every tile has answered: a Zeitreise needs no snapshot of its own for "now".
    var holdsAllOfAustria: Bool {
        status.coversCountry && status.pendingTiles == 0 && status.failedTiles == 0 && status.answeredTiles > 0
    }
}
