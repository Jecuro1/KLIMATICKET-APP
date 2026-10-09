import Foundation
import SwiftUI
import UIKit
import Security
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

    init?(supabaseProvider: String?) {
        switch supabaseProvider {
        case "apple": self = .apple
        case "google": self = .google
        case "azure": self = .microsoft
        default: return nil
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
///
/// Session handling: refresh tokens are single use, so refreshes are serialized (one in-flight refresh shared by all
/// callers). The session lives in the Keychain "after first unlock, this device only", so background sync works and
/// tokens never travel to another device via backups. Sign-out ends only this device's session.
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
    /// The cloud session is gone (refresh token expired or revoked, account deleted on another device, or the app was
    /// restored onto a new iPhone). The profile is kept as a local one (`isCloud == false`), so "Mit Konto verbinden"
    /// appears again; signing in with the same account resumes sync.
    private(set) var needsReauthentication = false
    /// True while `deleteAccount()` runs.
    private(set) var isDeletingAccount = false

    private let client: SupabaseClient?
    private(set) var session: SupabaseSession?
    private var currentNonce: String?
    /// The one in-flight refresh (refresh tokens are single use).
    @ObservationIgnored private var refreshTask: (id: UUID, task: Task<SupabaseSession, Error>)?
    /// The Keychain could not be read yet (launched in the background before the first unlock after a reboot).
    @ObservationIgnored private var keychainWasLocked = false
    /// The latest session could not be written to the Keychain yet.
    @ObservationIgnored private var sessionNeedsSaving = false
    @ObservationIgnored private var protectedDataObserver: NSObjectProtocol?

    private static let profileKey = "auth.profile"
    private static let sessionKey = "auth.session"

    init(config: AppConfig) {
        if let url = config.supabase {
            client = SupabaseClient(baseURL: url, anonKey: config.supabaseAnonKey)
        } else {
            client = nil
        }
        loadFromKeychain()
        protectedDataObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.protectedDataDidBecomeAvailable() }
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
        request.nonce = PKCE.sha256Hex(nonce)   // Apple gets the hash, Supabase the raw nonce
    }

    /// Completion handler of a `SignInWithAppleButton`.
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        let nonce = currentNonce
        currentNonce = nil
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            lastError = "Anmeldung mit Apple fehlgeschlagen. \(error.localizedDescription)"
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            let formatter = PersonNameComponentsFormatter()
            let name = credential.fullName.map { formatter.string(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
            if let client {
                guard let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
                    lastError = "Apple hat kein gültiges Anmelde-Token geliefert. Bitte versuch es noch einmal."
                    return
                }
                phase = .signingIn(.apple)
                do {
                    let s = try await client.signInWithIdToken(provider: "apple", idToken: token, nonce: nonce)
                    complete(with: s, provider: .apple, fallbackName: name)
                    // Apple sends the name only on the very first authorization – keep it in the account for other devices.
                    if let name, s.user.fullName == nil {
                        Task { try? await client.updateUserMetadata(["full_name": name], session: s) }
                    }
                } catch {
                    lastError = error.localizedDescription
                    restorePhase()
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
            let parameters = Self.callbackParameters(callback)
            guard let code = parameters["code"], !code.isEmpty else {
                if let message = parameters["error_description"] ?? parameters["error"] {
                    throw SupabaseError.authorization(message)
                }
                throw SupabaseError.missingCode
            }
            let s = try await client.exchangeCode(code, codeVerifier: verifier)
            complete(with: s, provider: provider, fallbackName: nil)
        } catch {
            if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                restorePhase()
                return
            }
            lastError = error.localizedDescription
            restorePhase()
        }
    }

    /// Query and fragment parameters of the OAuth redirect (GoTrue reports errors in either).
    static func callbackParameters(_ url: URL) -> [String: String] {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        var items = comps.queryItems ?? []
        if let fragment = comps.percentEncodedFragment, !fragment.isEmpty {
            var fragmentComps = URLComponents()
            fragmentComps.percentEncodedQuery = fragment
            items += fragmentComps.queryItems ?? []
        }
        var result: [String: String] = [:]
        for item in items where result[item.name] == nil {
            if let value = item.value { result[item.name] = value.replacingOccurrences(of: "+", with: " ") }
        }
        return result
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

    /// Signs out on this device only (`/logout?scope=local`); other devices of the account stay signed in.
    /// Local data stays on the device and remains linked to the account (see `SyncService.pendingAccountSwitch`).
    func signOut() async {
        if let pending = refreshTask?.task { _ = try? await pending.value }   // never race a refresh
        let current = session
        clearLocalAccount()
        guard let client, var current else { return }
        // The logout endpoint needs a valid access token to revoke the session's refresh token.
        if current.isExpired, let refreshed = try? await client.refresh(current) { current = refreshed }
        await client.signOut(current, scope: "local")
    }

    /// In-app account deletion (App Store guideline 5.1.1(v)): the Edge Function `delete-account` deletes the auth user,
    /// which cascades to all of the account's rows and sessions. Then signs out locally and forgets the sync owner.
    /// Data on this iPhone stays. Throws when offline, signed out or when the function is not deployed.
    func deleteAccount() async throws {
        guard let client else { throw SupabaseError.notConfigured }
        guard !isDeletingAccount else { return }
        guard let s = await validSession() else { throw SupabaseError.sessionExpired }
        let userID = s.user.id
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        // Same 401 handling as sync: the device may consider a token valid that the server already rejects.
        let provider: SupabaseClient.SessionProvider = { [weak self] rejected in
            guard let self else { throw SupabaseError.sessionExpired }
            let next: SupabaseSession?
            if let rejected {
                next = await self.refreshedSession(after: rejected)
            } else {
                next = await self.validSession()
            }
            guard let next, next.user.id == userID else { throw SupabaseError.sessionExpired }
            return next
        }
        do {
            _ = try await SupabaseClient.withSession(provider) { try await client.invokeFunction("delete-account", session: $0) }
        } catch let error as SupabaseError where error.status == 404 {
            throw SupabaseError.http(404, "Die Kontolöschung ist im Supabase-Projekt noch nicht eingerichtet (Edge Function „delete-account“ fehlt, siehe docs/SETUP.md).")
        }
        // The server already revoked every session of this user: only clear the local state.
        clearLocalAccount()
        SyncOwnerStore.forget(userID: userID)
    }

    // MARK: Session

    /// Returns a valid session (refreshing if needed) or nil when not signed in to the cloud.
    /// Concurrent callers share one refresh – refresh tokens are single use.
    func validSession(forceRefresh: Bool = false) async -> SupabaseSession? {
        guard let client, let current = session else { return nil }
        if !forceRefresh, !current.isExpired { return current }
        let task: Task<SupabaseSession, Error>
        if let running = refreshTask {
            task = running.task
        } else {
            let id = UUID()
            task = Task {
                defer { if self.refreshTask?.id == id { self.refreshTask = nil } }
                do {
                    let refreshed = try await client.refresh(current)
                    // Ignore the result when the user signed out or switched accounts meanwhile.
                    if self.session?.refreshToken == current.refreshToken { self.persist(session: refreshed) }
                    return refreshed
                } catch {
                    if self.session?.refreshToken == current.refreshToken,
                       let error = error as? SupabaseError, error.isDefinitiveAuthFailure {
                        self.sessionWasRejected()
                    }
                    throw error
                }
            }
            refreshTask = (id, task)
        }
        _ = try? await task.value
        guard let latest = session, !latest.isExpired else { return nil }
        return latest
    }

    /// After the server answered 401 for `rejected`: the newer session if another caller already refreshed,
    /// otherwise a forced refresh.
    func refreshedSession(after rejected: SupabaseSession) async -> SupabaseSession? {
        guard let current = session else { return nil }
        if current.accessToken != rejected.accessToken { return await validSession() }
        return await validSession(forceRefresh: true)
    }

    private func complete(with s: SupabaseSession, provider: AuthProvider, fallbackName: String?) {
        if let old = session, old.refreshToken != s.refreshToken, let client {
            // Signed in again without signing out first: end the previous session on this device.
            Task { await client.signOut(old, scope: "local") }
        }
        refreshTask = nil
        needsReauthentication = false
        persist(session: s)
        let name = s.user.fullName ?? fallbackName ?? s.user.email?.components(separatedBy: "@").first?.capitalized ?? provider.displayName
        let p = UserProfile(id: s.user.id, displayName: name, email: s.user.email, provider: provider,
                            avatarURL: s.user.avatarURL, isCloud: true)
        store(profile: p)
    }

    /// The refresh token is dead: keep the identity as a local profile so the UI offers signing in again.
    private func sessionWasRejected() {
        session = nil
        sessionNeedsSaving = false
        Keychain.set(nil, for: Self.sessionKey)
        if var p = profile, p.isCloud {
            p.isCloud = false
            store(profile: p)
        }
        needsReauthentication = true
        lastError = SupabaseError.sessionExpired.localizedDescription
    }

    private func clearLocalAccount() {
        refreshTask = nil
        session = nil
        profile = nil
        currentNonce = nil
        sessionNeedsSaving = false
        needsReauthentication = false
        Keychain.set(nil, for: Self.sessionKey)
        Keychain.set(nil, for: Self.profileKey)
        phase = .signedOut
    }

    private func restorePhase() {
        phase = profile == nil ? .signedOut : .signedIn
    }

    private func persist(session s: SupabaseSession) {
        session = s
        guard let data = try? JSONEncoder().encode(s) else { return }
        // Readable after the first unlock (background sync), never restored onto another device.
        sessionNeedsSaving = !Keychain.set(data, for: Self.sessionKey, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }

    private func store(profile p: UserProfile) {
        profile = p
        if let data = try? JSONEncoder().encode(p) {
            Keychain.set(data, for: Self.profileKey, accessibility: kSecAttrAccessibleAfterFirstUnlock)
        }
        phase = .signedIn
        lastError = nil
    }

    // MARK: Keychain

    private func loadFromKeychain() {
        var locked = false
        switch Keychain.read(Self.sessionKey) {
        case .found(let data):
            session = try? JSONDecoder().decode(SupabaseSession.self, from: data)
        case .locked:
            locked = true
        case .notFound, .failed:
            break
        }
        switch Keychain.read(Self.profileKey) {
        case .found(let data):
            if let p = try? JSONDecoder().decode(UserProfile.self, from: data) {
                profile = p
                phase = .signedIn
            }
        case .locked:
            locked = true
        case .notFound, .failed:
            break
        }
        keychainWasLocked = locked
        if !locked { reconcileProfileWithSession() }
    }

    /// Keeps profile and session consistent after launch (missing profile, restored backup without session, …).
    private func reconcileProfileWithSession() {
        guard client != nil else { return }
        if let s = session {
            guard profile?.id != s.user.id || profile?.isCloud != true else { return }
            // The profile write after sign-in did not make it: rebuild it from the session.
            let p = UserProfile(id: s.user.id, displayName: s.user.fullName ?? s.user.email ?? "Konto", email: s.user.email,
                                provider: AuthProvider(supabaseProvider: s.user.provider) ?? profile?.provider ?? .google,
                                avatarURL: s.user.avatarURL, isCloud: true)
            store(profile: p)
        } else if var p = profile, p.isCloud {
            // Cloud profile without session (e.g. restored onto a new iPhone – sessions never leave the device).
            p.isCloud = false
            store(profile: p)
            needsReauthentication = true
        }
    }

    private func protectedDataDidBecomeAvailable() {
        if keychainWasLocked {
            keychainWasLocked = false
            if session == nil && profile == nil { loadFromKeychain() }
        }
        if sessionNeedsSaving, let session { persist(session: session) }
    }
}
