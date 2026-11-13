import SwiftUI
import MapKit
import KlimaCore

// MARK: radar2 – the seam of the second radar wave (specs/radar2/README.md §3, docs/RADAR_MODES.md §Seam). radarmine and radartrail plug in
// here through their own folders; they never edit RadarView, RadarModel, RadarTripSheet or RadarFilterSheet.

/// One answer the live loop merged: the tile, its vehicles, the time the positions belong to (the request time) and the products asked.
struct RadarAnswerEvent {
    let tile: RadarTileKey
    let vehicles: [RadarVehicle]
    let requestedAt: Date
    let products: ProductMask
}

/// Why everything a part holds must go: the radar closed, or live data is no longer allowed (consent, switch, kill switch). Not offline.
enum RadarEndReason: Equatable { case closed, accessClosed }

/// A request of a radar part that is not a tile (radarmine's departures board). The live loop takes one slot of the radar budget for it
/// (`RadarScheduler.claimSlot`) and runs it in its task group. Returns the error, if any, so the loop can pause the radar on 429/circuit.
struct RadarSideJob: Sendable {
    let id: String
    let run: @Sendable () async -> Error?
}

@MainActor @Observable
final class Radar2Parts {
    let mine = RadarMineModel()     // MARK: radar2-mine  (Mine/RadarMineModel.swift)
    let trail = RadarTrailModel()   // MARK: radar2-trail (Trail/RadarTrailModel.swift)

    func didMerge(_ event: RadarAnswerEvent) { trail.didMerge(event) }
    func didRemove(products mask: ProductMask) { trail.didRemove(products: mask) }
    func didEnd(_ reason: RadarEndReason) { trail.end(reason); mine.end(reason) }
    func dueSideJob(now: Date) -> RadarSideJob? { mine.dueSideJob(now: now) }
    func sideJobStarted(_ job: RadarSideJob, at now: Date) { mine.sideJobStarted(job, at: now) }
    /// Vehicles that must stay single markers, never folded into a group (radarmine: highlighted lines, the stop panel's arrivals).
    func keepsSingle(_ vehicle: RadarVehicle) -> Bool { mine.keepsSingle(vehicle) }
    /// The Zeitreise card opened: one bottom panel at a time, so „Meine“ closes (radarmine §15). The other direction needs no seam:
    /// `RadarView+Mine.swift` is a `RadarView` extension and calls `travel.close()` itself when its panel opens.
    func timeCardOpened() { mine.timeCardOpened() }
}

extension RadarView {
    /// Map content of the wave, drawn before the vehicle markers (overlays sit under annotations anyway).
    @MapContentBuilder var radar2MapContent: some MapContent {
        trailMapContent   // MARK: radar2-trail
        mineMapContent    // MARK: radar2-mine
    }
    /// Items at the start of the mode-chip row.
    @ViewBuilder var radar2TopBarItems: some View { mineTopBarChip }   // MARK: radar2-mine
    /// A panel above the status card; while it is open the layer bar steps aside (as for the Zeitreise card).
    @ViewBuilder var radar2Panel: some View { minePanel }              // MARK: radar2-mine
    var radar2PanelIsOpen: Bool { minePanelIsOpen }                     // MARK: radar2-mine
    /// Short captions right under the status card (radartrail's „Spuren: …“ line).
    @ViewBuilder var radar2StatusNotes: some View { trailStatusNote }   // MARK: radar2-trail
    /// The decoration of one vehicle marker (highlight, dim, star, number).
    func radar2Decoration(_ pin: RadarPin) -> RadarMarkerDecoration { mineDecoration(pin) }   // MARK: radar2-mine
}

/// Rows under the trip sheet's actions.
struct Radar2TripRows: View {
    let vehicle: RadarVehicle
    let parts: Radar2Parts?

    var body: some View {
        if let parts {
            RadarMineTripRow(vehicle: vehicle, mine: parts.mine)       // MARK: radar2-mine – „Linie merken“
            RadarTrailDelayRow(vehicle: vehicle, trail: parts.trail)   // MARK: radar2-trail – delay sparkline
        }
    }
}

/// Sections at the end of the filter sheet's „Darstellung“ page.
struct Radar2SettingsSections: View {
    let parts: Radar2Parts?

    var body: some View {
        if let parts { RadarTrailSettingsSection(trail: parts.trail) }   // MARK: radar2-trail – „Spuren“
    }
}

/// Lifecycle: everything goes when the access closes (not offline: as the Zeitreise's `suspend`). Closing the radar needs no call: the
/// model is `@State` of `RadarView`, so `Radar2Parts` and everything in it is released with the view. Deliberately no `.onDisappear`:
/// it can also fire while the Cockpit's full-screen cover is up, which must not wipe the parts.
struct Radar2Hooks: ViewModifier {
    var parts: Radar2Parts
    var access: RadarFeatureGate.Access
    var timeOpen: Bool   // travel.isOpen

    func body(content: Content) -> some View {
        content
            .onChange(of: access) { _, new in if new == .closed { parts.didEnd(.accessClosed) } }
            .onChange(of: timeOpen) { _, open in if open { parts.timeCardOpened() } }
    }
}
