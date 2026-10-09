import Foundation
import SwiftUI
import UIKit
import AuthenticationServices
import KlimaCloud

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

    /// Provider identifier of the KlimaBilanz API (`/v1/auth/{provider}/…`, `user.provider`).
    var apiProvider: String {
        switch self {
        case .apple: "apple"
        case .google: "google"
        case .microsoft: "microsoft"
        case .local: ""
        }
    }

    init?(apiProvider: String?) {
        switch apiProvider {
        case "apple": self = .apple
        case "google": self = .google
        case "microsoft": self = .microsoft
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

/// Handles sign-in with Apple, Google and Microsoft against the KlimaBilanz Cloudflare Worker
/// (contract: docs/CLOUDFLARE_BACKEND.md §2, §6).
/// • With `apiBaseURL` configured: real accounts + cloud sync. Google, Microsoft and Apple (sideloaded builds) sign
///   in through the Worker in `ASWebAuthenticationSession` (code + PKCE + state); signed builds use native Sign in
///   with Apple (`/v1/auth/apple/native`). The buttons follow the providers the server has enabled (`/v1/config`).
/// • Without a cloud: Sign in with Apple still works locally (name/e-mail stay on device); Google/Microsoft explain the setup.
///
/// Session handling lives in `SessionCoordinator`: refresh tokens are single use and rotate, so there is one in-flight
/// refresh shared by all callers. The session lives in the Keychain "after first unlock, this device only", so
/// background sync works and tokens never travel to another device via backups. Sign-out ends only this device's session.
///
/// The stored session and profile are read off the main thread at launch (`SecItem…` calls block on IPC with securityd)
/// and published on the main actor a moment later (`isLoaded`); every async entry point waits for that read first.
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
    /// The cloud session is gone (refresh token expired or revoked, account deleted on another device, the app was
    /// restored onto a new iPhone, or the session dates from the retired Supabase backend). The profile is kept as a
    /// local one (`isCloud == false`), so "Mit Konto verbinden" appears again; signing in with the same account resumes sync.
    private(set) var needsReauthentication = false
    /// True while `deleteAccount()` runs.
    private(set) var isDeletingAccount = false
    /// The current cloud session (mirrors `SessionCoordinator.session`).
    private(set) var session: CloudSession?
    /// The server's `/v1/config` (providers, minimum app version); cached across launches. nil = not known yet.
    private(set) var serverConfig: CloudConfig?
    /// The stored session and profile have been read from the Keychain (shortly after launch). Until then the service
    /// looks signed out; views that decide something once from the sign-in state wait for this.
    private(set) var isLoaded = false

    private let client: CloudAPIClient?
    private let coordinator: SessionCoordinator?
    private let keychain = KeychainStore()
    @ObservationIgnored private var currentNonce: String?
    /// The Keychain could not be read yet (launched in the background before the first unlock after a reboot).
    @ObservationIgnored private var keychainWasLocked = false
    @ObservationIgnored private var legacySessionNeedsDeleting = false
    @ObservationIgnored private var protectedDataObserver: NSObjectProtocol?
    @ObservationIgnored private var configFetchedAt: Date?
    @ObservationIgnored private var configTask: Task<Void, Never>?
    /// The running Keychain read (launch, or again once protected data became available).
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Set by every local account change; a Keychain read that finishes afterwards must not overwrite it.
    @ObservationIgnored private var accountChangedDuringLoad = false

    private nonisolated static let profileKey = "auth.profile"
    /// Cloudflare-era session (`CloudSession`), device-only.
    private nonisolated static let sessionKey = "auth.session.cf1"
    /// The Supabase-era session: unusable with the new backend, deleted at launch.
    private nonisolated static let legacySessionKey = "auth.session"
    private static let configCacheKey = "cloud.config"

    init(config: AppConfig) {
        let client = config.cloudClient
        self.client = client
        if let client {
            coordinator = SessionCoordinator(store: KeychainStore(), key: Self.sessionKey) { try await client.refresh($0) }
        } else {
            coordinator = nil
        }
        serverConfig = Self.cachedConfig()
        coordinator?.onChange = { [weak self] session in self?.session = session }
        coordinator?.onRejected = { [weak self] _, _ in self?.sessionWasRejected() }
        legacySessionNeedsDeleting = true
        loadStoredAccount(readAccount: true)
        protectedDataObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.protectedDataDidBecomeAvailable() }
        }
        if client != nil, !LaunchMode.isScreenshot {
            Task { await self.refreshServerConfig(force: true) }
        }
    }

    var isCloudAvailable: Bool { client != nil }
    var isSignedIn: Bool { phase == .signedIn }

    // MARK: Server config

    /// Whether the server offers `provider` (`native`: native Sign in with Apple). True while the config is unknown,
    /// so a fresh install shows every button until `/v1/config` answered.
    func isProviderEnabled(_ provider: AuthProvider, native: Bool = false) -> Bool {
        guard let config = serverConfig else { return true }
        switch provider {
        case .google: return config.googleWeb
        case .microsoft: return config.microsoftWeb
        case .apple: return native ? config.appleNative : config.appleWeb
        case .local: return true
        }
    }

    /// The cloud is set up, but the server enables no way to sign in (yet).
    var serverHasNoProviders: Bool {
        guard isCloudAvailable, let serverConfig else { return false }
        return !serverConfig.hasAnyProvider(native: AppConfig.supportsNativeAppleSignIn)
    }

    /// Fetches `/v1/config` (at most once a minute unless forced). Failures keep the cached answer.
    func refreshServerConfig(force: Bool = false) async {
        guard let client else { return }
        if let running = configTask { await running.value; return }
        if !force, let fetched = configFetchedAt, Date().timeIntervalSince(fetched) < 60 { return }
        let task = Task { @MainActor in
            defer { self.configTask = nil }
            guard let config = try? await client.fetchConfig() else { return }
            self.configFetchedAt = Date()
            if self.serverConfig != config { self.serverConfig = config }
            if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: Self.configCacheKey) }
        }
        configTask = task
        await task.value
    }

    private static func cachedConfig() -> CloudConfig? {
        guard let data = UserDefaults.standard.data(forKey: configCacheKey) else { return nil }
        return try? JSONDecoder().decode(CloudConfig.self, from: data)
    }

    // MARK: Apple (native, signed builds)

    /// Configures the request of a `SignInWithAppleButton`.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = PKCE.randomURLSafe(byteCount: 32)
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = PKCE.sha256Hex(nonce)   // Apple gets the hash, the Worker the raw nonce
    }

    /// Completion handler of a `SignInWithAppleButton`.
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        await waitUntilLoaded()
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
                guard let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8),
                      let nonce else {
                    lastError = "Apple hat kein gültiges Anmelde-Token geliefert. Bitte versuch es noch einmal."
                    return
                }
                let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
                phase = .signingIn(.apple)
                do {
                    // The server keeps the name Apple sends only on the very first authorization.
                    let s = try await client.signInWithApple(identityToken: token, rawNonce: nonce,
                                                             authorizationCode: code, fullName: name)
                    complete(with: s, provider: .apple, fallbackName: name)
                } catch {
                    lastError = CloudError.userMessage(for: error, providerName: AuthProvider.apple.displayName)
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

    // MARK: Browser sign-in (Google, Microsoft, Apple in sideloaded builds)

    func signIn(with provider: AuthProvider, using webSession: WebAuthenticationSession) async {
        guard provider == .google || provider == .microsoft || provider == .apple else { return }
        await waitUntilLoaded()
        guard let client else {
            lastError = "Die Anmeldung mit \(provider.displayName) braucht ein Cloud-Konto. Richte das Cloudflare-Backend ein (siehe Einstellungen › Konto › Cloud-Sync einrichten) oder nutze „Mit Apple anmelden“ bzw. „Ohne Konto fortfahren“."
            return
        }
        phase = .signingIn(provider)
        Task { await refreshServerConfig() }
        let verifier = PKCE.makeVerifier()
        let state = PKCE.randomURLSafe(byteCount: 24)
        let url = client.authorizeURL(provider: provider.apiProvider, codeChallenge: PKCE.challenge(for: verifier),
                                      state: state, redirectURI: AppConfig.authCallback)
        do {
            let callback = try await webSession.authenticate(using: url, callbackURLScheme: AppConfig.urlScheme,
                                                             preferredBrowserSession: .ephemeral)
            let code = try WebAuthCallback.parse(callback, expectedState: state).get()
            let s = try await client.exchangeCode(code, codeVerifier: verifier, redirectURI: AppConfig.authCallback)
            complete(with: s, provider: provider, fallbackName: nil)
        } catch {
            if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                restorePhase()
                return
            }
            if (error as? CloudError) == .cancelled {
                restorePhase()
                return
            }
            if let e = error as? CloudError, e.code == "provider_disabled" {
                Task { await refreshServerConfig(force: true) }   // hide the button
            }
            lastError = CloudError.userMessage(for: error, providerName: provider.displayName)
            restorePhase()
        }
    }

    // MARK: Local

    func continueWithoutAccount(name: String = "") {
        let p = UserProfile(id: UUID().uuidString, displayName: name.isEmpty ? "Du" : name, email: nil,
                            provider: .local, avatarURL: nil, isCloud: false)
        store(profile: p)
    }

    /// Renames the profile; for a cloud account also on the server (`PATCH /v1/me`, fire and forget), so other
    /// devices get the name on their next sign-in.
    func updateDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var p = profile, !trimmed.isEmpty else { return }
        p.displayName = name
        store(profile: p)
        guard p.isCloud, let client, let userID = session?.user.id else { return }
        let provider = sessionProvider(userID: userID)
        Task { _ = try? await CloudAPIClient.withSession(provider) { try await client.updateDisplayName(trimmed, session: $0) } }
    }

    /// Signs out on this device only (`/v1/auth/logout` revokes this session); other devices of the account stay
    /// signed in. Local data stays on the device and remains linked to the account (see `SyncService.pendingAccountSwitch`).
    func signOut() async {
        await waitUntilLoaded()
        await coordinator?.waitForPendingRefresh()   // never race a token rotation
        let current = session
        clearLocalAccount()
        guard let client, let current else { return }
        // The refresh token identifies the session even when the access token has expired.
        await client.logout(current)
    }

    /// In-app account deletion (App Store guideline 5.1.1(v)): `POST /v1/account/delete` removes the account, every
    /// cloud row and every session (other devices fall back to a local profile). Then clears the local session and
    /// forgets the sync owner. Data on this iPhone stays. Throws when offline, signed out or unsupported by the server.
    func deleteAccount() async throws {
        guard let client else { throw CloudError.notConfigured }
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        guard let s = await validSession() else { throw CloudFailure(CloudError.sessionExpired.message(providerName: nil)) }
        let userID = s.user.id
        do {
            try await CloudAPIClient.withSession(sessionProvider(userID: userID)) { try await client.deleteAccount(session: $0) }
        } catch let error as CloudError where error.status == 404 {
            throw CloudFailure("Die Kontolöschung wird vom Server nicht unterstützt – bitte das Backend aktualisieren.")
        } catch {
            throw CloudFailure(CloudError.userMessage(for: error))
        }
        // The server already revoked every session of this user: only clear the local state.
        clearLocalAccount()
        SyncOwnerStore.forget(userID: userID)
    }

    // MARK: Session

    /// Returns a valid session (refreshing if needed) or nil when not signed in to the cloud.
    /// Concurrent callers share one refresh – refresh tokens are single use.
    func validSession(forceRefresh: Bool = false) async -> CloudSession? {
        await waitUntilLoaded()
        return await coordinator?.validSession(forceRefresh: forceRefresh)
    }

    /// After the server answered 401 for `rejected`: the newer session if another caller already refreshed,
    /// otherwise a forced refresh.
    func refreshedSession(after rejected: CloudSession) async -> CloudSession? {
        await waitUntilLoaded()
        return await coordinator?.refreshedSession(after: rejected)
    }

    /// Returns once the stored session and profile have been read (immediately after the launch read).
    func waitUntilLoaded() async {
        if let loadTask { await loadTask.value }
    }

    /// Session supplier for `CloudAPIClient.withSession` that refuses to switch accounts mid-operation.
    private func sessionProvider(userID: String) -> SessionProvider {
        { [weak self] rejected in
            guard let self else { throw CloudError.sessionExpired }
            let next: CloudSession?
            if let rejected {
                next = await self.refreshedSession(after: rejected)
            } else {
                next = await self.validSession()
            }
            guard let next, next.user.id == userID else { throw CloudError.sessionExpired }
            return next
        }
    }

    private func complete(with s: CloudSession, provider: AuthProvider, fallbackName: String?) {
        if let old = session, old.refreshToken != s.refreshToken, let client {
            // Signed in again without signing out first: end the previous session on this device.
            Task { await client.logout(old) }
        }
        needsReauthentication = false
        coordinator?.replace(with: s)
        let name = s.user.displayName ?? fallbackName ?? s.user.email?.components(separatedBy: "@").first?.capitalized
            ?? provider.displayName
        let p = UserProfile(id: s.user.id, displayName: name, email: s.user.email,
                            provider: AuthProvider(apiProvider: s.user.provider) ?? provider,
                            avatarURL: s.user.avatarURL, isCloud: true)
        store(profile: p)
    }

    /// The refresh token is dead (the coordinator already cleared the session): keep the identity as a local profile
    /// so the UI offers signing in again.
    private func sessionWasRejected() {
        if var p = profile, p.isCloud {
            p.isCloud = false
            store(profile: p)
        }
        needsReauthentication = true
        lastError = CloudError.sessionExpired.message(providerName: nil)
    }

    private func clearLocalAccount() {
        accountChangedDuringLoad = true
        coordinator?.replace(with: nil)
        profile = nil
        currentNonce = nil
        needsReauthentication = false
        Keychain.set(nil, for: Self.profileKey)
        phase = .signedOut
    }

    private func restorePhase() {
        phase = profile == nil ? .signedOut : .signedIn
    }

    private func store(profile p: UserProfile) {
        accountChangedDuringLoad = true
        profile = p
        if let data = try? JSONEncoder().encode(p) {
            keychain.write(data, key: Self.profileKey, thisDeviceOnly: false)
        }
        phase = .signedIn
        lastError = nil
    }

    // MARK: Keychain

    /// What the Keychain holds for this app (read off the main thread).
    private struct StoredAccount: Sendable {
        /// nil when there is no cloud (no session is read then).
        var session: SecureReadResult?
        /// nil when only the legacy session was deleted (no account read).
        var profile: SecureReadResult?
        var legacySessionDeleted: Bool?
    }

    /// Reads (and, where pending, deletes the Supabase-era session) on a background thread, then applies the result
    /// on the main actor. `readAccount: false` only retries the legacy delete.
    private func loadStoredAccount(readAccount: Bool) {
        let includeSession = coordinator != nil
        let deleteLegacy = legacySessionNeedsDeleting
        guard readAccount || deleteLegacy else { return }
        let previous = loadTask
        loadTask = Task { @MainActor in
            await previous?.value
            if readAccount { self.accountChangedDuringLoad = false }
            let stored = await Task.detached(priority: .userInitiated) {
                Self.readStoredAccount(includeSession: includeSession, readAccount: readAccount, deleteLegacy: deleteLegacy)
            }.value
            self.apply(stored)
        }
    }

    private nonisolated static func readStoredAccount(includeSession: Bool, readAccount: Bool, deleteLegacy: Bool) -> StoredAccount {
        let keychain = KeychainStore()
        var stored = StoredAccount()
        if deleteLegacy { stored.legacySessionDeleted = keychain.delete(legacySessionKey) }
        if readAccount {
            if includeSession { stored.session = keychain.read(sessionKey) }
            stored.profile = keychain.read(profileKey)
        }
        return stored
    }

    private func apply(_ stored: StoredAccount) {
        LaunchTrace.mark("auth.loaded")
        if let deleted = stored.legacySessionDeleted { legacySessionNeedsDeleting = !deleted }
        guard let profileRead = stored.profile else { return }
        defer { isLoaded = true }
        // Signed in, out or renamed while the Keychain was being read: that newer state wins (and is already stored).
        guard !accountChangedDuringLoad else {
            keychainWasLocked = false
            return
        }
        var locked = false
        if let sessionRead = stored.session, case .locked = coordinator?.load(from: sessionRead) { locked = true }
        switch profileRead {
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

    /// Keeps profile and session consistent after launch (missing profile, restored backup without session,
    /// a profile from the Supabase era, …).
    private func reconcileProfileWithSession() {
        guard client != nil else { return }
        if let s = session {
            guard profile?.id != s.user.id || profile?.isCloud != true else { return }
            // The profile write after sign-in did not make it: rebuild it from the session.
            let p = UserProfile(id: s.user.id, displayName: s.user.displayName ?? s.user.email ?? "Konto", email: s.user.email,
                                provider: AuthProvider(apiProvider: s.user.provider) ?? profile?.provider ?? .google,
                                avatarURL: s.user.avatarURL, isCloud: true)
            store(profile: p)
        } else if var p = profile, p.isCloud {
            // Cloud profile without session (restored onto a new iPhone – sessions never leave the device – or signed
            // in with the retired Supabase backend): keep it locally and offer signing in again.
            p.isCloud = false
            store(profile: p)
            needsReauthentication = true
        }
    }

    private func protectedDataDidBecomeAvailable() {
        var reload = false
        if keychainWasLocked {
            keychainWasLocked = false
            reload = session == nil && profile == nil
        }
        loadStoredAccount(readAccount: reload)   // also retries a pending legacy delete
        coordinator?.saveIfNeeded()
    }
}
