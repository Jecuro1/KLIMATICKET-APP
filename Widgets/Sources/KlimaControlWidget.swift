import WidgetKit
import SwiftUI
import AppIntents

/// Control Center / lock screen / Action button control: opens KlimaBilanz on "Fahrt erfassen".
struct KlimaControlWidget: ControlWidget {
    static let kind = "com.knitelarlberg.klimabilanz.control.addTrip"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenAddTripIntent()) {
                Label("Fahrt erfassen", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Fahrt erfassen")
        .description("Öffnet KlimaBilanz direkt beim Erfassen einer neuen Fahrt.")
    }
}
