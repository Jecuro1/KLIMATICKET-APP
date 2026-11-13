import SwiftUI
import KlimaCore

// MARK: commute – CI scenes of the Pendel-Modus (`-KBScreenshot <screen> -KBDemo YES`): a pinned clock, synthetic connections
// (CommuteFixture), no network, no system alert.
// - `commuteSetup`: the invitation „Ist das dein Arbeitsweg?“ (mode off, a confident guess)
// - `commuteMorning`: the live window at 07:04 – three connections, a changed platform, the age of the data
// - `commuteDelayed`: the first train 12 minutes late, the faster connection named · `commuteAX5`: the same at the largest text size,
//   `commuteAX5Rows` scrolled to its rows, `commuteAX5Bottom` to the stacked buttons
// - `commuteCancelled`: the first train cancelled, the next connection named
// - `commuteNoConsent`: live data not decided yet – the plan and the offer to switch it on
// - `commuteEvening`: outside the window – „Nächste Pendelfahrt heute 17:12“
// - `commuteSettings`: Einstellungen › Pendeln with the suggestion ticked · `commuteSettingsBottom`: its lower part (times, Siri)

struct CommuteScreenshotHost: View {
    static let screens: Set<String> = [
        "commuteSetup", "commuteMorning", "commuteDelayed", "commuteCancelled", "commuteNoConsent", "commuteEvening", "commuteAX5",
        "commuteAX5Rows", "commuteAX5Bottom", "commuteSettings", "commuteSettingsBottom",
    ]

    let screen: String

    var body: some View {
        let scene = CommuteFixture.scene(screen)
        Group {
            if screen.hasPrefix("commuteSettings") {
                NavigationStack {
                    CommuteSettingsPage(previewCandidates: scene.guess.map { [$0] } ?? [], screenshotScrollsDown: screen.hasSuffix("Bottom"))
                }
            } else {
                overview
            }
        }
        .defaultScrollAnchor(anchor)
        .defaultScrollAnchor(anchor, for: .sizeChanges)   // the rows arrive after the first frame
        .dynamicTypeSize(screen.hasPrefix("commuteAX5") ? .accessibility5 : .large)
        .onAppear { CommuteModel.shared.install(scene) }
    }

    /// `…Bottom` scenes open scrolled to the end, `commuteAX5Rows` to the middle (the rows at the largest text size).
    private var anchor: UnitPoint? {
        if screen.hasSuffix("Bottom") { return .bottom }
        if screen.hasSuffix("Rows") { return .center }
        return nil
    }

    /// The top of the Übersicht with the card under the header (on the device it sits above „Schnell erfassen“).
    private var overview: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker(text: Format.weekdayDayMonth(CommuteFixture.scene(screen).now))
                        Text("Übersicht").font(Theme.Typography.heroTitle).foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, Theme.Spacing.cardGutter + DashStyle.headerInset)
                    .padding(.top, Theme.Spacing.m)
                    CommuteCardSection(trips: [], savedRoutes: [])
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background { Color.clear.ambientBackground() }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }
}
