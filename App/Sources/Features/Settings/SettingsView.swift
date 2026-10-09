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
    /// Scroll progress of the header: it condenses while the inline nav-bar title fades in. Only the header and the
    /// title read it, so scrolling never re-renders the list itself.
    @State private var condense = ScrollCondense()

    /// CI screenshots of the lower parts of the long list (`-KBScreenshot settings2 | settings3 | settingsDemo | settingsEnd`).
    var screenshotScreen: String? = nil

    /// Sheet from the dashboard avatar (`app.isShowingSettings`) or any other modal presentation.
    private var showsDoneButton: Bool { app.isShowingSettings || isPresented }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                SetAccountSection(screenHeader: SetScreenHeader(kicker: headerKicker, title: "Einstellungen", condense: condense))
                SetFareSection()
                WorkSettingsSection() // MARK: work – "Arbeit & Steuer", "Auto-Vergleich"
                PerkSettingsSection() // MARK: benefits
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
            // One entrance per opening: the header and the profile card rise in (docs/MOTION.md §4); rows that
            // scroll in later are simply there.
            .revealScope()
            .tracksScrollCondense(condense, distance: 64)
            .task { await scrollForScreenshot(proxy) }
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
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
            SetInlineTitle(title: "Einstellungen", condense: condense)
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
        case "settings3", "settingsDemo": target = (.data, .center)
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

/// Einstellungen as the dashboard's sheet: its own NavigationStack with the toast mirrored above it. RootView's global
/// toast sits underneath the sheet, and an overlay on the list itself would vanish on every pushed page ("Favorit
/// gelöscht" in Favoriten verwalten, a quick log from Widgets & Kurzbefehle) – above the stack it covers all of them.
struct SettingsSheet: View {
    /// The sheet's inline navigation bar ("Fertig", the fading title): the toast sits right below it instead of
    /// covering the button.
    private static let navigationBarClearance: CGFloat = 56

    var body: some View {
        NavigationStack { SettingsView() }
            .overlay(alignment: .top) {
                ToastOverlay(playsHaptic: false)
                    .padding(.top, Self.navigationBarClearance)
            }
    }
}

/// Row ids the CI screenshots scroll to (`SettingsView.screenshotScreen`).
enum SetScrollAnchor: Hashable {
    case appearance, data, end
}
