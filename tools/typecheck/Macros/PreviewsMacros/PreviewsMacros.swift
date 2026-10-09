// Linux stand-ins for Apple's PreviewsMacros plugin (#Preview, @Previewable).
// The macro declarations come from the SDK (SwiftUI / UIKit / WidgetKit stubs);
// the compiler type-checks #Preview's arguments - including the body closure -
// against those declarations before expansion, so an empty expansion still
// reports errors inside preview bodies, as Xcode does.

import SwiftSyntax
import SwiftSyntaxMacros

public struct SwiftUIView: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct Common: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct KitViewMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct Previewable: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}
