import Foundation
import KlimaCore

// MARK: anschluss – synthetic data for the Anschluss-Wächter (-KBDemo and CI screenshots). Built on the demo follow run of the
// radar (`DemoScotty` „RJX 66“ Wien Hbf → … → Linz Hbf, +5 at Linz) with a 3-minute walk and an invented „REX 41 Linz Hbf →
// Summerau“; times relative to now. No network, no notification permission, no Live Activity, no file.

enum GuardDemo {
    /// The scenes of `GuardScreenshotHost`.
    enum Scene: String, CaseIterable {
        case safe, tighter, shaky, missed, cancelled, noRealtime, alternatives, accessory, ax5
    }

    static let feederTripID = "demo|radar|RJX66"
    static var wien: Location { DemoScotty.location("Wien Hbf") }
    static var linz: Location { DemoScotty.location("Linz Hbf") }
    static var summerau: Location { DemoScotty.location("Summerau") }
    static var pregarten: Location { DemoScotty.location("Pregarten") }

    /// Minutes from now of the demo run: Wien Hbf departs −22, Linz Hbf arrives +26 (planned).
    static let feederDeparture: Double = -22
    static let feederArrival: Double = 26
    static let walk = 3

    /// The scripted connection of one scene: planned connecting departure (minutes from now), its delay, platforms.
    struct Script {
        var connectionPlanned: Double
        var connectionDelay: Int?
        var platform = "5"
        var realtimePlatform: String?
        var cancelled = false
        /// Earlier answers: (minutes ago, feeder delay at Linz, connection delay); the last answer is now with the run's +5.
        var history: [(ago: Double, feederDelay: Int, connectionDelay: Int?)] = []
        var feederDelay: Int? = 5
    }

    static func script(_ scene: Scene) -> Script {
        switch scene {
        case .safe:
            return Script(connectionPlanned: 41, connectionDelay: 1, history: [(4, 5, 1)])
        case .tighter:
            return Script(connectionPlanned: 40, connectionDelay: 0, history: [(4, 2, 0)])
        case .shaky, .accessory, .ax5:
            return Script(connectionPlanned: 34, connectionDelay: 1, realtimePlatform: "7", history: [(3, 2, 1)])
        case .missed:
            return Script(connectionPlanned: 30, connectionDelay: 0, history: [(2, 2, 0)])
        case .cancelled, .alternatives:
            return Script(connectionPlanned: 38, connectionDelay: 0, cancelled: true)
        case .noRealtime:
            return Script(connectionPlanned: 38, connectionDelay: nil, feederDelay: nil)
        }
    }

    private static func event(_ minutes: Double, now: Date, delay: Int?, platform: String? = nil, realtimePlatform: String? = nil,
                              cancelled: Bool = false) -> StopEvent {
        let planned = now.addingTimeInterval(minutes * 60)
        return StopEvent(planned: planned, realtime: delay.map { planned.addingTimeInterval(Double($0) * 60) },
                         plannedPlatform: platform.map { Platform(text: $0, kind: .track) },
                         realtimePlatform: (delay == nil ? nil : (realtimePlatform ?? platform)).map { Platform(text: $0, kind: .track) },
                         isCancelled: cancelled, prognosis: delay == nil ? nil : .prognosed)
    }

    /// The followed connection: RJX 66 Wien Hbf → Linz Hbf, walk 3 min, REX 41 Linz Hbf → Summerau (1 h 2 min).
    static func journey(_ s: Script, feederDelay: Int?, connectionDelay: Int?, now: Date) -> Journey {
        let arrival = now.addingTimeInterval(feederArrival * 60)
        let feeder = Leg(id: "demo-guard-feeder", kind: .ride, origin: wien, destination: linz,
                         departure: event(feederDeparture, now: now, delay: feederDelay == nil ? nil : 0, platform: "9"),
                         arrival: event(feederArrival, now: now, delay: feederDelay, platform: "4"),
                         line: DemoScotty.rjx("RJX 66", number: "66"), direction: "Innsbruck Hbf", tripID: feederTripID,
                         isReachable: true)
        let walkLeg = Leg(id: "demo-guard-walk", kind: .walk, origin: linz, destination: linz,
                          departure: StopEvent(planned: arrival), arrival: StopEvent(planned: arrival.addingTimeInterval(Double(walk) * 60)),
                          walkDurationSeconds: walk * 60)
        let connection = Leg(id: "demo-guard-connection", kind: .ride, origin: linz, destination: summerau,
                             departure: event(s.connectionPlanned, now: now, delay: connectionDelay, platform: s.platform,
                                              realtimePlatform: s.realtimePlatform, cancelled: s.cancelled),
                             arrival: event(s.connectionPlanned + 62, now: now, delay: connectionDelay, platform: "1", cancelled: s.cancelled),
                             line: DemoScotty.regional("REX 41", number: "41"), direction: "Summerau", tripID: "demo|guard|REX41",
                             isReachable: true, isCancelled: s.cancelled)
        return Journey(legs: [feeder, walkLeg, connection], durationSeconds: Int((s.connectionPlanned + 62 - feederDeparture) * 60),
                       changes: 1, refreshToken: "demo-guard-token", realtimeUpdatedAt: now)
    }

    /// The follow target of the scenes: the demo run from Wien Hbf to Linz Hbf with the change to REX 41.
    static func followTarget(_ scene: Scene, now: Date) -> LiveFollowTarget {
        let s = script(scene)
        return LiveFollowTarget(tripID: feederTripID, lineName: "RJX 66", boardingStop: wien, alightStop: linz,
                                plannedDeparture: now.addingTimeInterval(feederDeparture * 60),
                                plannedArrival: now.addingTimeInterval(feederArrival * 60),
                                transfer: FollowTransfer(stationName: "Linz Hbf", plannedDeparture: now.addingTimeInterval(s.connectionPlanned * 60),
                                                         lineName: "REX 41", walkMinutes: walk))
    }

    static func record(_ scene: Scene, now: Date) -> GuardRecord {
        let s = script(scene)
        let first = s.history.first
        return GuardRecord(followTripID: feederTripID,
                           journey: journey(s, feederDelay: first?.feederDelay ?? s.feederDelay, connectionDelay: first?.connectionDelay ?? s.connectionDelay, now: now),
                           journeyAt: now.addingTimeInterval(-6 * 60), products: .klimaTicket, klimaTicketOnly: true,
                           createdAt: now.addingTimeInterval(-25 * 60))
    }

    /// The scripted answers of a scene, oldest first; the last one is now.
    static func answers(_ scene: Scene, now: Date) -> [(journey: Journey, at: Date)] {
        let s = script(scene)
        var out = s.history.map { h in
            (journey: journey(s, feederDelay: h.feederDelay, connectionDelay: h.connectionDelay, now: now), at: now.addingTimeInterval(-h.ago * 60))
        }
        out.append((journey: journey(s, feederDelay: s.feederDelay, connectionDelay: s.connectionDelay, now: now), at: now))
        return out
    }

    /// Alternatives from Linz Hbf to Summerau: REX 43, a change to Bus 291 in Pregarten, R 3443 and a later REX (top three shown).
    static func alternatives(after date: Date, now: Date) -> [Journey] {
        func ride(_ id: String, _ line: Line, from: Location, to: Location, dep: Double, arr: Double, platform: String?) -> Leg {
            Leg(id: id, kind: .ride, origin: from, destination: to, departure: event(dep, now: now, delay: 0, platform: platform),
                arrival: event(arr, now: now, delay: 0), line: line, direction: to.name, tripID: "demo|guard|\(id)")
        }
        let base = max(0, date.timeIntervalSince(now) / 60)
        let rex43 = Journey(legs: [ride("REX43", DemoScotty.regional("REX 43", number: "43"), from: linz, to: summerau,
                                        dep: base + 10, arr: base + 72, platform: "3")], changes: 0)
        let bus = DemoJourneys.bus("291")
        let viaPregarten = Journey(legs: [ride("REX4", DemoScotty.regional("REX 4", number: "4"), from: linz, to: pregarten,
                                               dep: base + 31, arr: base + 56, platform: "6"),
                                          ride("Bus291", bus, from: pregarten, to: summerau, dep: base + 63, arr: base + 91, platform: nil)],
                                   changes: 1)
        let r3443 = Journey(legs: [ride("R3443", DemoScotty.regional("R 3443", number: "3443"), from: linz, to: summerau,
                                        dep: base + 24, arr: base + 104, platform: "8")], changes: 0)
        let later = Journey(legs: [ride("REX45", DemoScotty.regional("REX 45", number: "45"), from: linz, to: summerau,
                                        dep: base + 70, arr: base + 132, platform: "3")], changes: 0)
        return [later, r3443, viaPregarten, rex43]
    }

    /// Scripted network for the scenes: the last answer again, the demo alternatives.
    static func services(_ scene: Scene, now: Date) -> ConnectionGuardService.Services {
        let last = answers(scene, now: now).last?.journey
        return ConnectionGuardService.Services(
            refresh: { _ in
                guard let last else { throw LiveError.noConnection }
                return last
            },
            trip: nil,
            journeys: { query in JourneyPage(journeys: alternatives(after: query.date, now: now)) },
            unavailable: nil)
    }

    /// `-KBDemo` outside screenshots: the registered demo connection answers as it is (the demo timetable has no Reconstruction),
    /// the demo timetable's JourneyDetails and searches.
    static func liveDemoServices(journey: Journey) -> ConnectionGuardService.Services {
        let timetable = DemoTimetableService()
        return ConnectionGuardService.Services(
            refresh: { _ in journey },
            trip: { id in try await timetable.trip(id, includePolyline: false) },
            journeys: { query in try await timetable.journeys(query) },
            unavailable: nil)
    }

    /// Installs a scene into the shared service (the follow of the scene must be running for the card to show it).
    @MainActor
    static func install(_ scene: Scene, now: Date) {
        let service = ConnectionGuardService.shared
        let record = record(scene, now: now)
        var alternativesState: ConnectionGuardService.Alternatives = .idle
        var searchedAt: Date?
        if scene == .missed || scene == .alternatives || scene == .cancelled {
            var engine = GuardEngine(record: record)
            _ = engine.reassess(now: now)
            for answer in answers(scene, now: now) {
                engine.begin()
                _ = engine.applyReconstruction(answer.journey, sentAt: answer.at, now: answer.at)
            }
            if let query = GuardAlternatives.query(journey: engine.record.journey, assessment: engine.assessment,
                                                   products: record.products, now: now) {
                let picked = GuardAlternatives.pick(alternatives(after: query.date, now: now), after: query.date,
                                                    originalArrival: engine.record.journey.arrival?.planned)
                alternativesState = .loaded(picked, query: query)
                searchedAt = now.addingTimeInterval(-40)
            }
        }
        service.installScripted(record: record, answers: answers(scene, now: now),
                                status: .updated(at: now, next: now.addingTimeInterval(scene == .safe || scene == .noRealtime ? 120 : 60)),
                                services: services(scene, now: now), alternatives: alternativesState, searchedAt: searchedAt)
        if scene == .missed || scene == .alternatives { service.requestScriptedAlternatives() }
    }
}
