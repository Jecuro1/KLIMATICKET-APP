import SwiftUI
import UIKit

// App-Symbol (Einstellungen › Darstellung › App-Symbol): the selectable home-screen icons and the switch.
// Artwork: scripts/render_app_icons.py → Assets.xcassets (AppIcon*.appiconset with light/dark/tinted variants,
// AppIconPreview-*.imageset for the in-app previews). Alternate icon names: project.yml
// (ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES); CI checks they reach CFBundleAlternateIcons.

/// One home-screen icon. `alpin` is the primary icon (`alternateIconName == nil`).
enum AppIconChoice: String, CaseIterable, Identifiable {
    case alpin, nacht, sonnenaufgang, gletscher, minimal

    var id: String { rawValue }

    /// Name of the alternate icon set passed to `setAlternateIconName` – nil for the primary icon.
    var alternateIconName: String? {
        switch self {
        case .alpin: nil
        case .nacht: "AppIcon-Nacht"
        case .sonnenaufgang: "AppIcon-Sonnenaufgang"
        case .gletscher: "AppIcon-Gletscher"
        case .minimal: "AppIcon-Minimal"
        }
    }

    /// Light + dark preview image (imageset with a dark appearance – follows the environment's colour scheme).
    var previewAsset: String {
        switch self {
        case .alpin: "AppIconPreview-Alpin"
        case .nacht: "AppIconPreview-Nacht"
        case .sonnenaufgang: "AppIconPreview-Sonnenaufgang"
        case .gletscher: "AppIconPreview-Gletscher"
        case .minimal: "AppIconPreview-Minimal"
        }
    }

    var title: String {
        switch self {
        case .alpin: "Alpin"
        case .nacht: "Nacht"
        case .sonnenaufgang: "Sonnenaufgang"
        case .gletscher: "Gletscher"
        case .minimal: "Minimal"
        }
    }

    var subtitle: String {
        switch self {
        case .alpin: "Das Original – Gipfel aus Glas im Morgenlicht"
        case .nacht: "Blaue Stunde mit Mond und Sternen"
        case .sonnenaufgang: "Dein Gipfel vor der aufgehenden Sonne"
        case .gletscher: "Kühles Eis, klare Linie"
        case .minimal: "Nur der Weg zum Gipfel"
        }
    }

    /// Signature colour of the artwork (glow behind the stage icon when it changes).
    var glow: Color {
        switch self {
        case .alpin: Color(hex: "#FF9F73")
        case .nacht: Color(hex: "#FFD27A")
        case .sonnenaufgang: Color(hex: "#FFB86E")
        case .gletscher: Color(hex: "#4FD3DD")
        case .minimal: Color(hex: "#7F6BFF")
        }
    }

    init(alternateIconName name: String?) {
        self = AppIconChoice.allCases.first { $0.alternateIconName == name } ?? .alpin
    }
}

/// The icon the system currently shows and the switch to another one.
@MainActor
@Observable
final class AppIconStore {
    static let shared = AppIconStore()

    private(set) var current: AppIconChoice
    /// A switch is in flight (the system call answers after its own confirmation alert is up).
    private(set) var isChanging = false

    // MARK: settings – `alternateIconName` is a synchronous LaunchServices XPC on the main thread; at the first render
    // of Einstellungen (app-icon row, update and brand rows) it blocked a CI launch for 16 s. This store is the only
    // writer of the icon, so it remembers its last answer and asks the system once per install. Screenshots always run
    // with the primary icon and never persist a choice.
    private static let cacheKey = "appIcon.current"

    private init() {
        if LaunchMode.isScreenshot {
            current = .alpin
        } else if let cached = UserDefaults.standard.string(forKey: Self.cacheKey).flatMap(AppIconChoice.init(rawValue:)) {
            current = cached
        } else {
            current = AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName)
            UserDefaults.standard.set(current.rawValue, forKey: Self.cacheKey)
        }
    }

    /// False on systems without alternate icons – the settings row is hidden then.
    var isSupported: Bool { UIApplication.shared.supportsAlternateIcons }

    /// Switches the home-screen icon. iOS confirms with its own short alert. `completion(false)` = unchanged.
    /// CI screenshots only update the UI (the system alert would cover the screen).
    func select(_ choice: AppIconChoice, completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard !isChanging else { return }
        guard choice != current else {
            completion(true)
            return
        }
        if LaunchMode.isScreenshot || !isSupported {
            current = choice
            completion(true)
            return
        }
        let previous = current
        current = choice
        isChanging = true
        UIApplication.shared.setAlternateIconName(choice.alternateIconName) { error in
            // The completion may arrive off the main thread – hop over before touching state.
            Task { @MainActor in
                let store = AppIconStore.shared
                store.isChanging = false
                if error != nil {
                    withMotion(Motion.snappy) { store.current = previous }
                    completion(false)
                } else {
                    UserDefaults.standard.set(choice.rawValue, forKey: AppIconStore.cacheKey) // MARK: settings
                    completion(true)
                }
            }
        }
    }
}

/// An icon preview clipped to the home-screen shape (continuous corners, 22.37 %).
struct AppIconImage: View {
    var choice: AppIconChoice
    var size: CGFloat

    var body: some View {
        Image(choice.previewAsset)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .overlay {
                // iOS 26 draws a fine glass rim around every home-screen icon – a hint of it here.
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.06), .white.opacity(0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: max(0.5, size / 90))
            }
            .accessibilityHidden(true)
    }
}
