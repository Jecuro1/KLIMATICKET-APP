import Foundation
import Observation
import KlimaCore

/// The on-device assistant (docs/LOCAL_AI.md). One object, owned by `AppState`. It asks the model only in the foreground,
/// never sends a request off the device, and falls back to the rules whenever the model is switched off, unavailable, or
/// its answer fails a check. Demo mode (`-KBDemo`, screenshots) never asks the model.
@MainActor
@Observable
final class LocalAssistant {
    private(set) var systemState: AssistantSystemState = .modelNotReady
    private(set) var supportsGerman = false
    /// Screenshot scenes show a chosen state (demo only).
    private(set) var previewState: AssistantSystemState?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let engine: AssistantEngine
    @ObservationIgnored let isDemo: Bool
    /// Last model answers for the same facts, so a foreground return does not ask the model again (memory only).
    @ObservationIgnored private var recapCache: [String: String] = [:]

    init(settings: AppSettings, engine: AssistantEngine = AssistantEngineFactory.make(),
         isDemo: Bool = LaunchMode.useDemoData) {
        self.settings = settings
        self.engine = engine
        self.isDemo = isDemo
        refresh()
    }

    // MARK: State

    var isSwitchedOn: Bool { settings.localAIEnabled }

    /// The state the Settings page and the sheets show. Demo mode reports an available model unless a scene says otherwise.
    var effectiveState: AssistantSystemState {
        guard isDemo else { return systemState }
        return previewState ?? .available
    }

    var availability: AssistantAvailability {
        AssistantAvailabilityResolver.resolve(system: effectiveState,
                                              supportsGerman: isDemo ? true : supportsGerman,
                                              switchedOn: isSwitchedOn)
    }

    /// Whether the model may be asked right now.
    private var canUseModel: Bool { !isDemo && availability == .available }

    /// Reads the system state again (the Settings page calls it on appear; Apple Intelligence may have been switched on).
    func refresh() {
        let probe = engine.systemState()
        systemState = probe.state
        supportsGerman = probe.supportsGerman
    }

    func showPreview(_ state: AssistantSystemState?) {
        guard isDemo else { return }
        previewState = state
    }

    // MARK: Trip query ("Suche in Worten")

    struct TripQueryResult {
        var draft: TripQueryDraft
        var origin: Station?
        var destination: Station?
        /// Place words that matched no station: the planner keeps those slots empty and says so.
        var unresolved: [String]
        var source: AssistantSource
    }

    func parseTripQuery(_ text: String, stations: StationIndex, now: Date = Date()) async -> TripQueryResult {
        let rules = TripQueryParser.parse(text, now: now)
        var draft = rules
        if canUseModel, let fields = try? await engine.tripQueryFields(for: text, today: AssistantFormat.isoDay(now)) {
            // The rules run first and win; the model only fills what they left open, and only with fields the sentence supports.
            draft = rules.filled(from: TripQueryValidator.validate(fields, sourceText: text, now: now).draft)
        }
        var unresolved: [String] = []
        func station(_ name: String?) -> Station? {
            guard let name else { return nil }
            let found = AssistantStationMatch.station(for: name, in: stations)
            if found == nil { unresolved.append(name) }
            return found
        }
        let origin = station(draft.origin)
        let destination = station(draft.destination)
        let source: AssistantSource = isDemo ? .demo : draft.source
        return TripQueryResult(draft: draft, origin: origin, destination: destination, unresolved: unresolved, source: source)
    }

    // MARK: Balance ("Warum lohnt sich mein Ticket?")

    func explainBalance(_ facts: BalanceFacts) async -> AssistantText {
        if isDemo { return AssistantText(text: facts.ruleText, source: .demo) }
        let rules = AssistantText(text: facts.ruleText, source: .rules)
        guard canUseModel, let text = await modelText(instructions: AssistantPrompts.balanceInstructions,
                                                      prompt: AssistantPrompts.facts(facts.lines),
                                                      facts: facts.lines, maxLength: 700) else { return rules }
        return AssistantText(text: text, source: .model)
    }

    // MARK: Weekly recap (the Sunday notification)

    func weeklyRecap(_ facts: WeeklyRecapFacts) async -> AssistantText {
        if isDemo { return AssistantText(text: facts.ruleText, source: .demo) }
        let rules = AssistantText(text: facts.ruleText, source: .rules)
        guard canUseModel, facts.tripsThisWeek > 0 else { return rules }
        let key = facts.lines.joined(separator: "|")
        if let cached = recapCache[key] { return AssistantText(text: cached, source: .model) }
        guard let text = await modelText(instructions: AssistantPrompts.recapInstructions,
                                         prompt: AssistantPrompts.facts(facts.lines), facts: facts.lines, maxLength: 160) else {
            return rules
        }
        recapCache[key] = text
        return AssistantText(text: text, source: .model)
    }

    // MARK: Route suggestion wording

    func routeWording(_ suggestion: RouteTimeSuggestion, fromName: String, toName: String) async -> AssistantText {
        let rules = AssistantText(text: suggestion.ruleText(fromName: fromName, toName: toName), source: .rules)
        if isDemo { return AssistantText(text: rules.text, source: .demo) }
        let facts = suggestion.facts(fromName: fromName, toName: toName)
        guard canUseModel, let text = await modelText(instructions: AssistantPrompts.routeInstructions,
                                                      prompt: AssistantPrompts.facts(facts), facts: facts, maxLength: 160) else {
            return rules
        }
        return AssistantText(text: text, source: .model)
    }

    // MARK: Checks

    /// The model's text, kept only when it is short, on one paragraph and every number in it is one of the facts.
    private func modelText(instructions: String, prompt: String, facts: [String], maxLength: Int) async -> String? {
        guard let raw = try? await engine.text(instructions: instructions, prompt: prompt) else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxLength, !text.contains("\n"),
              AssistantNumberGuard.accepts(text, facts: facts) else { return nil }
        return text
    }
}

/// Maps a typed place to a station without guessing: an exact name or alias, or a search hit whose first word is the same.
enum AssistantStationMatch {
    static func station(for text: String, in index: StationIndex) -> Station? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }
        if let exact = index.station(named: typed) { return exact }
        guard let hit = index.search(typed, limit: 1).first else { return nil }
        let wanted = firstWord(typed)
        return !wanted.isEmpty && firstWord(hit.name) == wanted ? hit : nil
    }

    private static func firstWord(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT"))
        let first = folded.split(whereSeparator: { $0 == " " || $0 == "-" }).first.map(String.init) ?? ""
        return first.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}
