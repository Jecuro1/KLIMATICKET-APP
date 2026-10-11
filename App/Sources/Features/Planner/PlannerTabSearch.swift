import SwiftUI

/// The Fahrplan's search field (docs/OEBB_LIVE.md §E1): on iOS 26 the search-role tab turns the tab bar into a search
/// field. `.searchable` sits on the `TabView`; `isSearching` and `dismissSearch` reach the planner inside the tab. The
/// model's `isSearchFocused` opens the keyboard when a slot of the search card is tapped.
/// With `PlannerModel.navigationStyle == .plainTab` (fallback R4) the planner has its own field and this does nothing.
struct PlannerTabSearch: ViewModifier {
    @Environment(AppState.self) private var app
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        @Bindable var planner = app.planner
        if PlannerModel.navigationStyle == .searchTab {
            content
                .searchable(text: $planner.query, prompt: Text(planner.searchPrompt))
                .searchFocused($focused)
                .tabViewSearchActivation(.automatic)   // the field waits in the tab bar until it is tapped (searchTabSelection would open it at once)
                .onChange(of: planner.isSearchFocused) { _, wanted in
                    if focused != wanted { focused = wanted }
                }
                .onChange(of: focused) { _, now in
                    if planner.isSearchFocused != now { planner.isSearchFocused = now }
                }
        } else {
            content
        }
    }
}

extension View {
    /// MARK: planner – the search-role tab's field.
    func plannerTabSearch() -> some View { modifier(PlannerTabSearch()) }
}
