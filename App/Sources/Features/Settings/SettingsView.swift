import SwiftUI
import SwiftData
import KlimaCore

/// Einstellungen (DESIGN.md §5.7): grouped list with coloured icon tiles on a pale alpine sky.
/// Lives inside a NavigationStack provided by the presenter; shows "Fertig" only when presented as a sheet.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented

    /// The update sheet is presented from here (not from a lazily loaded list row, and not from RootView,
    /// which cannot show a second sheet while Settings is up).
    @State private var showsUpdateSheet = false

    /// Sheet from the dashboard avatar (`app.isShowingSettings`) or any other modal presentation.
    private var showsDoneButton: Bool { app.isShowingSettings || isPresented }

    var body: some View {
        List {
            SetAccountSection()
            SetFareSection()
            WorkSettingsSection()
            SetDetectionSection()
            SetAppearanceSection()
            SetNotificationsSection()
            SetUpdatesSection(showsUpdateSheet: $showsUpdateSheet)
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
        .overlay(alignment: .top) {
            // RootView's global toast sits underneath this sheet – mirror it here so feedback from settings
            // ("Backup wiederhergestellt", "Tarife aktualisiert", …) is visible. Not needed when shown inline.
            if showsDoneButton {
                ToastOverlay()
            }
        }
        .sheet(isPresented: $showsUpdateSheet) {
            UpdateSheet()
        }
        .onChange(of: app.updates.isPresentingSheet) { _, presenting in
            // An automatic check (e.g. returning to the foreground) found an update while the Settings sheet is up:
            // RootView cannot present on top of it, so take over the presentation here.
            guard presenting, app.isShowingSettings else { return }
            app.updates.isPresentingSheet = false
            showsUpdateSheet = true
        }
    }
}
