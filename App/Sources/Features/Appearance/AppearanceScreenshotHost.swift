import SwiftUI
import KlimaCore

// MARK: themes – CI screenshot scenes of Look & Feel (demo data, no network, no system alert). Each scene's choices come from
// `AppearanceLaunch.screenshotPrefs` – applied at launch like `-KBTheme`, never stored.
//   themeSettings      Look & Feel, top (Gletscher)
//   themeGallery       the six palette cards (Zirbe chosen)
//   themeOptions       Bewegung, Haptik, Zahlen (Graphit, Ruhig, Dezent, Cent, Sonntag, kg)
//   themeAX5           Look & Feel at the largest text size (Morgenrot)
//   themeAX5Lower      the same, scrolled to the palettes
//   themeDash          Übersicht in Zirbe
//   themeStats         Statistik in Morgenrot
//   themeStatsFormat   Statistik with Cent, Sonntag and kg (Gletscher)
//   themeStatsWeek     the same, scrolled to the calendar and the weekday chart
//   themeDashWeek      Übersicht scrolled to the week card, week from Sunday
//   themeTicket        Ticket in Dämmerung
//   themeSettingsRow   Einstellungen › Darstellung with the Look & Feel row (Alpenglühen)
//   themeIcon          App-Symbol with the "Passendes Theme" suggestion

struct AppearanceScreenshotHost: View {
    static let screens: Set<String> = ["themeSettings", "themeGallery", "themeOptions", "themeAX5", "themeAX5Lower", "themeDash",
                                       "themeDashWeek", "themeStats", "themeStatsFormat", "themeStatsWeek", "themeTicket",
                                       "themeSettingsRow", "themeIcon"]

    let screen: String
    @Environment(AppState.self) private var app

    var body: some View {
        content
            .onAppear {
                // Screenshot runs switch haptics off before any scene starts; the scenes show the level they are about.
                app.settings.look.prefs.haptics = AppearanceLaunch.screenshotPrefs(for: screen)?.haptics ?? .full
            }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case "themeDash", "themeDashWeek":
            MainTabView().onAppear { app.selectedTab = .overview }
        case "themeStats", "themeStatsFormat", "themeStatsWeek":
            MainTabView().onAppear { app.selectedTab = .stats }
        case "themeTicket":
            MainTabView().onAppear { app.selectedTab = .ticket }
        case "themeSettingsRow":
            NavigationStack { SettingsView(screenshotScreen: "settings2") }
        case "themeIcon":
            NavigationStack { AppIconPickerView(screenshotChoice: .nacht) }
        case "themeGallery":
            NavigationStack { AppearanceView(screenshotSection: .palettes) }
        case "themeOptions":
            NavigationStack { AppearanceView(screenshotSection: .motion) }
        case "themeAX5":
            NavigationStack { AppearanceView() }
                .dynamicTypeSize(.accessibility5)
        case "themeAX5Lower":
            NavigationStack { AppearanceView(screenshotSection: .palettes) }
                .dynamicTypeSize(.accessibility5)
        default:
            NavigationStack { AppearanceView() }
        }
    }
}
