import SwiftUI
import SwiftData
import KlimaCore

/// Einstellungen (DESIGN.md §5.7): grouped list with coloured icon tiles on a pale alpine sky.
/// Lives inside a NavigationStack provided by the presenter; shows "Fertig" only when presented as a sheet.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented

    /// Sheet from the dashboard avatar (`app.isShowingSettings`) or any other modal presentation.
    private var showsDoneButton: Bool { app.isShowingSettings || isPresented }

    var body: some View {
        List {
            SetAccountSection()
            SetFareSection()
            SetDetectionSection()
            SetAppearanceSection()
            SetNotificationsSection()
            SetUpdatesSection()
            SetDataSection()
            SetAboutSection()
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop() }
        .tint(Theme.accent)
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
