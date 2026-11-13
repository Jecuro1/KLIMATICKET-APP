import Foundation

// MARK: themes – App-Symbol and palette that belong together (docs/THEMES.md §8). The picker of each one suggests the
// other; nothing is ever switched without a tap.

/// The home-screen icons (App/Sources/Features/AppIcon/AppIconStore.swift `AppIconChoice`, same raw values – the app
/// maps them with an exhaustive switch, so a new icon does not compile without a pairing).
public enum AppearanceIconID: String, CaseIterable, Sendable {
    case alpin, nacht, sonnenaufgang, gletscher, minimal
}

public enum AppearancePairing {
    /// The palette that suits an icon.
    public static func palette(for icon: AppearanceIconID) -> ThemePaletteID {
        switch icon {
        case .alpin: .gletscher          // the original icon with the original colours
        case .nacht: .daemmerung         // blue hour, gold moon
        case .sonnenaufgang: .morgenrot  // the sun behind the summit
        case .gletscher: .gletscher      // icy blue, same name
        case .minimal: .graphit          // just the line on white
        }
    }

    /// The icon that suits a palette.
    public static func icon(for palette: ThemePaletteID) -> AppearanceIconID {
        switch palette {
        case .gletscher: .gletscher
        case .zirbe: .alpin              // no green icon: the original goes with everything
        case .morgenrot: .sonnenaufgang
        case .daemmerung: .nacht
        case .alpengluehen: .sonnenaufgang   // its rosé sky
        case .graphit: .minimal
        }
    }
}
