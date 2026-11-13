import SwiftUI
import KlimaCore

// MARK: themes – the one moment Look & Feel reaches the screens (docs/THEMES.md §4): Einstellungen has closed, its dismissal
// has run, then the tab interface is built again under one cross-fade (`Motion.smooth`; none at Bewegung „Aus“ or in a
// screenshot run). RootView carries `.appearanceSwitchHost()` and gives MainTabView the id `app.settings.look.revision`.

extension View {
    func appearanceSwitchHost() -> some View {
        modifier(AppearanceSwitchHost())
    }
}

private struct AppearanceSwitchHost: ViewModifier {
    @Environment(AppState.self) private var app

    /// The sheet's dismissal animation (the same pause RootView waits before an alert).
    private static let dismissal: Duration = .milliseconds(450)

    func body(content: Content) -> some View {
        content
            .onChange(of: app.isShowingSettings) { _, isShowing in
                guard !isShowing, app.settings.look.hasPendingChanges else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: Self.dismissal)
                    // Opened again in the meantime: wait for the next close.
                    guard !app.isShowingSettings else { return }
                    withMotion(Motion.smooth) { _ = app.settings.look.applyPending() }
                }
            }
    }
}
