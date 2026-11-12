import SwiftUI
import SwiftData
import KlimaCore

/// How „Was wäre wenn?“ opens. `.automatic` is the normal case; the others are CI screenshot states (and a deep link could
/// use them later).
enum WhatIfLaunch: Equatable {
    /// „Meine Fahrten“ with at least five trips in the last 12 months, otherwise „Eigene Annahmen“.
    case automatic
    /// „Meine Fahrten“ with the filters of the real-data mode set (July/August off, one state, 1. Klasse, slider ×1,5).
    case historyFiltered
    /// „Eigene Annahmen“ with a preset filled in.
    case preset(String)
    /// „Eigene Annahmen“ without any route (the inviting empty card).
    case empty
    /// „Eigene Annahmen“ at the upper limit: 60 trips a month on two routes.
    case extreme
}

/// What the screen knows about the user: the trips of the last 12 months and the ticket (nil before the purchase).
/// A plain value built once per change of the stored trips – dragging a slider never rebuilds it.
struct WhatIfSource {
    struct Region: Identifiable, Hashable {
        var state: FederalState
        var count: Int
        var id: String { state.rawValue }
    }

    /// The trips of the window, nil when there are none.
    var history: WhatIfHistory?
    var baseline: WhatIfBaseline
    /// Trips in the window.
    var tripCount: Int
    /// The own ticket, nil before the first purchase.
    var currentProductID: String?
    var ticketVariant: TicketVariant?
    /// Start of the own ticket: prices of the real-data mode (and the Statistik comparison) are those of that day.
    var ticketStart: Date?
    /// States that single-state trips lie in, most trips first (the chips of „nur Bundesland“).
    var regions: [Region]

    var hasRichHistory: Bool { history?.isRichEnough == true }
    var hasTicket: Bool { currentProductID != nil }

    /// Variant the comparison starts with: the own ticket's, else Klassik.
    var defaultVariant: TicketVariant { ticketVariant ?? .klassik }

    @MainActor
    static func make(trips: [TripEntity], tickets: [TicketEntity], selectedTicketID: UUID?, now: Date = Date()) -> WhatIfSource {
        let liveTrips = trips.filter { $0.deletedAt == nil }
        let liveTickets = tickets.filter { $0.deletedAt == nil }
        let ticket = Analytics.activeTicket(in: liveTickets, selectedID: selectedTicketID)
        let first = ([liveTickets.map(\.startDate).min(), liveTrips.map(\.date).min()].compactMap { $0 }).min()
        let baseline = WhatIfBaseline.make(now: now, firstActivity: first)
        let window = liveTrips.filter { $0.date >= baseline.windowStart && $0.date <= now }

        var perState: [FederalState: Int] = [:]
        for trip in window where trip.states.count == 1 {
            if let state = FederalState(rawValue: trip.states[0]) { perState[state, default: 0] += 1 }
        }
        let regions = perState.map { Region(state: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.state.rawValue) > ($1.count, $0.state.rawValue) }

        let history: WhatIfHistory? = window.isEmpty ? nil : WhatIfHistory(
            trips: window.map(\.record),
            firstClassTripIDs: Set(window.filter { $0.travelClass == .first }.map(\.id)),
            annualizationFactor: baseline.annualizationFactor)
        return WhatIfSource(history: history, baseline: baseline, tripCount: window.count,
                            currentProductID: ticket?.productID, ticketVariant: ticket?.variant, ticketStart: ticket?.startDate,
                            regions: regions)
    }

    /// Without any trips or ticket (the onboarding sheet before the purchase).
    static let empty = WhatIfSource(history: nil, baseline: WhatIfBaseline.make(now: Date(), firstActivity: nil), tripCount: 0,
                                    currentProductID: nil, ticketVariant: nil, ticketStart: nil, regions: [])
}
