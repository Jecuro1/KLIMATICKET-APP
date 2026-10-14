import Foundation
import Observation
import KlimaCore

// Zugsuche state (docs/OEBB_LIVE.md §R9). A request is sent only on submit, never while typing. The recent searches are a
// per-device convenience in UserDefaults; nothing else depends on them.

@MainActor @Observable
final class TrainSearchModel {
    enum Phase: Equatable {
        case idle, invalid, loading, results, noMatch
        case failed(String)
    }

    var text = ""
    private(set) var phase: Phase = .idle
    private(set) var name: TrainName?
    /// Runs of exactly this train, earliest planned date first.
    private(set) var runs: [TrainRun] = []
    /// Runs the server returned for a longer name ("RJX 660" for "RJX 66"); they are not shown.
    private(set) var hiddenCount = 0
    private(set) var realtimeUpdatedAt: Date?
    private(set) var recent: [String]

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private static let recentKey = "trainsearch.recent"
    private static let recentLimit = 8

    init() {
        recent = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
    }

    var suggestions: [String] { TrainSearchSuggestions.make(for: text, recent: recent) }

    /// Searches the typed name. Text that is not a train name ends in `.invalid` without a request.
    func submit(using service: (any TrainSearchService)?) {
        guard let parsed = TrainName(text) else {
            task?.cancel()
            name = nil
            runs = []
            phase = .invalid
            return
        }
        name = parsed
        text = parsed.display
        remember(parsed.display)
        task?.cancel()
        guard let service else {
            phase = .failed("Die Zugsuche ist gerade nicht verfügbar.")
            return
        }
        phase = .loading
        task = Task {
            do {
                let result = try await service.trainRuns(TrainSearchQuery(name: parsed))
                if Task.isCancelled { return }
                self.runs = result.runs(for: parsed)
                self.hiddenCount = result.runs.filter { !parsed.matches($0.line) }.count
                self.realtimeUpdatedAt = result.realtimeUpdatedAt
                self.phase = self.runs.isEmpty ? .noMatch : .results
            } catch {
                if Task.isCancelled { return }
                self.runs = []
                self.hiddenCount = 0
                self.phase = .failed(LiveMessage.text(for: error))
            }
        }
    }

    /// Clears the result and the phase (the field was emptied).
    func reset() {
        task?.cancel()
        task = nil
        name = nil
        runs = []
        hiddenCount = 0
        realtimeUpdatedAt = nil
        phase = .idle
    }

    private func remember(_ value: String) {
        var list = recent.filter { $0.caseInsensitiveCompare(value) != .orderedSame }
        list.insert(value, at: 0)
        recent = Array(list.prefix(Self.recentLimit))
        UserDefaults.standard.set(recent, forKey: Self.recentKey)
    }
}
