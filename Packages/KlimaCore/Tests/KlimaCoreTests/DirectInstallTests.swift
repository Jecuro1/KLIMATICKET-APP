import XCTest
@testable import KlimaCore

/// Direkt installieren (ad-hoc OTA, docs/DIREKT_INSTALLIEREN.md): profile classification and the itms-services link.
final class DirectInstallTests: XCTestCase {
    private let bundle = "com.knitelarlberg.klimabilanz"
    private let devices = ["00008110-001A2B3C4D5E801E"]

    func testProfileKinds() {
        XCTAssertEqual(ProvisioningKind(profile: nil), .none)
        XCTAssertEqual(ProvisioningKind(profile: ["ProvisionedDevices": devices, "Entitlements": ["get-task-allow": false]]), .adHoc)
        // Ad-hoc profiles may omit get-task-allow altogether.
        XCTAssertEqual(ProvisioningKind(profile: ["ProvisionedDevices": devices, "Entitlements": [String: Any]()]), .adHoc)
        // AltStore / SideStore / Sideloadly sign with development profiles – they list devices too.
        XCTAssertEqual(ProvisioningKind(profile: ["ProvisionedDevices": devices, "Entitlements": ["get-task-allow": true]]), .development)
        XCTAssertEqual(ProvisioningKind(profile: ["ProvisionsAllDevices": true, "Entitlements": ["get-task-allow": false]]), .enterprise)
        XCTAssertEqual(ProvisioningKind(profile: ["Entitlements": ["get-task-allow": false]]), .other)
        XCTAssertEqual(ProvisioningKind(profile: ["ProvisionedDevices": [String](), "Entitlements": [String: Any]()]), .other)
    }

    func testReplacesInPlaceOnlyOurOwnAdHocBuild() {
        XCTAssertTrue(DirectInstall.replacesInPlace(kind: .adHoc, bundleIdentifier: bundle, expected: bundle))
        // SideStore/AltStore copies carry <id>.<TEAMID>: the ad-hoc build would be a second app.
        XCTAssertFalse(DirectInstall.replacesInPlace(kind: .adHoc, bundleIdentifier: bundle + ".ABCDE12345", expected: bundle))
        XCTAssertFalse(DirectInstall.replacesInPlace(kind: .development, bundleIdentifier: bundle, expected: bundle))
        XCTAssertFalse(DirectInstall.replacesInPlace(kind: .none, bundleIdentifier: bundle, expected: bundle))
        XCTAssertFalse(DirectInstall.replacesInPlace(kind: .adHoc, bundleIdentifier: nil, expected: bundle))
    }

    func testItmsServicesLink() throws {
        let manifest = "https://github.com/Jecuro1/KLIMATICKET-APP/releases/download/v1.2.3/manifest.plist"
        let link = try XCTUnwrap(DirectInstall.link(manifestURL: manifest))
        XCTAssertEqual(link.scheme, "itms-services")
        XCTAssertEqual(link.absoluteString,
                       "itms-services://?action=download-manifest&url=https://github.com/Jecuro1/KLIMATICKET-APP/releases/download/v1.2.3/manifest.plist")
        let query = try XCTUnwrap(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first(where: { $0.name == "url" })?.value, manifest)
        // A manifest URL with its own query must not leak into the itms-services query.
        let signed = try XCTUnwrap(DirectInstall.link(manifestURL: "https://api.example.at/v1/ota/v1.2.3/manifest.plist?x=1&y=2"))
        let items = try XCTUnwrap(URLComponents(url: signed, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.map(\.name), ["action", "url"])
        XCTAssertEqual(items.last?.value, "https://api.example.at/v1/ota/v1.2.3/manifest.plist?x=1&y=2")
    }

    func testOnlyHttpsManifests() {
        XCTAssertNil(DirectInstall.link(manifestURL: nil))
        XCTAssertNil(DirectInstall.link(manifestURL: ""))
        XCTAssertNil(DirectInstall.link(manifestURL: "http://example.com/manifest.plist"))
        XCTAssertNil(DirectInstall.link(manifestURL: "itms-services://?action=download-manifest&url=x"))
        XCTAssertNil(DirectInstall.link(manifestURL: "https:///manifest.plist"))
    }

    func testManifestFieldDecodesAndStaysOptional() throws {
        let json = #"{"version":"1.2.3","build":245,"publishedAt":"2026-10-09T12:00:00Z","downloadURL":"https://x/a.ipa","releaseNotes":[],"otaManifestURL":"https://x/manifest.plist"}"#
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.otaManifestURL, "https://x/manifest.plist")
        let old = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.replacingOccurrences(of: #","otaManifestURL":"https://x/manifest.plist""#, with: "").utf8))
        XCTAssertNil(old.otaManifestURL)
    }
}
