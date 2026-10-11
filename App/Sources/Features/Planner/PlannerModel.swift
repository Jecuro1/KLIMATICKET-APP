import SwiftUI
import Observation
import KlimaCore

/// State of the Fahrplan tab (docs/OEBB_LIVE.md §E3). W-D shell; the search, results and detail flows follow in W-E.
@MainActor @Observable
final class PlannerModel {
    enum NavigationStyle { case searchTab, plainTab }
    /// One-line fallback (R4): `.plainTab` drops the search role and shows the planner's own search field.
    static let navigationStyle: NavigationStyle = .searchTab

    let live: LiveDataService
    @ObservationIgnored let stationsProvider: () -> StationIndex
    @ObservationIgnored let settings: AppSettings

    var query = ""
    var searchPrompt: String { "Wohin?" }

    init(live: LiveDataService, stations: @escaping () -> StationIndex, settings: AppSettings) {
        self.live = live
        self.stationsProvider = stations
        self.settings = settings
    }

    /// `klimabilanz://plan?from=…&to=…&at=…&arr=0|1`
    func handleDeepLink(from: String?, to: String?, at: Date?, arrival: Bool) {}

    /// `klimabilanz://board?station=<stationID>`
    func showBoard(stationID: String) {}
}
