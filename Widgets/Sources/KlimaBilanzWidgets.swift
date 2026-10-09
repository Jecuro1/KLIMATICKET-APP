import WidgetKit
import SwiftUI

/// KlimaBilanz widget extension: home & lock-screen amortisation, interactive quick log, the controls "Fahrt erfassen"
/// and "Lieblingsfahrt erfassen" (Control Center, Lock Screen, Action button) and the "Unterwegs" Live Activity.
/// All widget views live in Shared/WidgetViews (also used by the app's gallery).
@main
struct KlimaBilanzWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AmortizationWidget()
        QuickLogWidget()
        KlimaControlWidget()
        KlimaFavoriteControl()
        RideLiveActivity()  // MARK: live
    }
}
