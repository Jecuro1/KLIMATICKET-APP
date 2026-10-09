// Linux stand-ins for Apple's SwiftUIMacros plugin (@Entry, @Animatable).

import SwiftSyntax
import SwiftSyntaxMacros

/// @Entry var name: T = default   (inside extension EnvironmentValues / Transaction /
/// ContainerValues / FocusedValues)  ->  get/set through a private key type.
public struct EntryMacro: AccessorMacro, PeerMacro {
    private static func info(_ declaration: some DeclSyntaxProtocol) -> (name: String, type: String, value: String)? {
        guard let v = declaration.as(VariableDeclSyntax.self), let b = v.bindings.first,
              let id = b.pattern.as(IdentifierPatternSyntax.self) else { return nil }
        let type = b.typeAnnotation?.type.trimmedDescription ?? ""
        let value = b.initializer?.value.trimmedDescription ?? "nil"
        return (id.identifier.text, type, value)
    }

    private static func keyProtocol(_ context: some MacroExpansionContext) -> String {
        for ctx in context.lexicalContext {
            if let ext = ctx.as(ExtensionDeclSyntax.self) {
                let t = ext.extendedType.trimmedDescription
                if t.hasSuffix("Transaction") { return "SwiftUICore.TransactionKey" }
                if t.hasSuffix("ContainerValues") { return "SwiftUICore.ContainerValueKey" }
                if t.hasSuffix("FocusedValues") { return "SwiftUI.FocusedValueKey" }
            }
        }
        return "SwiftUICore.EnvironmentKey"
    }

    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let i = info(declaration) else { return [] }
        return ["get { self[__Key_\(raw: i.name).self] }", "set { self[__Key_\(raw: i.name).self] = newValue }"]
    }

    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let i = info(declaration) else { return [] }
        let proto = keyProtocol(context)
        let valueType = i.type.isEmpty ? "" : "typealias Value = \(i.type)\n"
        if proto == "SwiftUI.FocusedValueKey" {
            return ["private struct __Key_\(raw: i.name): \(raw: proto) { \(raw: valueType) }"]
        }
        return ["private struct __Key_\(raw: i.name): \(raw: proto) { \(raw: valueType)static var defaultValue: Value { \(raw: i.value) } }"]
    }
}

public struct EntryDefaultValueMacro: AccessorMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] { [] }
}

/// @Animatable: Animatable conformance; `animatableData` is left to the protocol's
/// default (the real macro synthesises it from the stored properties).
public struct AnimatableValuesMacro: ExtensionMacro, MemberMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        try protocols.map { DeclSyntax("extension \(type.trimmed): \(raw: $0.trimmedDescription) {}").cast(ExtensionDeclSyntax.self) }
    }
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct AnimatableIgnoredMacro: AccessorMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] { [] }
}

public struct AnimatableValuesDataMacro: AccessorMacro {
    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] { [] }
}
