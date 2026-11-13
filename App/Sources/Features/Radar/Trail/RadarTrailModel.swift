import SwiftUI
import KlimaCore

// MARK: radar2-trail – stub of „Spuren“ (specs/radar2/radartrail.md). Landed with the radar2 seam (radarmodes); the radartrail track
// replaces the bodies of this file and never touches the seam (`Radar2/Radar2Seam.swift`).

@MainActor @Observable
final class RadarTrailModel {
    /// One answer the live loop merged.
    func didMerge(_ event: RadarAnswerEvent) {}
    /// Vehicles of these product classes left the radar (a mode was switched off).
    func didRemove(products mask: ProductMask) {}
    /// Everything the part holds goes (the access closed).
    func end(_ reason: RadarEndReason) {}
}
