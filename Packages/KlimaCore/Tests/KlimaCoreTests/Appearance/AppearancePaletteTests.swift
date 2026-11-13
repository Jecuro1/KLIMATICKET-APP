import XCTest
@testable import KlimaCore

/// Look & Feel palettes (docs/THEMES.md §2–3): the registry is complete, Gletscher is exactly the look before themes,
/// every palette passes the contrast gates, and the colours with a meaning are the same in every palette.
final class AppearancePaletteTests: XCTestCase {
    func testRegistryIsCompleteInBothAppearances() {
        XCTAssertEqual(ThemeCatalog.all.map(\.id), ThemePaletteID.allCases)
        XCTAssertEqual(ThemeCatalog.all.count, 6)
        XCTAssertEqual(Set(ThemeCatalog.all.map(\.name)).count, 6, "names are unique")
        for palette in ThemeCatalog.all {
            XCTAssertFalse(palette.name.isEmpty)
            XCTAssertFalse(palette.tagline.isEmpty)
            XCTAssertEqual(palette.route.count, ThemePalette.routeLocations.count, palette.name)
            XCTAssertEqual(palette.cta.count, 3, palette.name)
            for token in ThemeToken.allCases {
                guard let pair = palette.hex(token) else { return XCTFail("\(palette.name): \(token) missing") }
                XCTAssertNotNil(ThemeRGB(hex: pair.light), "\(palette.name) \(token) light \(pair.light)")
                XCTAssertNotNil(ThemeRGB(hex: pair.dark), "\(palette.name) \(token) dark \(pair.dark)")
            }
        }
    }

    /// Gletscher must look exactly like the app before themes (pixel-identical default): the values Theme.swift had.
    func testGletscherIsThePreThemeLook() {
        let g = ThemeCatalog.palette(.standard)
        XCTAssertEqual(ThemePaletteID.standard, .gletscher)
        XCTAssertEqual(g.accent, ThemeHexPair("#2A7BD4", "#7CC4FF"))        // glacier
        XCTAssertEqual(g.accentText, ThemeHexPair("#1D5FB0", "#9DD3FF"))
        XCTAssertEqual(g.prominentTint, ThemeHexPair("#2A7BD4", "#2E78CC"))
        XCTAssertEqual(g.route, [ThemeHexPair("#3B8BE0", "#6CB6FF"), ThemeHexPair("#7C79E6", "#A99FFF"), ThemeHexPair("#F08A5B", "#FFAD85")])
        XCTAssertEqual(ThemePalette.routeLocations, [0, 0.55, 1])
        XCTAssertEqual(g.cta, ["#3A8BE4", "#5C86EA", "#7F7EE8"])
    }

    /// Theme.swift keeps the brand colour `glacier` with the same values Gletscher's accent has.
    func testGletscherAccentMatchesThemeGlacier() throws {
        let theme = try AppearanceRepo.source("Shared/Theme.swift")
        XCTAssertTrue(theme.contains(##"static let glacier = Color(light: "#2A7BD4", dark: "#7CC4FF")"##))
    }

    func testEveryPaletteDiffersFromTheOthers() {
        let accents = ThemeCatalog.all.map(\.accent)
        XCTAssertEqual(Set(accents).count, accents.count)
    }

    // MARK: Contrast gates

    func testEveryPalettePassesEveryContrastGate() {
        for palette in ThemeCatalog.all {
            let gates = ThemeContrast.gates(for: palette)
            XCTAssertEqual(gates.count, 13, "\(palette.name): 2 card + 4 background text gates, 2 accent, 2 prominent, 3 CTA")
            for gate in gates {
                XCTAssertTrue(gate.passes, String(format: "%@ – %@: %.2f : 1 < %.1f : 1", palette.name, gate.name, gate.ratio, gate.minimum))
            }
        }
        XCTAssertEqual(ThemeContrast.shippable.map(\.id), ThemePaletteID.allCases, "a palette that fails a gate is not shipped")
    }

    /// The surfaces the gates use: white at 77 % over #E6ECF3 and white at 7 % over #08132A.
    func testCardSurfaces() {
        let light = ThemeContrast.lightCard, dark = ThemeContrast.darkCard
        XCTAssertEqual(light.r, 255 * 0.77 + 230 * 0.23, accuracy: 1e-9)
        XCTAssertEqual(light.g, 255 * 0.77 + 236 * 0.23, accuracy: 1e-9)
        XCTAssertEqual(light.b, 255 * 0.77 + 243 * 0.23, accuracy: 1e-9)
        XCTAssertEqual(dark.r, 255 * 0.07 + 8 * 0.93, accuracy: 1e-9)
        XCTAssertEqual(dark.b, 255 * 0.07 + 42 * 0.93, accuracy: 1e-9)
    }

    /// Known WCAG values: black on white 21 : 1, the same colour 1 : 1, #767676 on white is the classic 4,54 : 1.
    func testContrastMath() {
        let white = ThemeRGB.white, black = ThemeRGB(hex: "#000000")!
        XCTAssertEqual(ThemeContrast.ratio(black, white), 21, accuracy: 1e-9)
        XCTAssertEqual(ThemeContrast.ratio(white, white), 1, accuracy: 1e-9)
        XCTAssertEqual(ThemeContrast.ratio(ThemeRGB(hex: "767676")!, white), 4.54, accuracy: 0.01)
        XCTAssertNil(ThemeRGB(hex: "#12345"))
        XCTAssertNil(ThemeRGB(hex: "#GGGGGG"))
        XCTAssertNil(ThemeRGB(hex: "#2A7BD4CC"), "palettes use opaque colours only")
    }

    /// A deliberately broken palette fails: the gate works in both directions.
    func testAFailingPaletteIsCaught() {
        let pale = ThemePalette(id: .graphit, name: "Blass", tagline: "x",
                                accent: ThemeHexPair("#D0D8E0", "#1A2030"), accentText: ThemeHexPair("#9AA6B2", "#3A4558"),
                                prominentTint: ThemeHexPair("#C8D0DA", "#C8D0DA"),
                                route: [ThemeHexPair("#FFFFFF", "#000000"), ThemeHexPair("#FFFFFF", "#000000"), ThemeHexPair("#FFFFFF", "#000000")],
                                cta: ["#F0F0F0", "#E0E0E0", "#D0D0D0"])
        let failing = ThemeContrast.gates(for: pale).filter { !$0.passes }
        XCTAssertEqual(failing.count, 13)
    }

    // MARK: Semantic colours

    /// Colour keeps its meaning: no palette defines positive, negative, summit or live – and the values the semantic
    /// table states are the ones Theme.swift has.
    func testSemanticTokensAreIdenticalAcrossPalettes() throws {
        let themable = Set(ThemeToken.allCases.map(\.rawValue))
        for token in ThemeSemanticToken.allCases {
            XCTAssertFalse(themable.contains(token.rawValue), "\(token) must not be a palette token")
        }
        let theme = try AppearanceRepo.source("Shared/Theme.swift")
        for token in ThemeSemanticToken.allCases {
            let line = #"static let \#(token.themeProperty) = Color(light: "\#(token.hex.light)", dark: "\#(token.hex.dark)")"#
            XCTAssertTrue(theme.contains(line), "Theme.swift no longer has \(line)")
        }
        // The semantic tokens are not read through the palette runtime.
        for token in ["positive", "negative", "summit", "live", "positiveText", "summitText", "negativeText"] {
            XCTAssertFalse(theme.contains("static let \(token) = ThemeRuntime"), token)
        }
    }

    /// The text-safe semantic variants pass the same 4,5 : 1 gate (they are what small coloured text uses in every palette).
    func testSemanticTextTokensAreTextSafe() {
        for token in [ThemeSemanticToken.positiveText, .summitText, .negativeText] {
            let light = ThemeRGB(hex: token.hex.light)!, dark = ThemeRGB(hex: token.hex.dark)!
            XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(light, ThemeContrast.lightCard), 4.5, "\(token) light")
            XCTAssertGreaterThanOrEqual(ThemeContrast.ratio(dark, ThemeContrast.darkCard), 4.5, "\(token) dark")
        }
    }

    // MARK: Pairing

    func testIconPairingIsTotalBothWays() throws {
        for icon in AppearanceIconID.allCases {
            XCTAssertTrue(ThemePaletteID.allCases.contains(AppearancePairing.palette(for: icon)))
        }
        for palette in ThemePaletteID.allCases {
            XCTAssertTrue(AppearanceIconID.allCases.contains(AppearancePairing.icon(for: palette)))
        }
        // Every icon the app offers has a pairing, under the same raw value.
        let store = try AppearanceRepo.source("App/Sources/Features/AppIcon/AppIconStore.swift")
        XCTAssertEqual(AppearanceRepo.enumCases("AppIconChoice", in: store), AppearanceIconID.allCases.map(\.rawValue))
        XCTAssertEqual(AppearancePairing.palette(for: .alpin), .gletscher, "the original icon suggests the original colours")
        XCTAssertEqual(AppearancePairing.icon(for: .daemmerung), .nacht)
        XCTAssertEqual(AppearancePairing.palette(for: AppearancePairing.icon(for: .morgenrot)), .morgenrot)
    }
}
