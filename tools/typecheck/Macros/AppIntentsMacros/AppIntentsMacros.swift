// Linux stand-ins for Apple's AppIntentsMacros plugin. The app does not use these
// macros yet; they expand to nothing (arguments are still type-checked).

import SwiftSyntax
import SwiftSyntaxMacros

public struct EntityPropertyMacro: PeerMacro, AccessorMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] { [] }
}
public struct AppEntityMacro: MemberAttributeMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingAttributesFor member: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AttributeSyntax] { [] }
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] { [] }
}
public struct _UnionValueMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct AppEnumMacro: MemberAttributeMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingAttributesFor member: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AttributeSyntax] { [] }
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] { [] }
}

public struct AppIntentMacro: MemberAttributeMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingAttributesFor member: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AttributeSyntax] { [] }
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] { [] }
}

public struct AssistantEntityMacros: MemberAttributeMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingAttributesFor member: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AttributeSyntax] { [] }
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] { [] }
}

public struct AssistantEnumMacros: MemberAttributeMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingAttributesFor member: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AttributeSyntax] { [] }
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] { [] }
}

public struct AssistantIntentMacros: MemberAttributeMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingAttributesFor member: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AttributeSyntax] { [] }
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] { [] }
}
