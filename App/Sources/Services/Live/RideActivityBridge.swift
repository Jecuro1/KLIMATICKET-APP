import Foundation
import KlimaCore

/// Integration seam for the separately built Live Activity module (docs/OEBB_LIVE.md §E10, decision D10).
/// The planner builds a `LiveJourneySnapshot` (KlimaCore, pure values); the module maps it onto its own
/// `RideActivityAttributes.ContentState`. Until it plugs in, `NoopRideActivityController` does nothing.
@MainActor
protocol RideActivityControlling: AnyObject {
    var isSupported: Bool { get }
    /// Starts an activity for the snapshot; returns its id (nil when it could not start).
    func start(_ snapshot: LiveJourneySnapshot) async -> String?
    func update(_ id: String, _ snapshot: LiveJourneySnapshot) async
    func end(_ id: String, final snapshot: LiveJourneySnapshot?, dismissAfter: TimeInterval) async
}

@MainActor
final class NoopRideActivityController: RideActivityControlling {
    var isSupported: Bool { false }
    func start(_ snapshot: LiveJourneySnapshot) async -> String? { nil }
    func update(_ id: String, _ snapshot: LiveJourneySnapshot) async {}
    func end(_ id: String, final snapshot: LiveJourneySnapshot?, dismissAfter: TimeInterval) async {}
}
