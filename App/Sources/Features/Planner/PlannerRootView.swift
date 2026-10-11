import SwiftUI
import KlimaCore

/// Root of the Fahrplan tab.
struct PlannerRootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Kicker(text: Format.weekdayDayMonth(Date()))
                    Text("Fahrplan").font(Theme.Typography.heroTitle).accessibilityAddTraits(.isHeader)
                    if app.live.consent == .undecided { LiveConsentCard() }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.top, Theme.Spacing.l)
            }
            .ambientBackground()
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }
}
