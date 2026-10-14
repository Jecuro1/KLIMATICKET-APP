// Hand-written stand-in for FoundationModels (iOS 26, the on-device Apple Intelligence model). The declarations below are
// copied from the iOS 26.4 SDK interface (FoundationModels.swiftinterface, the mirror used by gen/fetch_sdk.sh), trimmed to
// what App/Sources/Services/AI uses. Bodies trap: the harness only type-checks. The two macros expand through the plugin
// Macros/FoundationModelsMacros (GenerableMacro, GuideMacro), so @Generable structs conform as they do in Xcode.
// The app targets iOS 26.0 (project.yml), so no #available is needed.

@_exported import Foundation
@_exported import FoundationShim

@inline(never) @usableFromInline func _fmStub() -> Never { fatalError("type-check stub") }

// MARK: Availability of the system model

public final class SystemLanguageModel: Sendable {
    public static var `default`: SystemLanguageModel { _fmStub() }
    public var availability: Availability { _fmStub() }
    public var isAvailable: Bool { _fmStub() }
    public func supportsLocale(_ locale: Locale = Locale.current) -> Bool { _fmStub() }
    public init(useCase: UseCase = .general, guardrails: Guardrails = .default) { _fmStub() }

    public struct UseCase: Sendable, Equatable {
        public static var general: UseCase { _fmStub() }
        public static var contentTagging: UseCase { _fmStub() }
        public static func == (a: UseCase, b: UseCase) -> Bool { _fmStub() }
    }

    public struct Guardrails: Sendable {
        public static var `default`: Guardrails { _fmStub() }
        public static var permissiveContentTransformations: Guardrails { _fmStub() }
    }

    public enum Availability: Equatable, Sendable {
        public enum UnavailableReason: Equatable, Sendable {
            case deviceNotEligible
            case appleIntelligenceNotEnabled
            case modelNotReady
        }
        case available
        case unavailable(UnavailableReason)
    }
}

// MARK: Generation options and results

public struct GenerationOptions: Sendable, Equatable {
    public struct SamplingMode: Sendable, Equatable {
        public static var greedy: SamplingMode { _fmStub() }
        public static func random(top k: Int, seed: UInt64? = nil) -> SamplingMode { _fmStub() }
        public static func random(probabilityThreshold: Double, seed: UInt64? = nil) -> SamplingMode { _fmStub() }
    }
    public var sampling: SamplingMode?
    public var temperature: Double?
    public var maximumResponseTokens: Int?
    public init(sampling: SamplingMode? = nil, temperature: Double? = nil, maximumResponseTokens: Int? = nil) {
        self.sampling = sampling
        self.temperature = temperature
        self.maximumResponseTokens = maximumResponseTokens
    }
}

public struct GeneratedContent: Sendable, Equatable {
    public init(json: String) throws { _fmStub() }
    public var jsonString: String { _fmStub() }
}

public struct GenerationSchema: Sendable, Codable, CustomDebugStringConvertible {
    public var debugDescription: String { _fmStub() }
    public init(from decoder: any Decoder) throws { _fmStub() }
    public func encode(to encoder: any Encoder) throws { _fmStub() }
}

public struct GenerationGuide<Value>: Sendable {}

// MARK: Generable

public protocol ConvertibleFromGeneratedContent: SendableMetatype {
    init(_ content: GeneratedContent) throws
}

public protocol PromptRepresentable {
    var promptRepresentation: Prompt { get }
}

public protocol InstructionsRepresentable {
    var instructionsRepresentation: Instructions { get }
}

public protocol ConvertibleToGeneratedContent: InstructionsRepresentable, PromptRepresentable {
    var generatedContent: GeneratedContent { get }
}

public protocol Generable: ConvertibleFromGeneratedContent, ConvertibleToGeneratedContent {
    associatedtype PartiallyGenerated: ConvertibleFromGeneratedContent = Self
    static var generationSchema: GenerationSchema { get }
}

extension String: PromptRepresentable, Generable {
    public var promptRepresentation: Prompt { _fmStub() }
    public init(_ content: GeneratedContent) throws { _fmStub() }
    public var generatedContent: GeneratedContent { _fmStub() }
    public var instructionsRepresentation: Instructions { _fmStub() }
    public static var generationSchema: GenerationSchema { _fmStub() }
}

extension Bool: Generable {
    public init(_ content: GeneratedContent) throws { _fmStub() }
    public var generatedContent: GeneratedContent { _fmStub() }
    public var instructionsRepresentation: Instructions { _fmStub() }
    public var promptRepresentation: Prompt { _fmStub() }
    public static var generationSchema: GenerationSchema { _fmStub() }
}

extension Int: Generable {
    public init(_ content: GeneratedContent) throws { _fmStub() }
    public var generatedContent: GeneratedContent { _fmStub() }
    public var instructionsRepresentation: Instructions { _fmStub() }
    public var promptRepresentation: Prompt { _fmStub() }
    public static var generationSchema: GenerationSchema { _fmStub() }
}

extension Double: Generable {
    public init(_ content: GeneratedContent) throws { _fmStub() }
    public var generatedContent: GeneratedContent { _fmStub() }
    public var instructionsRepresentation: Instructions { _fmStub() }
    public var promptRepresentation: Prompt { _fmStub() }
    public static var generationSchema: GenerationSchema { _fmStub() }
}

/// `@Generable(description:)` on a struct or enum: the plugin adds the conformance and the members (Macros/FoundationModelsMacros).
@attached(extension, conformances: Generable, names: named(init(_:)), named(generatedContent))
@attached(member, names: arbitrary)
public macro Generable(description: String? = nil) = #externalMacro(module: "FoundationModelsMacros", type: "GenerableMacro")

/// `@Guide(description:)` on a stored property of a @Generable type; the plugin adds nothing, the arguments are type-checked.
@attached(peer)
public macro Guide<T: Generable>(description: String? = nil, _ guides: GenerationGuide<T>...) = #externalMacro(module: "FoundationModelsMacros", type: "GuideMacro")

@attached(peer)
public macro Guide(description: String) = #externalMacro(module: "FoundationModelsMacros", type: "GuideMacro")

// MARK: Prompts and instructions

public struct Prompt: Sendable, Equatable {
    public init(_ content: some PromptRepresentable) { _fmStub() }
}

public struct Instructions: Sendable, Equatable {
    public init(_ content: some InstructionsRepresentable) { _fmStub() }
}

public protocol Tool: Sendable {}

// MARK: Session

public final class LanguageModelSession {
    public init(model: SystemLanguageModel = .default, tools: [any Tool] = [], instructions: String? = nil) { _fmStub() }
    public init(model: SystemLanguageModel = .default, tools: [any Tool] = [], instructions: Instructions?) { _fmStub() }

    public var isResponding: Bool { _fmStub() }

    public struct Response<Content> where Content: Generable {
        public let content: Content
        public let rawContent: GeneratedContent
    }

    public enum GenerationError: Error, LocalizedError {
        case exceededContextWindowSize(Context)
        case assetsUnavailable(Context)
        case guardrailViolation(Context)
        case unsupportedGuide(Context)
        case unsupportedLanguageOrLocale(Context)
        case decodingFailure(Context)
        case rateLimited(Context)
        case concurrentRequests(Context)
        case refusal(Refusal, Context)

        public struct Context: Sendable {
            public let debugDescription: String
            public init(debugDescription: String) { _fmStub() }
        }

        public struct Refusal: Sendable {
            public var explanation: Response<String> { _fmStub() }
        }

        public var errorDescription: String? { _fmStub() }
    }

    nonisolated(nonsending) public func respond(to prompt: Prompt, options: GenerationOptions = GenerationOptions()) async throws -> Response<String> {
        _fmStub()
    }

    @_disfavoredOverload
    nonisolated(nonsending) public func respond(to prompt: String, options: GenerationOptions = GenerationOptions()) async throws -> Response<String> {
        _fmStub()
    }

    nonisolated(nonsending) public func respond<Content>(to prompt: Prompt, generating type: Content.Type = Content.self,
                                                         includeSchemaInPrompt: Bool = true,
                                                         options: GenerationOptions = GenerationOptions()) async throws -> Response<Content>
        where Content: Generable {
        _fmStub()
    }

    @_disfavoredOverload
    nonisolated(nonsending) public func respond<Content>(to prompt: String, generating type: Content.Type = Content.self,
                                                         includeSchemaInPrompt: Bool = true,
                                                         options: GenerationOptions = GenerationOptions()) async throws -> Response<Content>
        where Content: Generable {
        _fmStub()
    }
}
