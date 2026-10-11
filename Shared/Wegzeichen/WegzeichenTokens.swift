import SwiftUI
import KlimaCore

// Wegzeichen tokens (docs/ENRICH_SPEC.md §3.1, BADGE_SPEC §2): styling of the plate families, plate sizes and the
// Gipfelfarben of the own ski-pass badge. All colours are own values: no operator, state or ski-area brand colours.
// `LineKind` itself (cases, order, spoken noun) lives in KlimaCore; this file only adds its look.

extension LineKind {
    enum Shape: Sendable { case wedge, rect, soft, square, capsule }

    var shape: Shape {
        switch self {
        case .fern, .nacht: .wedge
        case .regio: .rect
        case .sBahn, .tram: .soft
        case .uBahn: .square
        default: .capsule
        }
    }

    /// Plate fill (light / dark). U-Bahn colours depend on the line number.
    func fill(for text: String) -> Color {
        switch self {
        case .fern: Color(light: "#1B2F57", dark: "#DCE6F5")
        case .nacht: Color(light: "#2B2470", dark: "#C9C2FF")
        case .regio: Color(light: "#1F66C1", dark: "#7CC4FF")
        case .sBahn: Color(light: "#0E7C8A", dark: "#5FD6E0")
        case .uBahn: Self.uBahnFill(text)
        case .tram: Color(light: "#6A55D6", dark: "#B3A6FF")
        case .bus: Color(light: "#C4500C", dark: "#FFAE73")
        case .nachtbus: Color(light: "#1A2140", dark: "#2A3563")
        case .skibus: Color(light: "#FFFFFF", dark: "#E3EDFF")
        case .wanderbus: Color(light: "#4D7A1F", dark: "#A8D877")
        case .rufbus: Color(light: "#C4500C14", dark: "#FFAE731A")
        case .sev: Color(light: "#F2C230", dark: "#FFD866")
        case .seilbahn: Color(light: "#1E7A5C", dark: "#6BD6A9")
        case .schiff: Color(light: "#0F7F75", dark: "#5FD1C2")
        case .sonst: Color(light: "#56657A", dark: "#B7C4D4")
        }
    }

    var textColor: Color {
        switch self {
        case .nachtbus: Color(hex: "#FFD66B")
        case .skibus: Color(hex: "#23349E")
        case .rufbus: Color(light: "#A8480E", dark: "#FFB98A")
        case .sev: Color(hex: "#0A1626")
        default: Color(light: "#FFFFFF", dark: "#0A1626")
        }
    }

    /// Mandatory boundary ring (plates whose fill is too close to the card colour).
    var ring: Color? {
        switch self {
        case .skibus: Color(light: "#3448C5", dark: "#8E9BFF")
        case .nachtbus: Color(hex: "#FFD66B").opacity(0.55)
        case .sev: Color(light: "#966E008C", dark: "#00000000")
        default: nil
        }
    }

    static func uBahnFill(_ text: String) -> Color {
        switch text {
        case "U1": Color(light: "#C62F3B", dark: "#FF8A93")
        case "U2": Color(light: "#8E4BA0", dark: "#D9A3E8")
        case "U3": Color(light: "#B8520C", dark: "#FFB066")
        case "U4": Color(light: "#1B7F45", dark: "#6FD69A")
        case "U5": Color(light: "#0F7A85", dark: "#5ED3D9")
        case "U6": Color(light: "#8A5A2B", dark: "#D9A878")
        default: Color(light: "#56657A", dark: "#B7C4D4")
        }
    }
}

// MARK: - Sizes

enum PlateSize: String, CaseIterable, Sendable {
    case xs, s, m, l

    var height: CGFloat { switch self { case .xs: 16; case .s: 18; case .m: 22; case .l: 28 } }
    var fontSize: CGFloat { switch self { case .xs: 10; case .s: 11; case .m: 13; case .l: 16 } }
    var hPadding: CGFloat { switch self { case .xs: 4.5; case .s: 5; case .m: 6.5; case .l: 8.5 } }
    var weight: Font.Weight { self == .xs || self == .s ? .heavy : .bold }
    var textStyle: Font.TextStyle { switch self { case .xs, .s: .caption2; case .m: .footnote; case .l: .callout } }
    /// Dynamic Type cap for the height (pt).
    var maxHeight: CGFloat { switch self { case .xs: 20; case .s: 24; case .m: 28; case .l: 34 } }
    /// The text budget of this size (`LinePlateText`).
    var textSize: LinePlateText.Size { LinePlateText.Size(rawValue: rawValue) ?? .s }
}

// MARK: - Gipfelfarben

enum SummitHue: String, CaseIterable, Sendable {
    case enzian, gletscher, daemmerung, alpengluehen, zirbe, morgenrot, bergsee, fels

    var color: Color {
        switch self {
        case .enzian: Color(hex: "#3448C5")
        case .gletscher: Color(hex: "#2A6FD1")
        case .daemmerung: Color(hex: "#6A5ED6")
        case .alpengluehen: Color(hex: "#D2456C")
        case .zirbe: Color(hex: "#1F7A5E")
        case .morgenrot: Color(hex: "#C9622C")
        case .bergsee: Color(hex: "#138794")
        case .fels: Color(hex: "#5E6E82")
        }
    }
}
