// Hand-written stand-in for AuthenticationServices' Objective-C API
// (System/Cryptexes/OS/.../AuthenticationServices.framework/Headers). The SwiftUI
// pieces (SignInWithAppleButton, WebAuthenticationSession, \.webAuthenticationSession)
// come from the generated _AuthenticationServices_SwiftUI overlay. The Swift
// overlay of this framework (passkey / credential-exchange API) is not modelled.

@_exported import Foundation
@_exported import FoundationShim
import UIKit

@inline(never) @usableFromInline func _asStub() -> Never { fatalError("type-check stub") }

public typealias ASPresentationAnchor = UIWindow

public protocol ASAuthorizationCredential: NSObjectProtocol, NSCopying, NSSecureCoding {}
public protocol ASAuthorizationProvider: NSObjectProtocol {}

/// AS_SWIFT_SENDABLE classes get `@unchecked Sendable` (the overlay adds most of these conformances).
open class ASAuthorization: NSObject, @unchecked Sendable {
    /// NS_SWIFT_NAME(ASAuthorization.Scope) NS_TYPED_EXTENSIBLE_ENUM
    public struct Scope: RawRepresentable, Hashable, @unchecked Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static var fullName: Scope { _asStub() }
        public static var email: Scope { _asStub() }
    }
    /// NS_SWIFT_NAME(ASAuthorization.OpenIDOperation) NS_TYPED_EXTENSIBLE_ENUM
    public struct OpenIDOperation: RawRepresentable, Hashable, @unchecked Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static var operationImplicit: OpenIDOperation { _asStub() }
        public static var operationLogin: OpenIDOperation { _asStub() }
        public static var operationRefresh: OpenIDOperation { _asStub() }
        public static var operationLogout: OpenIDOperation { _asStub() }
    }
    open var provider: any ASAuthorizationProvider { _asStub() }
    open var credential: any ASAuthorizationCredential { _asStub() }
}

open class ASAuthorizationRequest: NSObject, NSCopying, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _asStub() }
    public required init?(coder: NSCoder) { _asStub() }
    open func encode(with coder: NSCoder) { _asStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _asStub() }
    open var provider: any ASAuthorizationProvider { _asStub() }
}

open class ASAuthorizationOpenIDRequest: ASAuthorizationRequest, @unchecked Sendable {
    open var requestedScopes: [ASAuthorization.Scope]?
    open var state: String?
    open var nonce: String?
    open var requestedOperation: ASAuthorization.OpenIDOperation = .operationLogin
}

open class ASAuthorizationAppleIDRequest: ASAuthorizationOpenIDRequest, @unchecked Sendable {
    open var user: String?
}

public enum ASUserDetectionStatus: Int, @unchecked Sendable {
    case unsupported = 0, unknown, likelyReal
}

public enum ASUserAgeRange: Int, @unchecked Sendable {
    case unknown = 0, child, notChild
}

open class ASAuthorizationAppleIDCredential: NSObject, ASAuthorizationCredential, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _asStub() }
    public required init?(coder: NSCoder) { _asStub() }
    open func encode(with coder: NSCoder) { _asStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _asStub() }
    open var user: String { _asStub() }
    open var state: String? { _asStub() }
    open var authorizedScopes: [ASAuthorization.Scope] { _asStub() }
    open var authorizationCode: Data? { _asStub() }
    open var identityToken: Data? { _asStub() }
    open var email: String? { _asStub() }
    open var fullName: PersonNameComponents? { _asStub() }
    open var realUserStatus: ASUserDetectionStatus { _asStub() }
    open var userAgeRange: ASUserAgeRange { _asStub() }
}

open class ASPasswordCredential: NSObject, ASAuthorizationCredential, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { _asStub() }
    public required init?(coder: NSCoder) { _asStub() }
    open func encode(with coder: NSCoder) { _asStub() }
    open func copy(with zone: NSZone? = nil) -> Any { _asStub() }
    public init(user: String, password: String) { super.init() }
    open var user: String { _asStub() }
    open var password: String { _asStub() }
}

open class ASAuthorizationAppleIDProvider: NSObject, ASAuthorizationProvider, @unchecked Sendable {
    /// NS_SWIFT_NAME(ASAuthorizationAppleIDProvider.CredentialState)
    public enum CredentialState: Int, @unchecked Sendable {
        case revoked = 0, authorized, notFound, transferred
    }
    public override init() { super.init() }
    open func createRequest() -> ASAuthorizationAppleIDRequest { _asStub() }
    open func getCredentialState(forUserID userID: String, completion: @escaping (ASAuthorizationAppleIDProvider.CredentialState, (any Error)?) -> Void) { _asStub() }
    open func credentialState(forUserID userID: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState { _asStub() }
    nonisolated public class var credentialRevokedNotification: NSNotification.Name { _asStub() }
}

@MainActor @preconcurrency
public protocol ASAuthorizationControllerDelegate: NSObjectProtocol {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization)
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error)
}
extension ASAuthorizationControllerDelegate {
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {}
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {}
}

@MainActor @preconcurrency
public protocol ASAuthorizationControllerPresentationContextProviding: NSObjectProtocol {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor
}

open class ASAuthorizationController: NSObject {
    public struct RequestOptions: OptionSet, @unchecked Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static var preferImmediatelyAvailableCredentials: RequestOptions { .init(rawValue: 1) }
    }
    public init(authorizationRequests: [ASAuthorizationRequest]) { super.init() }
    open var authorizationRequests: [ASAuthorizationRequest] { _asStub() }
    open weak var delegate: (any ASAuthorizationControllerDelegate)?
    open weak var presentationContextProvider: (any ASAuthorizationControllerPresentationContextProviding)?
    open func performRequests() { _asStub() }
    open func performRequests(options: ASAuthorizationController.RequestOptions) { _asStub() }
    open func cancel() { _asStub() }
}

/// ASAuthorizationError.h: NS_ERROR_ENUM(ASAuthorizationErrorDomain, ASAuthorizationErrorCode)
public struct ASAuthorizationError: Error, Hashable, @unchecked Sendable {
    public enum Code: Int, @unchecked Sendable {
        case unknown = 1000, canceled = 1001, invalidResponse = 1002, notHandled = 1003, failed = 1004,
             notInteractive = 1005, matchedExcludedCredential = 1006, credentialImport = 1007,
             credentialExport = 1008, preferSignInWithApple = 1009, deviceNotConfiguredForPasskeyCreation = 1010
    }
    public init(_ code: Code, userInfo: [String: Any] = [:]) { _asStub() }
    public var code: Code { _asStub() }
    public static var errorDomain: String { _asStub() }
    public static var unknown: Code { .unknown }
    public static var canceled: Code { .canceled }
    public static var invalidResponse: Code { .invalidResponse }
    public static var notHandled: Code { .notHandled }
    public static var failed: Code { .failed }
    public static var notInteractive: Code { .notInteractive }
}

// MARK: ASWebAuthenticationSession.h

/// NS_ERROR_ENUM(ASWebAuthenticationSessionErrorDomain, ASWebAuthenticationSessionErrorCode)
public struct ASWebAuthenticationSessionError: Error, Hashable, @unchecked Sendable {
    public enum Code: Int, @unchecked Sendable {
        case canceledLogin = 1, presentationContextNotProvided = 2, presentationContextInvalid = 3
    }
    public init(_ code: Code, userInfo: [String: Any] = [:]) { _asStub() }
    public var code: Code { _asStub() }
    public static var errorDomain: String { _asStub() }
    public static var canceledLogin: Code { .canceledLogin }
    public static var presentationContextNotProvided: Code { .presentationContextNotProvided }
    public static var presentationContextInvalid: Code { .presentationContextInvalid }
}

@MainActor @preconcurrency
public protocol ASWebAuthenticationPresentationContextProviding: NSObjectProtocol {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor
}

open class ASWebAuthenticationSession: NSObject {
    /// typedef void (^ASWebAuthenticationSessionCompletionHandler)(NSURL *_Nullable, NSError *_Nullable)
    /// NS_SWIFT_NAME(ASWebAuthenticationSession.CompletionHandler)
    public typealias CompletionHandler = (URL?, (any Error)?) -> Void

    /// ASWebAuthenticationSessionCallback, NS_SWIFT_NAME(ASWebAuthenticationSession.Callback), AS_SWIFT_SENDABLE
    open class Callback: NSObject, @unchecked Sendable {
        /// + callbackWithCustomScheme: NS_SWIFT_NAME(customScheme(_:))
        open class func customScheme(_ customScheme: String) -> Self { _asStub() }
        /// + callbackWithHTTPSHost:path: NS_SWIFT_NAME(https(host:path:))
        open class func https(host: String, path: String) -> Self { _asStub() }
        open func matchesURL(_ url: URL) -> Bool { _asStub() }
    }

    @available(*, deprecated, message: "Use initWithURL:callback:completionHandler: instead")
    public init(url URL: URL, callbackURLScheme: String?, completionHandler: @escaping ASWebAuthenticationSession.CompletionHandler) { super.init() }
    public init(url URL: URL, callback: ASWebAuthenticationSession.Callback, completionHandler: @escaping ASWebAuthenticationSession.CompletionHandler) { super.init() }
    open weak var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)?
    open var prefersEphemeralWebBrowserSession: Bool = false
    open var additionalHeaderFields: [String: String]?
    open var canStart: Bool { _asStub() }
    open func start() -> Bool { _asStub() }
    open func cancel() { _asStub() }
}
