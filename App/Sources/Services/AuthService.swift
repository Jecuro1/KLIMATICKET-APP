import Foundation
import SwiftUI
import AuthenticationServices

enum AuthProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple, google, microsoft, local

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .microsoft: "Microsoft"
        case .local: "Lokal"
        }
    }

    /// Supabase provider identifier.
    var supabaseProvider: String {
        switch self {
        case .apple: "apple"
        case .google: "google"
        case .microsoft: "azure"
        case .local: ""
        }
    }
}

struct UserProfile: Codable, Equatable, Sendable {
    var id: String
    var displayName: String
    var email: String?
    var provider: AuthProvider
    var avatarURL: String?
    /// True when backed by a cloud session (sync available).
    var isCloud: Bool

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "🙂" : letters.uppercased()
    }
}

/// Handles sign-in with Apple, Google and Microsoft.
/// • With Supabase configured: real accounts + cloud sync (Apple natively via ID token, Google/Microsoft via PKCE web flow).
/// • Without Supabase: Sign in with Apple still works locally (name/e-mail stay on device); Google/Microsoft explain the setup.
@Observable
@MainActor
final class AuthService {
    enum Phase: Equatable {
        case signedOut
        case signingIn(AuthProvider)
        case signedIn
    }

    private(set) var phase: Phase = .signedOut
    private(set) var profile: UserProfile?
    var lastError: String?

    private let client: SupabaseClient?
    private(set) var session: SupabaseSession?
    private var currentNonce: String?

    private static let profileKey = "auth.profile"
    private static let sessionKey = "auth.session"

    init(config: AppConfig) {
        if let url = config.supabase {
            client = SupabaseClient(baseURL: url, anonKey: config.supabaseAnonKey)
        } else {
            client = nil
        }
        if let data = Keychain.data(for: Self.sessionKey), let s = try? JSONDecoder().decode(SupabaseSession.self, from: data) {
            session = s
        }
        if let data = Keychain.data(for: Self.profileKey), let p = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = p
            phase = .signedIn
        }
    }

    var isCloudAvailable: Bool { client != nil }
    var isSignedIn: Bool { phase == .signedIn }

    // MARK: Apple

    /// Configures the request of a `SignInWithAppleButton`.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = PKCE.randomURLSafe(byteCount: 32)
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = PKCE.sha256Hex(nonce)
    }

    /// Completion handler of a `SignInWithAppleButton`.
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            lastError = "Anmeldung mit Apple fehlgeschlagen. \(error.localizedDescription)"
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            phase = .signingIn(.apple)
            let formatter = PersonNameComponentsFormatter()
            let name = credential.fullName.map { formatter.string(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
            if let client, let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8) {
                do {
                    let s = try await client.signInWithIdToken(provider: "apple", idToken: token, nonce: currentNonce)
                    complete(with: s, provider: .apple, fallbackName: name)
                } catch {
                    lastError = error.localizedDescription
                    phase = profile == nil ? .signedOut : .signedIn
                }
            } else {
                // Local-only Apple identity.
                let p = UserProfile(id: credential.user, displayName: name ?? profile?.displayName ?? "Apple-Konto",
                                    email: credential.email ?? profile?.email, provider: .apple, avatarURL: nil, isCloud: false)
                store(profile: p)
            }
        }
    }

    // MARK: Google & Microsoft (PKCE web flow)

    func signIn(with provider: AuthProvider, using webSession: WebAuthenticationSession) async {
        guard provider == .google || provider == .microsoft || provider == .apple else { return }
        guard let client else {
            lastError = "Die Anmeldung mit \(provider.displayName) braucht ein Cloud-Konto. Richte Supabase ein (siehe Einstellungen › Konto › Einrichtung) oder nutze „Mit Apple anmelden“ bzw. „Ohne Konto fortfahren“."
            return
        }
        phase = .signingIn(provider)
        let verifier = PKCE.makeVerifier()
        let url = client.authorizeURL(provider: provider.supabaseProvider, redirectTo: AppConfig.authCallback,
                                      codeChallenge: PKCE.challenge(for: verifier),
                                      scopes: provider == .microsoft ? "email openid profile" : nil)
        do {
            let callback = try await webSession.authenticate(using: url, callbackURLScheme: AppConfig.urlScheme,
                                                             preferredBrowserSession: .ephemeral)
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else { throw SupabaseError.missingCode }
            let s = try await client.exchangeCode(code, codeVerifier: verifier)
            complete(with: s, provider: provider, fallbackName: nil)
        } catch {
            if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                phase = profile == nil ? .signedOut : .signedIn
                return
            }
            lastError = error.localizedDescription
            phase = profile == nil ? .signedOut : .signedIn
        }
    }

    // MARK: Local

    func continueWithoutAccount(name: String = "") {
        let p = UserProfile(id: UUID().uuidString, displayName: name.isEmpty ? "Du" : name, email: nil,
                            provider: .local, avatarURL: nil, isCloud: false)
        store(profile: p)
    }

    func updateDisplayName(_ name: String) {
        guard var p = profile, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        p.displayName = name
        store(profile: p)
    }

    func signOut() async {
        if let client, let session { await client.signOut(session) }
        session = nil
        profile = nil
        Keychain.set(nil, for: Self.sessionKey)
        Keychain.set(nil, for: Self.profileKey)
        phase = .signedOut
    }

    // MARK: Session

    /// Returns a valid session (refreshing if needed) or nil when not signed in to the cloud.
    func validSession() async -> SupabaseSession? {
        guard let client, let current = session else { return nil }
        guard current.isExpired else { return current }
        do {
            let refreshed = try await client.refresh(current)
            persist(session: refreshed)
            return refreshed
        } catch {
            return nil
        }
    }

    private func complete(with s: SupabaseSession, provider: AuthProvider, fallbackName: String?) {
        persist(session: s)
        let name = s.user.fullName ?? fallbackName ?? s.user.email?.components(separatedBy: "@").first?.capitalized ?? provider.displayName
        let p = UserProfile(id: s.user.id, displayName: name, email: s.user.email, provider: provider,
                            avatarURL: s.user.avatarURL, isCloud: true)
        store(profile: p)
    }

    private func persist(session s: SupabaseSession) {
        session = s
        Keychain.set(try? JSONEncoder().encode(s), for: Self.sessionKey)
    }

    private func store(profile p: UserProfile) {
        profile = p
        Keychain.set(try? JSONEncoder().encode(p), for: Self.profileKey)
        phase = .signedIn
        lastError = nil
    }
}
