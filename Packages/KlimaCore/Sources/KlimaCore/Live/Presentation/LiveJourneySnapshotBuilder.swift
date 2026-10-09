import Foundation

/// „Live verfolgen“ snapshot of a journey at `now` (SPEC §C3.6) for the in-app accessory and the Live Activity.
///
/// | Phase | Condition | Next event |
/// |---|---|---|
/// | `beforeDeparture` | now < first ride departure | that departure: „Abfahrt in 12 min · Gl. 3“ |
/// | `riding` | inside a ride leg (or the final walk) | a following transfer's departure „Umsteigen in St. Anton“, else the arrival „Ankunft Lech 14:09“ |
/// | `transferring` | between ride legs | the next departure „Umsteigen in St. Anton“ |
/// | `arrived` | now ≥ final arrival − 1 min | „Angekommen in Lech“ |
/// | `cancelled` | a ride leg is cancelled | „RJX 19960 fällt aus“ |
///
/// All times are realtime-aware (effective); `progress` = elapsed / total, clamped to 0…1; `staleAfter` = next
/// event + 2 min. Pure: `now` is injected.
public enum LiveJourneySnapshotBuilder {
    public static func make(journey: Journey, quote: PriceQuote?, now: Date) -> LiveJourneySnapshot {
        let b = Builder(journey: journey, quote: quote, now: now)
        let legs = journey.legs
        let rides = b.rideIndices

        if let i = rides.first(where: { legs[$0].isCancelled || legs[$0].departure.isCancelled || legs[$0].arrival.isCancelled }) {
            let leg = legs[i]
            let title = leg.line.map { "\(LinePresentation.title($0)) fällt aus" } ?? "Fällt aus"
            return b.snapshot(.cancelled, line: leg, title: title, time: leg.departure.effective, platform: nil,
                              realtime: RealtimeLabel(state: .cancelled, text: "Fällt aus"), stale: false)
        }
        let finalArrival = journey.arrival ?? StopEvent()
        if let end = b.end, now >= end.addingTimeInterval(-60) {
            return b.snapshot(.arrived, line: rides.last.map { legs[$0] }, title: "Angekommen in \(b.destination)", time: end,
                              platform: finalArrival.platform?.text, realtime: RealtimePresentation.label(finalArrival),
                              progress: 1, stale: false)
        }
        guard let firstRide = rides.first else {
            // Walk-only journey.
            let phase: LiveJourneySnapshot.Phase = (b.start.map { now < $0 } ?? true) ? .beforeDeparture : .riding
            return b.snapshot(phase, line: nil, title: arrivalTitle(b.destination, b.end), time: b.end, platform: nil,
                              realtime: RealtimePresentation.label(finalArrival))
        }
        // Before the first ride departs (an access walk counts as before departure).
        if let dep = legs[firstRide].departure.effective, now < dep {
            let leg = legs[firstRide]
            let minutes = max(1, Int((dep.timeIntervalSince(now) / 60).rounded(.up)))
            let platform = JourneyPresentation.platformLabel(leg.departure, mode: leg.line?.mode)
            let title = "Abfahrt in \(minutes) min" + (platform.map { " · \($0.text)" } ?? "")
            return b.snapshot(.beforeDeparture, line: leg, title: title, time: dep, platform: platform?.display,
                              realtime: RealtimePresentation.label(leg.departure))
        }
        for (n, i) in rides.enumerated() {
            let leg = legs[i]
            let next = n + 1 < rides.count ? rides[n + 1] : nil
            if let arrival = leg.arrival.effective, now < arrival {
                if let next { return b.transfer(.riding, current: leg, from: i, to: next) }
                let platform = JourneyPresentation.platformLabel(leg.arrival, mode: leg.line?.mode)
                return b.snapshot(.riding, line: leg, title: arrivalTitle(DisplayNames.name(leg.destination.name), arrival), time: arrival,
                                  platform: platform?.display, realtime: RealtimePresentation.label(leg.arrival))
            }
            if let next, let nextDeparture = legs[next].departure.effective, now < nextDeparture {
                return b.transfer(.transferring, current: legs[next], from: i, to: next)
            }
        }
        // After the last ride, still walking to the destination.
        return b.snapshot(.riding, line: nil, title: arrivalTitle(b.destination, b.end), time: b.end, platform: nil,
                          realtime: RealtimePresentation.label(finalArrival))
    }

    /// „Ankunft Lech 14:09“.
    static func arrivalTitle(_ name: String, _ time: Date?) -> String {
        time.map { "Ankunft \(name) \(RealtimePresentation.time($0))" } ?? "Ankunft \(name)"
    }

    private struct Builder {
        let journey: Journey
        let quote: PriceQuote?
        let now: Date
        let rideIndices: [Int]
        let start: Date?
        let end: Date?
        let origin: String
        let destination: String
        let progress: Double

        init(journey: Journey, quote: PriceQuote?, now: Date) {
            self.journey = journey
            self.quote = quote
            self.now = now
            let legs = journey.legs
            rideIndices = legs.indices.filter { legs[$0].kind == .ride }
            start = journey.departure?.effective ?? rideIndices.first.flatMap { legs[$0].departure.effective }
            end = journey.arrival?.effective ?? rideIndices.last.flatMap { legs[$0].arrival.effective }
            origin = DisplayNames.name(journey.origin?.name ?? "")
            destination = DisplayNames.name(journey.destination?.name ?? "")
            if let start, let end, end > start {
                progress = min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
            } else {
                progress = 0
            }
        }

        func snapshot(_ phase: LiveJourneySnapshot.Phase, line leg: Leg?, title: String, time: Date?, platform: String?,
                      realtime: RealtimeLabel, transfer: TransferInfo? = nil, progress p: Double? = nil,
                      stale: Bool = true) -> LiveJourneySnapshot {
            LiveJourneySnapshot(journeyID: journey.id, phase: phase, originName: origin, destinationName: destination,
                                currentLine: leg?.line.map(LinePresentation.title), currentMode: leg?.line?.mode,
                                nextEventTitle: title, nextEventTime: time, nextEventPlatform: platform, nextEventRealtime: realtime,
                                progress: p ?? progress, transfer: transfer, arrival: end, regularPriceEUR: quote?.amountEUR,
                                staleAfter: stale ? time?.addingTimeInterval(120) : nil, updatedAt: now)
        }

        /// Next event = the departure of ride leg `b` after changing at the end of ride leg `a`.
        func transfer(_ phase: LiveJourneySnapshot.Phase, current: Leg, from a: Int, to b: Int) -> LiveJourneySnapshot {
            let next = journey.legs[b]
            let info = JourneyPresentation.transfer(journey, from: a, to: b)
            let station = info?.stationName ?? DisplayNames.name(journey.legs[a].destination.name)
            let platform = JourneyPresentation.platformLabel(next.departure, mode: next.line?.mode)
            return snapshot(phase, line: current, title: "Umsteigen in \(station)", time: next.departure.effective,
                            platform: platform?.display, realtime: RealtimePresentation.label(next.departure), transfer: info)
        }
    }
}
