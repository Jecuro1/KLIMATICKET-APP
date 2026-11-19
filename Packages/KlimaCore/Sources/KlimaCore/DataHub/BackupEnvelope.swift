import Foundation

// MARK: data – the frame of a backup file (docs/DATA_HUB.md §3). Version 3 = version 2 (tickets, trips, favourites, benefits; the rows
// are the app's) plus `settings` and `checksum`. Both are new keys: a version-2 app ignores them, and this reader takes a version-2
// file without them. The app decodes the rows; KlimaCore decides whether a file may be restored at all.

public enum BackupFormat {
    public static let name = "klimabilanz-backup"
    /// What this app writes.
    public static let currentVersion = 3
}

/// The keys around the rows.
public struct BackupEnvelope: Codable, Equatable, Sendable {
    public var format: String
    public var version: Int
    public var exportedAt: Date?
    public var appVersion: String?
    /// Version 3: the allow-listed settings (BackupSettingsPolicy).
    public var settings: [String: BackupSettingValue]?
    /// Version 3: „crc32:xxxxxxxx“ (BackupChecksum).
    public var checksum: String?

    private enum CodingKeys: String, CodingKey { case format, version, exportedAt, appVersion, settings, checksum }

    public init(format: String = BackupFormat.name, version: Int = BackupFormat.currentVersion, exportedAt: Date? = nil,
                appVersion: String? = nil, settings: [String: BackupSettingValue]? = nil, checksum: String? = nil) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.settings = settings
        self.checksum = checksum
    }

    /// Tolerant like the app's reader: a missing format or version means a version-1 file; a settings block that does not decode
    /// is dropped (the rows still restore).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? c.decodeIfPresent(String.self, forKey: .format)) ?? BackupFormat.name
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        exportedAt = try? c.decodeIfPresent(Date.self, forKey: .exportedAt)
        appVersion = try? c.decodeIfPresent(String.self, forKey: .appVersion)
        settings = try? c.decodeIfPresent([String: BackupSettingValue].self, forKey: .settings)
        checksum = try? c.decodeIfPresent(String.self, forKey: .checksum)
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Whether a file may be restored, and why not.
public struct BackupInspection: Equatable, Sendable {
    public enum Problem: Equatable, Sendable {
        /// Not JSON, or JSON without the four tables.
        case notABackup
        /// JSON of another app.
        case otherFormat(String)
        /// The checksum does not match – damaged or changed after writing.
        case damaged

        public var message: String {
            switch self {
            case .notABackup: "Die Datei ist kein KlimaBilanz-Backup."
            case .otherFormat: "Die Datei stammt nicht von KlimaBilanz."
            case .damaged: "Die Datei ist beschädigt oder wurde nachträglich verändert (Prüfsumme stimmt nicht). Es wurde nichts geändert."
            }
        }
    }

    public var envelope: BackupEnvelope?
    public var verdict: BackupChecksum.Verdict
    public var problem: Problem?

    public var canRestore: Bool { problem == nil }
    /// A file from a newer app: it restores (unknown keys are ignored), but the preview says that something may be left out.
    public var isFromNewerApp: Bool { (envelope?.version ?? 0) > BackupFormat.currentVersion }

    /// The rows themselves are checked by the app's decoder; this decides on the frame and the checksum before anything is read.
    public static func inspect(_ data: Data) -> BackupInspection {
        let verdict = BackupChecksum.verify(data)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              ["tickets", "trips", "favorites"].allSatisfy({ object[$0] is [Any] }) else {
            return BackupInspection(envelope: nil, verdict: verdict, problem: .notABackup)
        }
        guard let envelope = try? BackupEnvelope.decoder().decode(BackupEnvelope.self, from: data) else {
            return BackupInspection(envelope: nil, verdict: verdict, problem: .notABackup)
        }
        if envelope.format != BackupFormat.name {
            return BackupInspection(envelope: envelope, verdict: verdict, problem: .otherFormat(envelope.format))
        }
        if verdict.isDamaged {
            return BackupInspection(envelope: envelope, verdict: verdict, problem: .damaged)
        }
        return BackupInspection(envelope: envelope, verdict: verdict, problem: nil)
    }
}
