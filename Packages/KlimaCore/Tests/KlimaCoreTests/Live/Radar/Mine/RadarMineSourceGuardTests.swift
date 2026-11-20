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

    func testTheFunctionsHubNamesWhatIsSentAndWhatStays() {
        // The Funktionen-Zentrale (docs/FUNCTIONS_HUB.md) lists every data flow: the stop goes to the ÖBB-Auskunft inside the radar's own flow (one
        // item per feature and recipient), the remembered lines, the last stops and the fix stay on the iPhone.
        let flows = FeatureID.radar.descriptor.dataFlows
        let timetable = flows.filter { $0.recipient == .oebbTimetable }
        XCTAssertEqual(timetable.count, 1)
        XCTAssertTrue(timetable.first?.sends.contains("„Wo bleibt mein Bus?“ die Haltestelle") == true)
        XCTAssertTrue(timetable.first?.when.contains("einmal pro Minute") == true)
        XCTAssertTrue(timetable.first?.when.contains("24 Anfragen pro Minute") == true)
        let mine = flows.filter { $0.recipient == .device && $0.sends.hasPrefix("Meine Fahrzeuge:") }
        XCTAssertEqual(mine.count, 1)
        XCTAssertTrue(mine.first?.sends.contains("nicht in der iPhone-Sicherung") == true)
        XCTAssertTrue(mine.first?.sends.contains("nie gesendet") == true)
    }

    func testTheBoardOnlyThroughTheSideJobsSource() throws {
        // Only `RadarStopBoardSource` (called from the side job in `RadarMineModel.run`) reaches the timetable or the station linker.
        let words = ["timetable.", "linker.", "TimetableService", "HafasClient", "claimSlot", "RequestThrottle"]
        for file in try sources() where file.name.hasPrefix("App/") && !file.name.hasSuffix("RadarStopBoardSource.swift") {
            for word in words {
                XCTAssertFalse(file.code.contains(word), "\(file.name) uses \(word) outside the side job's source")
            }
        }
    }
}
