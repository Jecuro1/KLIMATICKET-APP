import WidgetKit
import SwiftUI

/// KlimaBilanz widget extension: home & lock-screen amortisation, interactive quick log and the
/// Control Center "Fahrt erfassen" button. All widget views live in Shared/WidgetViews (also used by the app's gallery).
@main
struct KlimaBilanzWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AmortizationWidget()
        QuickLogWidget()
        KlimaControlWidget()
        RideLiveActivity()  // MARK: live
    }
}
