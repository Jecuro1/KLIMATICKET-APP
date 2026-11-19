import XCTest
@testable import KlimaCore

/// „Spuren“ never leave the memory (docs/RADAR_TRAILS.md §3): no file, no defaults (but the one setting), no archive, no log, no share sheet, no
/// export and no request anywhere in this feature's folders. Comments are left out of the scan; the code itself may not name any of it.
final class RadarTrailSourceGuardTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Trail
        .deletingLastPathComponent()   // Radar
        .deletingLastPathComponent()   // Live
        .deletingLastPathComponent()   // KlimaCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // KlimaCore
        .deletingLastPathComponent()   // Packages
        .deletingLastPathComponent()   // repo

    static let folders = ["Packages/KlimaCore/Sources/KlimaCore/Live/Radar/Trail", "App/Sources/Features/Radar/Trail"]
    /// The one file that may keep the setting `radar.trail.v1`.
    static let settingStore = "RadarTrailSettingStore.swift"

    static let forbidden = ["FileManager", "write(to:", "Data(contentsOf:", "URLSession", "NSKeyedArchiver", "Logger(", "os_log", "NSLog",
                            "print(", "ShareLink", "fileExporter", "UIActivityViewController", "CKContainer", "NSUbiquitousKeyValueStore",
                            // no request of any kind
                            "RadarService", "TimetableService", "HafasClient", "claimSlot", "RequestThrottle"]
    static let settingOnly = ["UserDefaults", "@AppStorage"]

    private func sources() throws -> [(name: String, code: String)] {
        var result: [(String, String)] = []
        for folder in Self.folders {
            let url = Self.root.appendingPathComponent(folder)
            let names = try FileManager.default.contentsOfDirectory(atPath: url.path).filter { $0.hasSuffix(".swift") }.sorted()
            XCTAssertFalse(names.isEmpty, "\(folder) has no sources")
            for name in names {
                let text = try String(contentsOf: url.appendingPathComponent(name), encoding: .utf8)
                result.append(("\(folder)/\(name)", Self.withoutComments(text)))
            }
        }
        return result
    }

    /// The code without `//` comments (doc comments included).
    static func withoutComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            guard let range = line.range(of: "//") else { return line }
            return line[..<range.lowerBound]
        }.joined(separator: "\n")
    }

    func testNothingLeavesTheMemory() throws {
        let files = try sources()
        XCTAssertGreaterThanOrEqual(files.count, 6)
        for file in files {
            for word in Self.forbidden {
                XCTAssertFalse(file.code.contains(word), "\(file.name) uses \(word)")
            }
            if !file.name.hasSuffix(Self.settingStore) {
                for word in Self.settingOnly {
                    XCTAssertFalse(file.code.contains(word), "\(file.name) uses \(word): only \(Self.settingStore) may keep the setting")
                }
            }
        }
    }

    func testTheSettingStoreKeepsOnlyTheSetting() throws {
        let store = try sources().first { $0.name.hasSuffix(Self.settingStore) }
        let code = try XCTUnwrap(store?.code, "the setting store exists")
        XCTAssertTrue(code.contains("RadarTrailSetting.storageKey"))
        XCTAssertFalse(code.contains("RadarTrailSample"))
        XCTAssertFalse(code.contains("RadarTrailRecorder"))
    }

    func testTheScanSeesThroughCommentsOnly() {
        XCTAssertEqual(Self.withoutComments("let a = 1 // print(a)\n// URLSession\nprint(a)"), "let a = 1 \n\nprint(a)")
    }
}
