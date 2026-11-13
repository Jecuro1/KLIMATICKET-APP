import Foundation
import KlimaCore
import Observation
import SwiftUI

/// What the departures section shows (ENRICH_SPEC §4.4, docs/COMMUTE.md §12). MARK: commute – the next departures come from
/// one HAFAS station board (`LiveStopDepartureProvider`) as the Fahrplan's board rows.
enum DeparturesState: Equatable {
    /// No live data (consent, switch, kill switch, offline) – or not asked yet.
    case unavailable(LiveDataService.Unavailable?)
    case loading
    case live(StopBoardSnapshot)
    case empty
    case failed
}

/// Feature flags of the stop detail.
enum StopFeatureFlags {
    /// The „Nächste Abfahrten“ section. Off: `StopDeparturesSection` renders nothing.
    /// MARK: commute – CI screenshot and perf runs only, until the section has been reviewed in screenshots; then on for everyone.
    static var showsDepartures: Bool { LaunchMode.isSandboxed }
}

/// State of one stop detail: loads `StopDetails` from the place index (built in the background at launch).
@MainActor
@Observable
final class StopDetailModel {
    enum Phase { case loading, loaded, missing }

    let placeID: String
    private(set) var phase: Phase = .loading
    private(set) var details: StopDetails?
    private(set) var index: PlaceIndex?
    var departures: DeparturesState = .unavailable(nil)
    /// MARK: commute – when the last board answer (or empty answer) arrived; the section asks at most once a minute.
    @ObservationIgnored private var lastDepartureFetch: Date?
    @ObservationIgnored private var isLoadingDepartures = false

    init(placeID: String) {
        self.placeID = placeID
        if let index = PlaceIndexLoader.shared.current { apply(index) }
    }

    func load() async {
        guard details == nil else { return }
        guard let index = try? await PlaceIndexLoader.shared.load() else {
            phase = .missing
            return
        }
        apply(index)
    }

    private func apply(_ index: PlaceIndex) {
        self.index = index
        details = index.details(for: placeID)
        phase = details == nil ? .missing : .loaded
    }

    // MARK: commute – departures

    /// One board request for the stop, unless the last answer is younger than a minute or one is running. Without live data
    /// nothing is requested; the state says why.
    func loadDepartures(live: LiveDataService) async {
        guard StopFeatureFlags.showsDepartures, let place = details?.place else { return }
        if let reason = live.timetableUnavailable, !live.isDemo {
            departures = .unavailable(reason)
            return
        }
        guard StopBoardDepartures.mayRefresh(lastFetch: lastDepartureFetch, now: Date()), !isLoadingDepartures else { return }
        isLoadingDepartures = true
        defer { isLoadingDepartures = false }
        switch departures {
        case .live, .empty: break
        default: departures = .loading
        }
        do {
            let snapshot = try await LiveStopDepartureProvider(live: live).departures(for: place.station)
            lastDepartureFetch = snapshot.fetchedAt
            withMotion(Motion.smooth) { departures = snapshot.rows.isEmpty ? .empty : .live(snapshot) }
        } catch is CancellationError {
            if departures == .loading { departures = .unavailable(nil) }
        } catch let error as CommuteLiveError where error == .consentRequired {
            departures = .unavailable(live.timetableUnavailable)
        } catch {
            // Older rows stay (their age line says how old); without rows the section says it failed.
            if case .live = departures { return }
            withMotion(Motion.smooth) { departures = .failed }
        }
    }

    /// Ids a stored trip may use for this stop (the place id and the ids of the previous station list).
    var tripStationIDs: Set<String> {
        guard let place = details?.place else { return [placeID] }
        return Set([place.id, place.stationID, placeID] + place.legacyStationIDs)
    }
}
