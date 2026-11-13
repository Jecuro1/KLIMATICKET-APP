import SwiftUI
import KlimaCore

// MARK: radar2-mine – stub of „Meine Fahrzeuge“ (specs/radar2/radarmine.md). Landed with the radar2 seam (radarmodes); the radarmine track
// replaces the bodies of this file and never touches the seam (`Radar2/Radar2Seam.swift`).

@MainActor @Observable
final class RadarMineModel {
    /// Everything the part holds goes (the access closed).
    func end(_ reason: RadarEndReason) {}
    /// A request that is due now (the departures board of the open stop panel); nil: nothing to ask.
    func dueSideJob(now: Date) -> RadarSideJob? { nil }
    func sideJobStarted(_ job: RadarSideJob, at now: Date) {}
    /// The vehicle's line is one the user remembered (radartrail reads it).
    func remembers(_ vehicle: RadarVehicle) -> Bool { false }
    /// The vehicle stays a single marker, never folded into a group.
    func keepsSingle(_ vehicle: RadarVehicle) -> Bool { false }
    /// The Zeitreise card opened: the part's own panel closes.
    func timeCardOpened() {}
}
