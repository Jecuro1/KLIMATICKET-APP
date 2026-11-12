import Foundation
import KlimaCore

// Where the trip detection keeps what it must keep (docs/TRIP_DETECTION.md §6): two small JSON files in Application Support
// (not the App Group: no widget reads them), excluded from backups, readable after the first unlock only. Raw positions live
// in `PointBufferStore` for at most 36 hours; `DetectionLogStore` is the "Erkennungs-Protokoll" (names, times, reasons).
// Neither is part of the export, the backup or the sync.

enum DetectionFiles {
    private static let folder = "TripDetection"

    static var directory: URL {
        let base = URL.applicationSupportDirectory.appending(path: folder, directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = base
            try? url.setResourceValues(values)
        }
        return base
    }

    static func url(_ name: String) -> URL { directory.appending(path: name) }

    /// Reads a Codable file; nil when it is missing or unreadable (an unreadable file is as good as none).
    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        var url = self.url(name)
        // Readable in the background after the first unlock (a region or visit event can relaunch the app while locked).
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(name))
    }

    /// Everything the detection keeps on disk.
    static func removeAll() {
        remove(PointBufferStore.fileName)
        remove(DetectionLogStore.fileName)
    }
}

/// The rolling buffer of raw positions (at most 36 h).
enum PointBufferStore {
    static let fileName = "points.json"

    static func load(now: Date = Date()) -> RollingPointBuffer {
        var buffer = DetectionFiles.load(RollingPointBuffer.self, from: fileName) ?? RollingPointBuffer()
        buffer.prune(now: now)
        return buffer
    }

    static func save(_ buffer: RollingPointBuffer) {
        if buffer.isEmpty { DetectionFiles.remove(fileName) } else { DetectionFiles.save(buffer, to: fileName) }
    }
}

/// The local "Erkennungs-Protokoll".
enum DetectionLogStore {
    static let fileName = "log.json"

    static func load(now: Date = Date()) -> DetectionLog {
        var log = DetectionFiles.load(DetectionLog.self, from: fileName) ?? DetectionLog()
        log.prune(now: now)
        return log
    }

    static func save(_ log: DetectionLog) {
        if log.entries.isEmpty { DetectionFiles.remove(fileName) } else { DetectionFiles.save(log, to: fileName) }
    }
}

/// The switches of the detection (UserDefaults, this device only).
enum DetectionDefaults {
    /// Hintergrund-Erkennung (Beta). A new key: the earlier geofence switch ("detection.enabled") does not carry over, because
    /// the new mode keeps positions on the device and needs the explanation screen first.
    static let backgroundEnabled = "tripdetect.background.enabled"
    /// The explanation screen was confirmed ("Verstanden, einschalten").
    static let explained = "tripdetect.background.explained"
    /// The one timetable lookup per candidate (effective only with the consent for live data).
    static let timetableLookup = "tripdetect.timetableLookup"
    /// The earlier geofence detection's keys, read once for the migration and then removed.
    static let legacyEnabled = "detection.enabled"
    static let legacySuggestions = "detection.suggestions"
    static let legacyLastExit = "detection.lastExit"
    static let legacyLastArrival = "detection.lastArrival"
}
