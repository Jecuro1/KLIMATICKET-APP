import Foundation

/// File storage of the local diagnostics in `Application Support/Diagnostics/`:
///
///     events.json                index of incidents (last 30 days, at most `maxEvents`)
///     sessions.json              current session + the last `maxSessions` sessions
///     breadcrumbs.json           breadcrumb ring of the running session (rewritten, coalesced)
///     breadcrumbs-previous.json  … of the session before (what happened right before a crash)
///     hang-inprogress.json       marker of a long hang that is still going on
///     payloads/*.json            raw MetricKit payloads (30 days, at most `maxPayloadBytes`)
///
/// Every file access runs on one serial utility queue, never on the main thread.
final class DiagnosticsStore: @unchecked Sendable {
    static let retention: TimeInterval = 30 * 86_400
    static let maxEvents = 400
    static let maxSessions = 20
    static let maxPayloadBytes = 6 * 1024 * 1024

    let root: URL
    let queue = DispatchQueue(label: "com.knitelarlberg.klimabilanz.diagnostics", qos: .utility)

    private var eventsCache: [DiagnosticsEvent]?
    private var eventsDirty = false
    private var saveScheduled = false

    init(root: URL) {
        self.root = root
    }

    static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    var payloadDirectory: URL { root.appendingPathComponent("payloads", isDirectory: true) }

    func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    // MARK: Coding

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: Generic files (call on `queue`)

    func ensureDirectories() {
        try? FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        // Diagnostics are recreated on the device – keep them out of iCloud/Finder backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var dir = root
        try? dir.setResourceValues(values)
    }

    func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? Self.decoder.decode(type, from: data)
    }

    func write<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? Self.encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(name))
    }

    func move(_ name: String, to target: String) {
        let fm = FileManager.default
        try? fm.removeItem(at: url(target))
        try? fm.moveItem(at: url(name), to: url(target))
    }

    // MARK: Events (call on `queue`)

    func events() -> [DiagnosticsEvent] {
        if let eventsCache { return eventsCache }
        let loaded = read([DiagnosticsEvent].self, from: "events.json") ?? []
        eventsCache = loaded
        return loaded
    }

    /// Adds events (duplicates by id are ignored) and schedules a coalesced save.
    func append(_ new: [DiagnosticsEvent]) {
        guard !new.isEmpty else { return }
        var all = events()
        let known = Set(all.map(\.id))
        let fresh = new.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        all.append(contentsOf: fresh)
        eventsCache = Self.pruned(all, now: Date())
        eventsDirty = true
        scheduleSave()
    }

    static func pruned(_ events: [DiagnosticsEvent], now: Date) -> [DiagnosticsEvent] {
        let cutoff = now.addingTimeInterval(-retention)
        let recent = events.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        return Array(recent.suffix(maxEvents))
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.saveScheduled = false
            self?.saveEventsIfNeeded()
        }
    }

    func saveEventsIfNeeded() {
        guard eventsDirty, let eventsCache else { return }
        eventsDirty = false
        write(eventsCache, to: "events.json")
    }

    // MARK: Payloads (call on `queue`)

    /// Stores a raw MetricKit payload once (file names carry a content hash). Returns false if it existed already.
    @discardableResult
    func storePayload(named name: String, data: Data) -> Bool {
        let target = payloadDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) { return false }
        try? FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        return (try? data.write(to: target, options: .atomic)) != nil
    }

    func payloadFiles() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: payloadDirectory, includingPropertiesForKeys: keys)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Drops payloads older than 30 days, then the oldest until the folder fits `maxPayloadBytes`.
    func prunePayloads(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        var entries: [(url: URL, date: Date, size: Int)] = payloadFiles().map { file in
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return (file, values?.contentModificationDate ?? now, values?.fileSize ?? 0)
        }
        entries.sort { $0.date < $1.date }
        var total = entries.reduce(0) { $0 + $1.size }
        for entry in entries where entry.date < cutoff || total > Self.maxPayloadBytes {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    // MARK: Reset (call on `queue`)

    /// Deletes every stored diagnostic except the running session's file.
    func clearAll() {
        let fm = FileManager.default
        try? fm.removeItem(at: payloadDirectory)
        for name in ["events.json", "breadcrumbs-previous.json", "hang-inprogress.json"] { remove(name) }
        eventsCache = []
        eventsDirty = false
        ensureDirectories()
    }
}

// MARK: - Helpers

enum DiagnosticsHash {
    /// FNV-1a 64-bit – stable file names / ids for identical payloads (not a security hash).
    static func fnv1a(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

enum DiagnosticsTime {
    /// "20261009-143205" – sortable file name stamp (UTC).
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
