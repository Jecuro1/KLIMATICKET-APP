// Linux stand-ins for Apple's SwiftDataMacros compiler plugin.
//
// The macro *declarations* (@Model, @Attribute, @Relationship, @Transient,
// @Query, #Unique, #Index, @ModelActor) come unchanged from the iOS SDK
// (Stubs/SwiftData, Stubs/_SwiftData_SwiftUI), so their arguments are
// type-checked exactly like in Xcode. These implementations only need to expand
// to something with the same *type-level* effect for client code:
//   @Model      -> PersistentModel + Observable conformance and the members
//                  PersistentModel requires (bodies trap, never executed)
//   @Query      -> computed `get` accessor + `_name: Query<Element, Result>` peer
//   @Attribute / @Relationship / @Transient / #Unique / #Index -> no code

import SwiftSyntax
import SwiftSyntaxMacros

private func typeName(of decl: some DeclGroupSyntax) -> String {
    if let c = decl.as(ClassDeclSyntax.self) { return c.name.text }
    if let s = decl.as(StructDeclSyntax.self) { return s.name.text }
    if let a = decl.as(ActorDeclSyntax.self) { return a.name.text }
    return "Self"
}

public struct PersistentModelMacro: MemberMacro, MemberAttributeMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let t = typeName(of: declaration)
        return [
            "public var persistentBackingData: any SwiftData.BackingData<\(raw: t)> { get { fatalError() } set { } }",
            "public static var schemaMetadata: [SwiftData.Schema.PropertyMetadata] { [] }",
            "public required init(backingData: any SwiftData.BackingData<\(raw: t)>) { fatalError() }",
        ]
    }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingAttributesFor member: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AttributeSyntax] {
        []
    }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        var out: [ExtensionDeclSyntax] = []
        for p in protocols {
            let name = p.trimmedDescription
            // Apple's macro lists Sendable as a possible conformance, but @Model
            // classes are not Sendable in practice (see docs/SWIFTUI_IOS26_NOTES.md §8.2).
            if name.hasSuffix("Sendable") { continue }
            out.append(DeclSyntax("extension \(type.trimmed): \(raw: name) {}").cast(ExtensionDeclSyntax.self))
        }
        return out
    }
}

public struct AttributePropertyMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct RelationshipPropertyMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct TransientPropertyMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct PersistedPropertyMacro: AccessorMacro, PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] { [] }
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct TransformablePersistedPropertyMacro: AccessorMacro, PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] { [] }
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct UniqueConstraintsMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct IndexMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

/// @ModelActor: adds the ModelActor requirements.
public struct PersistentModelActorMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        [
            "nonisolated public let modelExecutor: any SwiftData.ModelExecutor = { fatalError() }()",
            "nonisolated public let modelContainer: SwiftData.ModelContainer = { fatalError() }()",
            "public init(modelContainer: SwiftData.ModelContainer) { fatalError() }",
        ]
    }
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        try protocols.map { DeclSyntax("extension \(type.trimmed): \(raw: $0.trimmedDescription) {}").cast(ExtensionDeclSyntax.self) }
    }
}

/// @Query var trips: [Trip]  ->  var trips: [Trip] { get { _trips.wrappedValue } }
///                              var _trips: SwiftData.Query<[Trip].Element, [Trip]> = .init(<macro arguments>)
public struct QueryMacro: AccessorMacro, PeerMacro {
    private static func binding(_ declaration: some DeclSyntaxProtocol) -> (name: String, type: String)? {
        guard let v = declaration.as(VariableDeclSyntax.self), let b = v.bindings.first,
              let id = b.pattern.as(IdentifierPatternSyntax.self) else { return nil }
        return (id.identifier.text, b.typeAnnotation?.type.trimmedDescription ?? "")
    }

    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let (name, _) = binding(declaration) else { return [] }
        return ["get { _\(raw: name).wrappedValue }"]
    }

    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let (name, type) = binding(declaration), !type.isEmpty else { return [] }
        var args = ""
        if case .argumentList(let list)? = node.arguments { args = list.trimmedDescription }
        let isStatic = declaration.as(VariableDeclSyntax.self)?.modifiers.contains { $0.name.text == "static" } ?? false
        // NOTE: access level of Apple's peer is not documented; internal is the permissive choice.
        return ["\(raw: isStatic ? "static " : "")var _\(raw: name): SwiftData.Query<\(raw: type).Element, \(raw: type)> = .init(\(raw: args))"]
    }
}
