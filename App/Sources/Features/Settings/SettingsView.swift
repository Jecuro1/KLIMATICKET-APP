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

    /// CI screenshots of the lower parts of the long list (`-KBScreenshot settings2 | settings3 | settingsEnd`).
    var screenshotScreen: String? = nil

    /// Sheet from the dashboard avatar (`app.isShowingSettings`) or any other modal presentation.
    private var showsDoneButton: Bool { app.isShowingSettings || isPresented }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                SetAccountSection(screenHeader: SetScreenHeader(kicker: headerKicker, title: "Einstellungen"))
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
            .task { await scrollForScreenshot(proxy) }
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

    private func scrollForScreenshot(_ proxy: ScrollViewProxy) async {
        let target: (anchor: SetScrollAnchor, position: UnitPoint)
        switch screenshotScreen {
        case "settings2": target = (.appearance, .center)
        case "settings3": target = (.data, .center)
        case "settingsEnd": target = (.end, .bottom)
        default: return
        }
        try? await Task.sleep(for: .milliseconds(400))
        proxy.scrollTo(target.anchor, anchor: target.position)
    }

    /// What the screen holds, like the informational eyebrows of the other screens ("TICKETJAHR 2026/27").
    /// A greeting would only repeat the name shown on the profile card right below.
    private var headerKicker: String { "Konto, App & Daten" }
}

/// Row ids the CI screenshots scroll to (`SettingsView.screenshotScreen`).
enum SetScrollAnchor: Hashable {
    case appearance, data, end
}
