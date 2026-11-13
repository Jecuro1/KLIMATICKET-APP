import XCTest
@testable import KlimaCore

/// MARK: review-themes – which palettes' accents pass for a colour with a meaning (docs/THEMES.md §3). The app keeps a figure
/// beside Gewinn / Verlust / Gipfel neutral in those palettes, so „Noch € 356“ never reads as a gain in Zirbe.
final class AppearanceMeaningTests: XCTestCase {
    func testHueAndSaturation() {
        func hue(_ hex: String) -> Double { ThemeMeaning.hueAndSaturation(ThemeRGB(hex: hex)!).hue }
        XCTAssertEqual(hue("#FF0000"), 0, accuracy: 0.001)
        XCTAssertEqual(hue("#00FF00"), 120, accuracy: 0.001)
        XCTAssertEqual(hue("#0000FF"), 240, accuracy: 0.001)
        XCTAssertEqual(hue("#FF00FF"), 300, accuracy: 0.001)
        XCTAssertEqual(ThemeMeaning.hueAndSaturation(ThemeRGB(hex: "#808080")!).saturation, 0, accuracy: 0.001)
        XCTAssertEqual(ThemeMeaning.hueDistance(350, 10), 20, accuracy: 0.001)
        XCTAssertEqual(ThemeMeaning.hueDistance(10, 350), 20, accuracy: 0.001)
        XCTAssertEqual(ThemeMeaning.hueDistance(0, 180), 180, accuracy: 0.001)
    }

    /// Green, orange and rose accents sit next to Gewinn, Gipfel and Verlust; blue, violet and slate do not.
    func testWhichPalettesEchoAMeaning() {
        let echoed = Dictionary(uniqueKeysWithValues: ThemeCatalog.all.map { ($0.id, ThemeMeaning.echoedMeaning($0)) })
        XCTAssertNil(echoed[.gletscher] ?? nil, "Gletscher (blue) keeps its own gradient")
        XCTAssertNil(echoed[.daemmerung] ?? nil)
        XCTAssertNil(echoed[.graphit] ?? nil, "slate is too grey to carry a hue")
        XCTAssertNotNil(echoed[.zirbe] ?? nil, "Zirbe green reads like Gewinn")
        XCTAssertNotNil(echoed[.morgenrot] ?? nil, "Morgenrot orange reads like Gipfel")
        XCTAssertNotNil(echoed[.alpengluehen] ?? nil, "Alpenglühen rose reads like Verlust")
    }

    /// A meaning colour always echoes itself – the check cannot pass a palette that copies one.
    func testACopiedMeaningColourIsCaught() {
        for token in ThemeSemanticToken.allCases {
            let copy = ThemePalette(id: .graphit, name: "Kopie", tagline: "Test", accent: token.hex, accentText: token.hex,
                                    prominentTint: ThemeHexPair("#475569", "#475569"),
                                    route: Array(repeating: token.hex, count: 3), cta: ["#475569", "#475569", "#475569"])
            XCTAssertTrue(ThemeMeaning.echoesMeaning(copy), "\(token)")
        }
    }
}
