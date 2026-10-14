import WidgetKit
import SwiftUI

/// KlimaBilanz widget extension: home & lock-screen amortisation, interactive quick log, the controls "Fahrt erfassen"
/// and "Lieblingsfahrt erfassen" (Control Center, Lock Screen, Action button) and the "Unterwegs" Live Activity.
/// Widget track (docs/WIDGETS.md): nächste Verbindung, Abfahrten, Störungen, Ticket-Restzeit, Break-even, Jahresrückblick,
/// Fahrten-Kalender, Gipfel-Fortschritt; controls Zug-Radar, Verbindung suchen, Live verfolgen.
/// All widget views live in Shared/WidgetViews (also used by the app's gallery).
@main
struct KlimaBilanzWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AmortizationWidget()
        QuickLogWidget()
        NextConnectionWidget()
        DeparturesWidget()
        DisruptionsWidget()
        TicketRemainingWidget()
        BreakEvenWidget()
        YearReviewWidget()
        HeatmapWidget()
        SummitWidget()
        KlimaControlWidget()
        KlimaFavoriteControl()
        RadarControl()
        SearchControl()
        LiveFollowControl()
        RideLiveActivity()  // MARK: live
        FollowLiveActivity()  // MARK: follow – "Live verfolgen" (docs/OEBB_LIVE.md §R8)
    }
}
