import XCTest
@testable import KlimaCore

// MARK: settings – Manuell aktualisieren
final class ManualUpdateTests: XCTestCase {
    private let hash = String(repeating: "ab", count: 32)

    private func manifest(size: Int? = 1000, sha: String? = nil) -> UpdateManifest {
        UpdateManifest(version: SemanticVersion(major: 1, minor: 0, patch: 5), build: 361, publishedAt: "2026-10-09T10:00:00Z",
                       downloadURL: "https://example.com/KlimaBilanz-1.0.5.ipa", size: size, sha256: sha)
    }

    func testDecodesSizeAndChecksumFromPublishedManifest() throws {
        let json = """
        {"version":"1.0.4","build":350,"publishedAt":"2026-10-09T22:44:28Z","downloadURL":"https://x/y.ipa",
         "size":23692125,"sha256":"\(hash)","releaseNotes":["A"],"tariffsSHA256":"ff","bundleIdentifier":"b"}
        """
        let m = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
        XCTAssertEqual(m.size, 23692125)
        XCTAssertEqual(m.sha256, hash)
    }

    func testOlderManifestWithoutTheFieldsStillDecodes() throws {
        let json = #"{"version":"1.0.0","build":1,"publishedAt":"x","downloadURL":"https://x/y.ipa","releaseNotes":[]}"#
        let m = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
        XCTAssertNil(m.size)
        XCTAssertNil(m.sha256)
        XCTAssertEqual(ManualUpdate.verify(manifest: m, actualSize: 5, actualChecksum: "00"), .unverifiable)
    }

    func testVerification() {
        let m = manifest(sha: hash.uppercased())
        XCTAssertEqual(ManualUpdate.verify(manifest: m, actualSize: 1000, actualChecksum: hash), .verified)
        XCTAssertEqual(ManualUpdate.verify(manifest: m, actualSize: 999, actualChecksum: hash), .sizeMismatch(expected: 1000, actual: 999))
        XCTAssertEqual(ManualUpdate.verify(manifest: m, actualSize: 1000, actualChecksum: String(repeating: "0", count: 64)), .checksumMismatch)
        XCTAssertEqual(ManualUpdate.verify(manifest: m, actualSize: 1000, actualChecksum: nil), .checksumMismatch)
        XCTAssertEqual(ManualUpdate.verify(manifest: manifest(sha: "nothex"), actualSize: 1000, actualChecksum: hash), .unverifiable)
    }

    func testFileNameAndSizes() {
        XCTAssertEqual(ManualUpdate.fileName(for: manifest()), "KlimaBilanz-1.0.5-361.ipa")
        XCTAssertEqual(ManualUpdate.expectedSize(manifest(size: nil), announced: 42), 42)
        XCTAssertEqual(ManualUpdate.expectedSize(manifest(size: 1000), announced: 42), 1000)
        XCTAssertNil(ManualUpdate.expectedSize(manifest(size: nil), announced: -1))
        XCTAssertEqual(ManualUpdate.fraction(received: 500, total: 1000), 0.5)
        XCTAssertEqual(ManualUpdate.fraction(received: 5000, total: 1000), 1)
        XCTAssertNil(ManualUpdate.fraction(received: 5, total: nil))
    }

    func testStaleness() {
        let v104 = SemanticVersion(major: 1, minor: 0, patch: 4), v105 = SemanticVersion(major: 1, minor: 0, patch: 5)
        XCTAssertFalse(ManualUpdate.isStale(fileVersion: v105, fileBuild: 361, installed: v104, installedBuild: 400))
        XCTAssertTrue(ManualUpdate.isStale(fileVersion: v104, fileBuild: 999, installed: v105, installedBuild: 1))
        XCTAssertTrue(ManualUpdate.isStale(fileVersion: v105, fileBuild: 361, installed: v105, installedBuild: 361))
        XCTAssertFalse(ManualUpdate.isStale(fileVersion: v105, fileBuild: 362, installed: v105, installedBuild: 361))
    }
}
