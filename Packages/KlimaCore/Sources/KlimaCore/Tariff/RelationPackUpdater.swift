import Foundation

/// The cache of the remote relation pack: the verbatim pack file and a small meta file with what the catalogue promised for
/// it, side by side in one directory (the app uses Application Support). Both are written atomically; a pack whose files do
/// not agree, fail validation again at load time or are not newer than the bundled table are deleted and never used.
public struct RelationPackStore: Sendable {
    public static let packFileName = "relations-pack.bin"
    public static let metaFileName = "relations-pack-meta.json"

    public struct Meta: Codable, Hashable, Sendable {
        public var pack: RelationsPackInfo
        public var installedAt: Date

        public init(pack: RelationsPackInfo, installedAt: Date) {
            self.pack = pack
            self.installedAt = installedAt
        }
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    var packURL: URL { directory.appendingPathComponent(Self.packFileName) }
    var metaURL: URL { directory.appendingPathComponent(Self.metaFileName) }

    public func readMeta() -> Meta? {
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Meta.self, from: data)
    }

    /// Writes the pack, then its meta, each atomically (temporary file, then rename).
    public func write(pack data: Data, info: RelationsPackInfo, installedAt: Date) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let meta = try encoder.encode(Meta(pack: info, installedAt: installedAt))
        try data.write(to: packURL, options: .atomic)
        try meta.write(to: metaURL, options: .atomic)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: packURL)
        try? FileManager.default.removeItem(at: metaURL)
    }

    /// The stored pack, checked again as if it had just been downloaded. nil when nothing is stored, and – after deleting
    /// the files – when they do not agree, fail a check or are not newer than the bundled table (`bundledVersion`).
    public func loadValidated(validator: RelationPackValidator, reference: RelationPackValidator.Reference,
                              bundledVersion: Int) -> RelationPack? {
        let hasPack = FileManager.default.fileExists(atPath: packURL.path)
        let meta = readMeta()
        guard hasPack || meta != nil else { return nil }
        guard let meta, let data = try? Data(contentsOf: packURL),
              let pack = try? validator.validate(data, expected: meta.pack, reference: reference),
              pack.version > bundledVersion else {
            remove()
            return nil
        }
        return pack
    }
}

/// One refresh of the relation pack: decides whether to fetch, fetches, validates and installs – or leaves everything as it
/// is. The download itself comes in as a function (URLSession in the app, a stub in the tests), so the whole decision chain
/// runs on Linux. Never talks to anything but the URL the catalogue names, resolved against the tariffs document.
public struct RelationPackUpdater: Sendable {
    /// Downloads at most `maxBytes` bytes from `url`; throws on any network or HTTP failure.
    public typealias Fetch = @Sendable (_ url: URL, _ maxBytes: Int) async throws -> Data

    /// At most one download attempt per 24 hours (unless forced).
    public static let minInterval: TimeInterval = 24 * 3600

    public enum Outcome: Equatable, Sendable {
        /// The catalogue has no `relationsPack` block.
        case unavailable
        /// The pack is not newer than the table in use.
        case notNewer
        /// The last attempt was less than 24 hours ago.
        case throttled
        /// The URL is not `https`, or not on the owner's host.
        case blockedURL
        /// Downloaded, valid, written: from now on the table of this version is available.
        case installed(version: Int)
        /// Downloaded but not accepted: the table in use stays.
        case rejected(RelationPackError)
        /// No network, or the server did not answer with the file: the table in use stays.
        case unreachable
    }

    public struct Result: Equatable, Sendable {
        public var outcome: Outcome
        /// A download was tried (the caller records `now` as the last attempt, whatever came of it).
        public var attempted: Bool
    }

    public let store: RelationPackStore
    public let validator: RelationPackValidator

    public init(store: RelationPackStore, validator: RelationPackValidator) {
        self.store = store
        self.validator = validator
    }

    /// - Parameters:
    ///   - info: the catalogue's `relationsPack` block.
    ///   - tariffsURL: where the tariffs document comes from; a relative pack URL resolves against it.
    ///   - versionInUse: data version of the table in use (bundled or installed pack, whichever is higher).
    ///   - reference: the table in use, for the plausibility checks.
    ///   - lastAttempt: when a download was last tried (nil = never).
    ///   - force: "Jetzt prüfen" – ignores the 24 hour limit (never the version check).
    public func refresh(info: RelationsPackInfo?, tariffsURL: URL?, versionInUse: Int, reference: RelationPackValidator.Reference,
                        lastAttempt: Date?, now: Date, force: Bool, fetch: Fetch) async -> Result {
        guard let info else { return Result(outcome: .unavailable, attempted: false) }
        guard info.version > versionInUse else { return Result(outcome: .notNewer, attempted: false) }
        if !force, let last = lastAttempt {
            let elapsed = now.timeIntervalSince(last)
            if elapsed >= 0, elapsed < Self.minInterval { return Result(outcome: .throttled, attempted: false) }
        }
        guard let url = info.resolvedURL(relativeTo: tariffsURL) else { return Result(outcome: .blockedURL, attempted: false) }
        guard info.bytes > 0, info.bytes <= RelationPack.maxBytes else {
            return Result(outcome: .rejected(.tooLarge), attempted: false)
        }
        let data: Data
        do {
            data = try await fetch(url, RelationPack.maxBytes)
        } catch let error as RelationPackError {
            return Result(outcome: .rejected(error), attempted: true)
        } catch {
            return Result(outcome: .unreachable, attempted: true)
        }
        do {
            let pack = try validator.validate(data, expected: info, reference: reference)
            try store.write(pack: data, info: info, installedAt: now)
            return Result(outcome: .installed(version: pack.version), attempted: true)
        } catch let error as RelationPackError {
            return Result(outcome: .rejected(error), attempted: true)
        } catch {
            return Result(outcome: .rejected(.corrupt("write")), attempted: true)
        }
    }
}
