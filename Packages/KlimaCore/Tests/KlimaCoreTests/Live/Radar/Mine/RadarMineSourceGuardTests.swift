import XCTest
@testable import KlimaCore

/// What „Meine Fahrzeuge“ may not do, checked in its sources (docs/RADAR_MINE.md §6, specs radar2/radarmine.md §13): remembered lines and stops live
/// only in `RadarMine/mine.json` (never UserDefaults, which is part of the iPhone backup); the location is asked through `LocationService` only (no
/// second permission path); no request carries the position (no LocGeoPos / „In der Nähe“ search); the blue dot only after the tap; the board only
/// as the radar's side job. Comments are left out of the scan.
final class RadarMineSourceGuardTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Mine
        .deletingLastPathComponent()   // Radar
        .deletingLastPathComponent()   // Live
        .deletingLastPathComponent()   // KlimaCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // KlimaCore
        .deletingLastPathComponent()   // Packages
        .deletingLastPathComponent()   // repo

    static let folders = ["Packages/KlimaCore/Sources/KlimaCore/Live/Radar/Mine", "App/Sources/Features/Radar/Mine"]

    private func sources() throws -> [(name: String, code: String)] {
        var result: [(String, String)] = []
        for folder in Self.folders {
            let url = Self.root.appendingPathComponent(folder)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let names = try FileManager.default.contentsOfDirectory(atPath: url.path).filter { $0.hasSuffix(".swift") }.sorted()
            for name in names {
                let text = try String(contentsOf: url.appendingPathComponent(name), encoding: .utf8)
                result.append(("\(folder)/\(name)", RadarTrailSourceGuardTests.withoutComments(text)))
            }
        }
        return result
    }

    func testNoDefaultsNoSecondLocationPathNoPositionInARequest() throws {
        let files = try sources()
        XCTAssertFalse(files.isEmpty)
        let forbidden = ["UserDefaults", "@AppStorage", "requestWhenInUseAuthorization", "requestAlwaysAuthorization", "CLLocationManager(",
                         "startUpdatingLocation", "nearby(", "LocGeoPos", "locGeoPos", "NSUbiquitousKeyValueStore", "print(", "NSLog", "Logger(",
                         "URLSession", "ShareLink"]
        for file in files {
            for word in forbidden {
                XCTAssertFalse(file.code.contains(word), "\(file.name) uses \(word)")
            }
        }
    }

    func testTheFileIsWrittenOnlyByTheStore() throws {
        for file in try sources() where file.code.contains("write(to:") || file.code.contains("FileManager") {
            XCTAssertTrue(file.name.hasSuffix("RadarMineStore.swift"), "\(file.name) touches files")
        }
    }

    func testTheBlueDotOnlyWithAFix() throws {
        for file in try sources() where file.code.contains("UserAnnotation(") {
            XCTAssertTrue(file.code.contains("hasLiveFix"), "\(file.name) draws the user's dot without the tap's fix")
        }
    }

    func testTheBoardOnlyAsASideJob() throws {
        for file in try sources() where file.code.contains(".board(") {
            XCTAssertTrue(file.name.hasSuffix("RadarStopBoardSource.swift") || file.name.contains("Sources/KlimaCore"),
                          "\(file.name) asks for a board outside the side job's source")
        }
    }
}
