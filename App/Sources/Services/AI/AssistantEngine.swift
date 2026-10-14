import Foundation
import KlimaCore
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Engine boundary (docs/LOCAL_AI.md §1)

/// The only place that talks to the on-device model. Everything above it (`LocalAssistant`) works with plain values, so
/// the rule-based fallbacks and the checks never depend on FoundationModels.
protocol AssistantEngine: Sendable {
    /// The system's state for the model and whether German is supported. Cheap; read on demand.
    func systemState() -> (state: AssistantSystemState, supportsGerman: Bool)
    /// Structured fields for a trip query (guided generation). Fields are not trusted: see `TripQueryValidator`.
    func tripQueryFields(for text: String, today: String) async throws -> TripQueryFields
    /// Free German text for `prompt` under `instructions`. Callers check the result (`AssistantNumberGuard`).
    func text(instructions: String, prompt: String) async throws -> String
}

/// Used where FoundationModels is not available at all (no SDK). The assistant then reports `.deviceNotEligible`.
struct UnavailableAssistantEngine: AssistantEngine {
    struct Unavailable: Error {}

    func systemState() -> (state: AssistantSystemState, supportsGerman: Bool) { (.deviceNotEligible, false) }

    func tripQueryFields(for text: String, today: String) async throws -> TripQueryFields { throw Unavailable() }

    func text(instructions: String, prompt: String) async throws -> String { throw Unavailable() }
}

enum AssistantEngineFactory {
    static func make() -> AssistantEngine {
        #if canImport(FoundationModels)
        FoundationModelsEngine()
        #else
        UnavailableAssistantEngine()
        #endif
    }
}

#if canImport(FoundationModels)

/// Guided-generation schema for a trip query. Every field is a plain string or Bool: empty means "not in the sentence".
@Generable(description: "Eine Zugsuche aus einem deutschen Satz")
struct GeneratedTripQuery {
    @Guide(description: "Abfahrtsort, wörtlich wie im Satz genannt. Leer, wenn nicht genannt.")
    var origin: String
    @Guide(description: "Ziel, wörtlich wie im Satz genannt. Leer, wenn nicht genannt.")
    var destination: String
    @Guide(description: "Datum der Hinfahrt als JJJJ-MM-TT. Leer, wenn nicht genannt.")
    var outboundDay: String
    @Guide(description: "Uhrzeit der Hinfahrt als HH:MM. Leer, wenn nicht genannt.")
    var outboundTime: String
    @Guide(description: "Datum der Rückfahrt als JJJJ-MM-TT. Leer, wenn nicht genannt.")
    var returnDay: String
    @Guide(description: "true, wenn die Uhrzeit die Ankunft meint (bis, spätestens), sonst false.")
    var isArrival: Bool
}

/// The on-device Apple model (iOS 26). It runs in the foreground only; no session outlives the call.
struct FoundationModelsEngine: AssistantEngine {
    func systemState() -> (state: AssistantSystemState, supportsGerman: Bool) {
        let model = SystemLanguageModel.default
        let state: AssistantSystemState
        switch model.availability {
        case .available:
            state = .available
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled: state = .appleIntelligenceNotEnabled
            case .modelNotReady: state = .modelNotReady
            case .deviceNotEligible: state = .deviceNotEligible
            @unknown default: state = .deviceNotEligible
            }
        }
        return (state, model.supportsLocale(Locale(identifier: "de_AT")))
    }

    func tripQueryFields(for text: String, today: String) async throws -> TripQueryFields {
        let session = LanguageModelSession(model: SystemLanguageModel.default,
                                           instructions: AssistantPrompts.tripQueryInstructions(today: today))
        let response = try await session.respond(to: text, generating: GeneratedTripQuery.self,
                                                 options: GenerationOptions(temperature: 0))
        let fields = response.content
        return TripQueryFields(origin: fields.origin, destination: fields.destination, outboundDay: fields.outboundDay,
                               outboundTime: fields.outboundTime, returnDay: fields.returnDay, isArrival: fields.isArrival)
    }

    func text(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.3))
        return response.content
    }
}

#endif
