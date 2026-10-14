// Linux stand-ins for the FoundationModels macro plugin (FoundationModelsMacros). `@Generable` adds the conformance and the
// three members Generable requires, with traps as bodies (the harness never runs them); `@Guide` expands to nothing. The
// arguments of both are still type-checked against the declarations in Stubs/FoundationModels.

import SwiftSyntax
import SwiftSyntaxMacros

public struct GenerableMacro: ExtensionMacro, MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        [
            "public init(_ content: FoundationModels.GeneratedContent) throws { fatalError() }",
            "public var generatedContent: FoundationModels.GeneratedContent { fatalError() }",
            "public static var generationSchema: FoundationModels.GenerationSchema { fatalError() }",
        ]
    }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        [try ExtensionDeclSyntax("extension \(type): FoundationModels.Generable {}")]
    }
}

public struct GuideMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}
