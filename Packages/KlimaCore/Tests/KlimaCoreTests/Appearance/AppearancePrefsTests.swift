import XCTest
@testable import KlimaCore

/// theme.v1 (docs/THEMES.md §7): round trip, tolerant decoding, garbage gives the defaults.
final class AppearancePrefsTests: XCTestCase {
    func testRoundTrip() {
        let prefs = AppearancePrefs(palette: .zirbe, motion: .calm, haptics: .subtle,
                                    format: FormatPrefs(amounts: .cents, weekStart: .sunday, co2: .kilograms))
        XCTAssertEqual(AppearancePrefs.decode(prefs.encoded()), prefs)
        let json = String(decoding: prefs.encoded(), as: UTF8.self)
        XCTAssertTrue(json.contains(#""palette":"zirbe""#), json)
        XCTAssertTrue(json.contains(#""motion":"ruhig""#), json)
        XCTAssertTrue(json.contains(#""version":1"#), json)
    }

    func testDefaultsAreTheLookBeforeThemes() {
        let prefs = AppearancePrefs.standard
        XCTAssertEqual(prefs.palette, .gletscher)
        XCTAssertEqual(prefs.motion, .full)
        XCTAssertEqual(prefs.haptics, .full)
        XCTAssertEqual(prefs.format, FormatPrefs(amounts: .automatic, weekStart: .monday, co2: .automatic))
        XCTAssertTrue(prefs.isStandardLook)
    }

    func testGarbageGivesDefaults() {
        for garbage in ["", "nonsense", "[1,2,3]", "42", "null", "{\"palette\":"] {
            let data = Data(garbage.utf8)
            XCTAssertNil(AppearancePrefs.decode(data), garbage)
            XCTAssertEqual(AppearancePrefs.load(data, legacyHapticsEnabled: nil), .standard, garbage)
        }
        XCTAssertNil(AppearancePrefs.decode(nil))
    }

    func testUnknownAndMissingValuesFallBackOneByOne() {
        let json = #"{"palette":"neon","motion":"ruhig","haptics":7,"format":{"amounts":"cent","weekStart":"friday"},"extra":true}"#
        let prefs = AppearancePrefs.decode(Data(json.utf8))
        XCTAssertEqual(prefs?.palette, .gletscher, "unknown palette → Gletscher")
        XCTAssertEqual(prefs?.motion, .calm, "a valid value survives its broken neighbours")
        XCTAssertEqual(prefs?.haptics, .full)
        XCTAssertEqual(prefs?.format.amounts, .cents)
        XCTAssertEqual(prefs?.format.weekStart, .monday)
        XCTAssertEqual(prefs?.format.co2, .automatic)
        XCTAssertEqual(AppearancePrefs.decode(Data("{}".utf8)), .standard)
        XCTAssertEqual(AppearancePrefs.decode(Data(#"{"format":"x"}"#.utf8))?.format, .standard)
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(ThemePaletteID.allCases.map(\.rawValue), ["gletscher", "zirbe", "morgenrot", "daemmerung", "alpengluehen", "graphit"])
        XCTAssertEqual(HapticLevel.allCases.map(\.rawValue), ["aus", "dezent", "voll"])
        XCTAssertEqual(FormatPrefs.Amounts.allCases.map(\.rawValue), ["auto", "ganz", "cent"])
        XCTAssertEqual(AppearancePrefs.storageKey, "theme.v1")
    }
}
