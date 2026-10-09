import SwiftUI
import KlimaCore

/// Design QA screen (CI screenshot "benefitCard"): the module's entry cards as they sit at the bottom of the
/// Übersicht and Ticket screens – which a one-screen screenshot of those tabs never reaches.
struct PerkEntryPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PerkStyle.cardSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Kicker(text: "Übersicht · Ticket")
                    Text("Vorteile")
                        .font(Theme.Typography.heroTitle)
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                .padding(.bottom, Theme.Spacing.xs)

                PerkSummaryCard()
                PerkRightsTeaserCard {}
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xxs)
        }
        .ambientBackground(.standard, glow: 0.6)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}

/// Design QA screen (CI screenshot "benefitSettings"): the "Vorteilswelt" settings section in the settings list style.
struct PerkSettingsPreview: View {
    var body: some View {
        List {
            PerkSettingsSection()
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop() }
        .tint(Theme.accent)
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.large)
    }
}
