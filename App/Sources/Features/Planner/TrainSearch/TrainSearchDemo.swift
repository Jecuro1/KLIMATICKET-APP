import Foundation
import SwiftUI
import KlimaCore

// Zugsuche demo (-KBDemo and CI screenshots): the demo runs of the Zug-Radar, for today, tomorrow and next week. No network.
// Later days carry no realtime, as in the live timetable.

struct DemoTrainSearchService: TrainSearchService {
    var now: @Sendable () -> Date = { Date() }

    func trainRuns(_ query: TrainSearchQuery) async throws -> TrainSearchResult {
        let t = now()
        guard let name = TrainName(query.input) else { return .empty }
        var runs: [TrainRun] = []
        for run in DemoScotty.runs where name.matches(run.line) {
            for days in [0, 1, 7] {
                let stops = DemoScotty.stopovers(run, now: t.addingTimeInterval(Double(days) * 86_400))
                guard let first = stops.first, let last = stops.last else { continue }
                let origin = days == 0 ? first : planOnly(first), destination = days == 0 ? last : planOnly(last)
                runs.append(TrainRun(tripID: "\(run.tripID)|+\(days)", line: run.line, direction: run.direction,
                                     origin: origin, destination: destination))
            }
        }
        return TrainSearchResult(source: .journeyMatch, runs: runs, realtimeUpdatedAt: t)
    }

    private func planOnly(_ stop: Stopover) -> Stopover {
        var copy = stop
        copy.arrival = stop.arrival.map { event in var e = event; e.realtime = nil; e.prognosis = nil; return e }
        copy.departure = stop.departure.map { event in var e = event; e.realtime = nil; e.prognosis = nil; return e }
        return copy
    }
}

// MARK: trainsearch – CI screenshot hosts (demo data, no network)

struct TrainSearchScreenshotHost: View {
    static let screens: Set<String> = ["trainSearch", "trainResult"]

    let screen: String

    var body: some View {
        switch screen {
        case "trainResult":   // MARK: trainsearch – the runs of RJX 66 (today with realtime, then the timetable period)
            TrainSearchView(initialText: "RJX 66", autoSubmit: true)
        default:              // MARK: trainsearch – the field with suggestions for "RJX"
            TrainSearchView(initialText: "RJX")
        }
    }
}
