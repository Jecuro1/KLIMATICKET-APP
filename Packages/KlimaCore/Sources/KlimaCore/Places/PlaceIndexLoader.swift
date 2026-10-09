import Foundation

/// Builds the `PlaceIndex` once, lazily and off the main thread (SUGGEST_SPEC §4.4). Concurrent callers share one
/// build; `current` never blocks (nil until ready – fall back to `StationIndex` meanwhile).
///
/// ```swift
/// // App launch (after the first frame):
/// PlaceIndexLoader.shared.preload()
/// // Station picker:
/// if let index = PlaceIndexLoader.shared.current { … } else { … StationIndex … }
/// let index = try await PlaceIndexLoader.shared.load()
/// ```
public final class PlaceIndexLoader: @unchecked Sendable {
    public enum State: Sendable {
        case idle, loading, ready, failed(String)
    }

    /// Loader for `places.bin` + `localities.bin` in the main bundle (nil URLs → `load()` throws).
    public static let shared = PlaceIndexLoader(bundle: .main)

    public let placesURL: URL?
    public let localitiesURL: URL?
    private let lock = NSLock()
    private var task: Task<PlaceIndex, Error>?
    private var index: PlaceIndex?
    private var failure: String?
    private var observers: [@Sendable (PlaceIndex) -> Void] = []

    public enum LoadError: Error, Equatable { case resourceMissing }

    public init(placesURL: URL?, localitiesURL: URL?) {
        self.placesURL = placesURL
        self.localitiesURL = localitiesURL
    }

    public convenience init(bundle: Bundle) {
        self.init(placesURL: bundle.url(forResource: "places", withExtension: "bin"),
                  localitiesURL: bundle.url(forResource: "localities", withExtension: "bin"))
    }

    /// The index if it is ready (never blocks, never starts a build).
    public var current: PlaceIndex? {
        lock.lock(); defer { lock.unlock() }
        return index
    }

    public var state: State {
        lock.lock(); defer { lock.unlock() }
        if index != nil { return .ready }
        if let failure { return .failed(failure) }
        return task == nil ? .idle : .loading
    }

    /// Calls `body` once the index is ready (immediately if it already is). Use it to attach the index to
    /// `StationIndex` (`stations.attach(places:)`) or to publish readiness to the UI.
    public func whenReady(_ body: @escaping @Sendable (PlaceIndex) -> Void) {
        lock.lock()
        if let index {
            lock.unlock()
            body(index)
            return
        }
        observers.append(body)
        lock.unlock()
    }

    /// Starts the build in the background if it has not started yet.
    public func preload(priority: TaskPriority = .utility) {
        _ = startIfNeeded(priority: priority)
    }

    /// The index, building it on first use (detached, `priority`). Throws if the resources are missing or invalid.
    public func load(priority: TaskPriority = .userInitiated) async throws -> PlaceIndex {
        try await startIfNeeded(priority: priority).value
    }

    private func startIfNeeded(priority: TaskPriority) -> Task<PlaceIndex, Error> {
        lock.lock()
        defer { lock.unlock() }
        if let index { return Task { index } }
        if let task { return task }
        failure = nil
        let places = placesURL, localities = localitiesURL
        let t = Task.detached(priority: priority) { [weak self] () throws -> PlaceIndex in
            do {
                guard let places else { throw LoadError.resourceMissing }
                let built = try PlaceIndex(placesURL: places, localitiesURL: localities)
                self?.finish(built)
                return built
            } catch {
                self?.fail(error)
                throw error
            }
        }
        task = t
        return t
    }

    private func finish(_ built: PlaceIndex) {
        lock.lock()
        index = built
        let obs = observers
        observers = []
        lock.unlock()
        for o in obs { o(built) }
    }

    private func fail(_ error: Error) {
        lock.lock()
        failure = String(describing: error)
        task = nil          // allow a retry
        lock.unlock()
    }
}
