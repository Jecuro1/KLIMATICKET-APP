import Foundation

/// Kinds of the widgets added in the widget track (docs/WIDGETS.md). The app and the widget extension share them.
enum WidKind {
    static let nextConnection = "nextConnection"
    static let departures = "departures"
    static let disruptions = "disruptions"
    static let ticketRemaining = "ticketRemaining"
    static let breakEven = "breakEven"
    static let yearReview = "yearReview"
    static let heatmap = "heatmap"
    static let summit = "summit"
    static let radarControl = "com.knitelarlberg.klimabilanz.control.radar"
    static let searchControl = "com.knitelarlberg.klimabilanz.control.search"
    static let liveFollowControl = "com.knitelarlberg.klimabilanz.control.liveFollow"
}

/// Deep links of the new widgets and controls (RootView › handleDeepLink).
extension WidDeepLink {
    /// klimabilanz://tab/planner – the Fahrplan (Verbindung suchen).
    static let planner = URL(string: "klimabilanz://tab/planner")!
    /// klimabilanz://radar – the Zug-Radar.
    static let radar = URL(string: "klimabilanz://radar")!
    /// klimabilanz://tab/stats – Statistik (Jahresrückblick).
    static let stats = URL(string: "klimabilanz://tab/stats")!

    /// klimabilanz://board?station=<id> – the Abfahrten of one station.
    static func board(stationID: String) -> URL {
        var components = URLComponents()
        components.scheme = "klimabilanz"
        components.host = "board"
        components.queryItems = [URLQueryItem(name: "station", value: stationID)]
        return components.url ?? planner
    }
}
