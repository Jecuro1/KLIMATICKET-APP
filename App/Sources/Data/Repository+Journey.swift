import Foundation
import SwiftData
import KlimaCore

// „Fahrt erfassen“ from a planner connection (docs/OEBB_LIVE.md §E6). The trips come from the pure `JourneyLogPlanner`
// (KlimaCore, tested): ride legs become the existing „Reise mit Etappen“ (docs/JOURNEYS.md), requested via stops land in
// the existing via fields (docs/VIA.md), a partially covered connection logs and values only its covered part.
extension Repository {
    /// Logs a connection in one commit and returns the trips in travel order (empty when there is no ride leg).
    /// The price is shared over the legs so the journey adds up to exactly `quote.amountEUR`. A price that came from the
    /// planner is never marked as manual.
    @discardableResult
    func logJourney(_ journey: Journey, quote: PriceQuote?, coverage: JourneyCoverage?, travelClass: TravelClass,
                    isRoundTrip: Bool = false, via: [ViaStop] = []) -> [TripEntity] {
        let plan = JourneyLogPlanner.plan(journey: journey, quote: quote, coverage: coverage, via: via, stations: app.stations)
        return logPlan(plan, quote: quote, travelClass: travelClass, isRoundTrip: isRoundTrip)
    }

    @discardableResult
    func logPlan(_ plan: JourneyLogPlan, quote: PriceQuote? = nil, travelClass: TravelClass, isRoundTrip: Bool = false) -> [TripEntity] {
        guard !plan.isEmpty else { return [] }
        let journeyID: UUID? = plan.isJourney ? UUID() : nil
        var trips: [TripEntity] = []
        for (index, leg) in plan.legs.enumerated() {
            let trip = TripEntity(date: plan.date, fromName: leg.fromName, toName: leg.toName, fromStationID: leg.fromStationID,
                                  toStationID: leg.toStationID, mode: leg.mode, distanceKm: leg.distanceKm, fareEUR: leg.fareEUR,
                                  isFareManual: false, isRoundTrip: isRoundTrip, travelClass: travelClass, states: leg.states)
            trip.viaRaw = TripViaCodec.encode(leg.via)
            trip.journeyID = journeyID
            trip.legIndex = index
            // MARK: planner – provenance (the price is shared over the legs, the source is the same)
            if let quote {
                trip.priceSourceRaw = quote.source.rawValue
                trip.priceProvider = quote.provider ?? ""
                trip.priceProduct = quote.productName ?? ""
                trip.priceFetchedAt = quote.fetchedAt
            }
            trip.journeyRef = plan.journeyRef
            trip.lineSummary = plan.isJourney ? leg.lineTitle : plan.lineSummary
            trip.arrivalAt = leg.arrival
            trips.append(trip)
        }
        for trip in trips { context.insert(trip) }
        commit()
        return trips
    }
}
