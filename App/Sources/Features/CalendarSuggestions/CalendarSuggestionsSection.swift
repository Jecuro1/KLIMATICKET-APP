import SwiftUI
import SwiftData
import KlimaCore

// MARK: calendarsuggestions – „Termine mit Zugfahrt?“ on the Übersicht, below the Fahrten-Vorschläge (docs/CALENDAR_SUGGESTIONS.md §2):
// up to three cards for events of the next 14 days and the „Warst du gefahren?“ follow-ups. Renders nothing (not even padding) while
// the switch is off, without read access or without a card – and nothing in other tracks' CI scenes. Reads the calendars only while
// the app is in the foreground: on appear, on return to the app, when trips change and when the calendar database changes.

struct CalendarSuggestionsSection: View {
    /// The Übersicht's trips, newest first: "already covered", the usual start and the follow-ups read them.
    var trips: [TripEntity]
    /// CI scenes draw the section without the refresh (the scene installed the store's state).
    var isScreenshotScene = false

    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    private var store: CalendarSuggestionStore { .shared }

    /// Shown in normal runs and in this track's own CI scenes only.
    static var isAllowedHere: Bool {
        guard LaunchMode.isSandboxed else { return true }
        return CalendarScreenshotHost.screens.contains(LaunchMode.screenshotScreen ?? "")
    }

    private var hasContent: Bool {
        store.setupState.showsSuggestions && !(store.suggestions.isEmpty && store.followUps.isEmpty)
    }

    var body: some View {
        Group {
            if Self.isAllowedHere, hasContent {
                content
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.top, DashStyle.sectionSpacing)
                    .reveal(order: 4)   // with the Fahrten-Vorschläge, in reading order (docs/MOTION.md §4)
                    .motionTransition(.rise)
            }
        }
        .motionAnimation(Motion.smooth, value: store.suggestions.map(\.id) + store.followUps.map(\.id))
        .task(id: RefreshKey(trips: trips.count, newest: trips.first?.updatedAt, enabled: store.prefs.isEnabled,
                             active: scenePhase == .active)) {
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: CalendarSuggestionStore.changeNotification).receive(on: RunLoop.main)) { _ in
            guard scenePhase == .active else { return }
            refresh()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DashStyle.cardSpacing) {
            // At accessibility sizes the header's link would outgrow its title: „Anpassen“ moves under the cards.
            SectionHeader(title: "Termine mit Zugfahrt?", actionTitle: typeSize.isAccessibilitySize ? nil : "Anpassen") {
                store.showsSettingsSheet = true
            }
            .padding(.horizontal, DashStyle.headerInset)
            ForEach(store.followUps) { followUp in
                CalendarFollowUpCard(followUp: followUp, now: store.now())
                    .motionTransition(.rise)
            }
            ForEach(store.suggestions) { suggestion in
                CalendarSuggestionCard(suggestion: suggestion, now: store.now())
                    .id(suggestion.id + "|\(suggestion.bufferMinutes)")
                    .motionTransition(.rise)
            }
            Label("Aus deinem Kalender, nur auf diesem iPhone gelesen", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, DashStyle.headerInset)
            if typeSize.isAccessibilitySize {
                Button("Kalender-Vorschläge anpassen") { store.showsSettingsSheet = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, DashStyle.headerInset)
            }
        }
    }

    /// Reads the calendars and plans the cards – only in the foreground, only with the switch on (otherwise nothing is touched).
    private func refresh() {
        guard !isScreenshotScene, Self.isAllowedHere || !LaunchMode.isSandboxed else { return }
        guard scenePhase == .active, store.prefs.isEnabled else { return }
        let recent = trips.prefix(80).filter { $0.deletedAt == nil }.map(\.record)
        store.refresh(trips: recent, stations: app.stations, homeStationID: app.settings.homeStationID)
    }
}

private struct RefreshKey: Hashable {
    var trips: Int
    var newest: Date?
    var enabled: Bool
    var active: Bool
}

// MARK: - Settings sheet host

extension View {
    /// klimabilanz://calendar and the section's „Anpassen“: Einstellungen › Kalender-Vorschläge as a sheet. Put on the root, once.
    func calendarSettingsHost() -> some View { modifier(CalendarSettingsHost()) }
}

private struct CalendarSettingsHost: ViewModifier {
    @State private var store = CalendarSuggestionStore.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: $store.showsSettingsSheet) {
            NavigationStack { CalendarSettingsPage(isSheet: true) }
        }
    }
}
