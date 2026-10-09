import Foundation

/// Result of reading a secret.
public enum SecureReadResult: Equatable, Sendable {
    case found(Data)
    case notFound
    /// Protected data is not available yet (background launch before the first unlock after a reboot).
    case locked
    case failed
}

/// Secret storage (the Keychain in the app, `InMemorySecureStore` in tests).
public protocol SecureStore {
    func read(_ key: String) -> SecureReadResult
    /// Writes without deleting first, so a failed write keeps the old value. `thisDeviceOnly` = never restored onto
    /// another device from a backup. Returns false when the store refused (e.g. still locked).
    @discardableResult func write(_ data: Data, key: String, thisDeviceOnly: Bool) -> Bool
    @discardableResult func delete(_ key: String) -> Bool
}

/// In-memory `SecureStore` for tests; `isLocked` simulates a device that was not unlocked yet.
public final class InMemorySecureStore: SecureStore {
    public private(set) var values: [String: Data] = [:]
    public private(set) var deviceOnlyKeys: Set<String> = []
    public var isLocked = false
    public var failWrites = false

    public init(values: [String: Data] = [:]) { self.values = values }

    public func read(_ key: String) -> SecureReadResult {
        if isLocked { return .locked }
        return values[key].map { .found($0) } ?? .notFound
    }

    @discardableResult
    public func write(_ data: Data, key: String, thisDeviceOnly: Bool) -> Bool {
        guard !isLocked, !failWrites else { return false }
        values[key] = data
        if thisDeviceOnly { deviceOnlyKeys.insert(key) } else { deviceOnlyKeys.remove(key) }
        return true
    }

    @discardableResult
    public func delete(_ key: String) -> Bool {
        guard !isLocked else { return false }
        values[key] = nil
        deviceOnlyKeys.remove(key)
        return true
    }
}

/// Owns the current `CloudSession`: persistence, and refresh serialization.
///
/// Refresh tokens are single use, so there is at most one refresh in flight and every caller shares it. A refresh
/// result is dropped when the session changed meanwhile (sign-out, another account). When the server definitively
/// rejects the refresh token (`invalid_grant`), the session is cleared and `onRejected` fires once.
@MainActor
public final class SessionCoordinator {
    public typealias Refresh = @Sendable (CloudSession) async throws -> CloudSession

    public private(set) var session: CloudSession? {
        didSet { if oldValue != session { onChange?(session) } }
    }
    /// The latest session could not be written yet (store locked); retried by `saveIfNeeded()`.
    public private(set) var needsSaving = false
    /// Called whenever `session` changes.
    public var onChange: ((CloudSession?) -> Void)?
    /// Called once when the refresh token of `rejected` was definitively refused; `session` is already nil.
    public var onRejected: ((_ rejected: CloudSession, _ error: CloudError) -> Void)?

    private let store: SecureStore
    private let key: String
    private let refresh: Refresh
    private let now: () -> Date
    private var refreshTask: (id: UUID, task: Task<CloudSession, Error>)?

    public init(store: SecureStore, key: String, now: @escaping () -> Date = { Date() }, refresh: @escaping Refresh) {
        self.store = store
        self.key = key
        self.now = now
        self.refresh = refresh
    }

    public enum LoadResult: Equatable {
        case loaded(CloudSession?)
        case locked
    }

    /// Reads the persisted session (a value that does not decode counts as none).
    @discardableResult
    public func load() -> LoadResult {
        load(from: store.read(key))
    }

    /// Applies what `store.read(key)` returned when the read ran elsewhere – e.g. on a background thread at launch,
    /// because a Keychain read blocks on IPC. Same rules as `load()`.
    @discardableResult
    public func load(from result: SecureReadResult) -> LoadResult {
        switch result {
        case .found(let data):
            session = try? JSONDecoder().decode(CloudSession.self, from: data)
            return .loaded(session)
        case .locked:
            return .locked
        case .notFound, .failed:
            return .loaded(session)
        }
    }

    /// Sign-in (`session`) or local sign-out (`nil`). A refresh that is still running is ignored afterwards.
    public func replace(with session: CloudSession?) {
        refreshTask = nil
        if let session {
            persist(session)
        } else {
            self.session = nil
            needsSaving = false
            store.delete(key)
        }
    }

    /// A valid session (refreshed when the access token expires within 60 s, or when forced), nil when signed out or
    /// the refresh failed. Concurrent callers share one refresh.
    public func validSession(forceRefresh: Bool = false) async -> CloudSession? {
        guard let current = session else { return nil }
        if !forceRefresh, !current.isExpired(at: now()) { return current }
        let task: Task<CloudSession, Error>
        if let running = refreshTask {
            task = running.task
        } else {
            let id = UUID()
            let refresh = self.refresh
            task = Task { @MainActor in
                defer { if self.refreshTask?.id == id { self.refreshTask = nil } }
                do {
                    let refreshed = try await refresh(current)
                    // Ignore the result when the user signed out or switched accounts meanwhile.
                    if self.session?.refreshToken == current.refreshToken { self.persist(refreshed) }
                    return refreshed
                } catch {
                    if self.session?.refreshToken == current.refreshToken,
                       let error = error as? CloudError, error.isDefinitiveAuthFailure {
                        self.reject(current, error)
                    }
                    throw error
                }
            }
            refreshTask = (id, task)
        }
        _ = try? await task.value
        guard let latest = session, !latest.isExpired(at: now()) else { return nil }
        return latest
    }

    /// After the server answered 401 for `rejected`: the newer session if another caller already refreshed,
    /// otherwise a forced refresh.
    public func refreshedSession(after rejected: CloudSession) async -> CloudSession? {
        guard let current = session else { return nil }
        if current.accessToken != rejected.accessToken { return await validSession() }
        return await validSession(forceRefresh: true)
    }

    /// Waits for a running refresh (so sign-out never races a token rotation).
    public func waitForPendingRefresh() async {
        if let task = refreshTask?.task { _ = try? await task.value }
    }

    /// Retries a write that failed while the store was locked.
    public func saveIfNeeded() {
        if needsSaving, let session { persist(session) }
    }

    private func persist(_ s: CloudSession) {
        session = s
        guard let data = try? JSONEncoder().encode(s) else { return }
        needsSaving = !store.write(data, key: key, thisDeviceOnly: true)
    }

    private func reject(_ rejected: CloudSession, _ error: CloudError) {
        session = nil
        needsSaving = false
        store.delete(key)
        onRejected?(rejected, error)
    }
}
