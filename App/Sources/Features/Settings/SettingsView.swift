import SwiftUI
import SwiftData
import KlimaCore

/// Einstellungen (DESIGN.md §5.7): grouped list with coloured icon tiles on a pale alpine sky.
/// Lives inside a NavigationStack provided by the presenter; shows "Fertig" only when presented as a sheet.
/// Like every other main screen it carries its own header (eyebrow + large title at the 20 pt text margin)
/// instead of the system large title, which would sit 4 pt further left than the rest of the app.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented

    /// The update sheet is presented from here (not from a lazily loaded list row, and not from RootView,
    /// which cannot show a second sheet while Settings is up).
    @State private var showsUpdateSheet = false
    /// The inline nav-bar title fades in once the custom header has scrolled away.
    @State private var showsInlineTitle = false

    /// Sheet from the dashboard avatar (`app.isShowingSettings`) or any other modal presentation.
    private var showsDoneButton: Bool { app.isShowingSettings || isPresented }

    var body: some View {
        List {
            SetScreenHeader(kicker: headerKicker, title: "Einstellungen")
            SetAccountSection()
            SetFareSection()
            SetCaptureSection()
            SetAppearanceSection()
            SetNotificationsSection()
            SetUpdatesSection(showsUpdateSheet: $showsUpdateSheet)
            SetDataSection()
            SetAboutSection()
            SetSignOutSection()
            SetBrandFooterSection()
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop() }
        .tint(Theme.accent)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 56
        } action: { _, isScrolled in
            withAnimation(.easeInOut(duration: 0.2)) { showsInlineTitle = isScrolled }
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Einstellungen")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .opacity(showsInlineTitle ? 1 : 0)
                .accessibilityHidden(!showsInlineTitle)
        }
        // iOS 26 wraps custom toolbar views in a shared glass capsule – it would stay visible as an
        // empty pill while the title is faded out (same as Übersicht and Statistik).
        .sharedBackgroundVisibility(.hidden)
        if showsDoneButton {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }
                    .fontWeight(.semibold)
            }
        }
    }

    /// "SERVUS, LENA" for a signed-in profile (CI screenshots use the demo holder), else the app version.
    private var headerKicker: String {
        let profile = app.auth.profile ?? (LaunchMode.isScreenshot ? SetDemo.profile : nil)
        // Placeholder names from AuthService ("Du", "Konto", "Apple-Konto") or an e-mail make a poor greeting.
        let placeholders: Set<String> = ["Du", "Konto", "Apple-Konto"]
        if let name = profile?.displayName, !placeholders.contains(name), !name.contains("@"),
           let first = name.split(separator: " ").first {
            return "Servus, \(first)"
        }
        return "KlimaBilanz · Version \(AppConfig.appVersion)"
    }
}
