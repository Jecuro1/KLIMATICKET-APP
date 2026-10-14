import WidgetKit
import SwiftUI
import AppIntents
import KlimaCore

// Controls for Control Center, the Lock Screen and the Action button (docs/WIDGETS.md §4.2, item 9). They open the app at
// a screen (deep links) or switch the live follow; no control fetches anything itself.

/// "Zug-Radar öffnen": the live map of the trains that are under way.
struct RadarControl: ControlWidget {
    static let kind = WidKind.radarControl

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(WidDeepLink.radar)) {
                Label("Zug-Radar", systemImage: "dot.radiowaves.left.and.right")
            }
            .tint(Theme.glacier)
        }
        .displayName("Zug-Radar öffnen")
        .description("Öffnet KlimaBilanz beim Zug-Radar: welche Züge gerade unterwegs sind.")
    }
}

/// "Verbindung suchen": the Fahrplan, ready for a new search.
struct SearchControl: ControlWidget {
    static let kind = WidKind.searchControl

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(WidDeepLink.planner)) {
                Label("Verbindung suchen", systemImage: "magnifyingglass")
            }
            .tint(Theme.accent)
        }
        .displayName("Verbindung suchen")
        .description("Öffnet den Fahrplan von KlimaBilanz für eine neue Verbindung.")
    }
}

/// "Live verfolgen": on while the app follows a train. Turning it on opens the Zug-Radar to choose one; turning it off
/// stops the follow in the app.
struct LiveFollowControl: ControlWidget {
    static let kind = WidKind.liveFollowControl

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: LiveFollowValueProvider()) { isOn in
            ControlWidgetToggle("Live verfolgen", isOn: isOn, action: LiveFollowSetIntent()) { on in
                Label(on ? "Live verfolgt" : "Live verfolgen", systemImage: on ? "location.fill" : "location")
            }
            .tint(Theme.live)
        }
        .displayName("Live verfolgen")
        .description("Schaltet die Live-Verfolgung eines Zugs ein oder aus. Zum Einschalten wählst du den Zug im Zug-Radar.")
    }
}

/// The toggle's state: the live follow the app mirrored into the App Group (`WidgetCacheKey.liveFollowActive`).
struct LiveFollowValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        WidgetCache.liveFollowActive
    }
}
