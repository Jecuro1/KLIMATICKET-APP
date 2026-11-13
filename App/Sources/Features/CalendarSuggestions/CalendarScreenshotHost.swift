import SwiftUI
import KlimaCore

// MARK: calendarsuggestions – CI scenes of Kalender-Vorschläge (`-KBScreenshot <screen> -KBDemo YES`): the fake calendar
// (`CalendarDemoEvents`, twelve fictional events), a pinned clock (Thu, 19 Nov 2026, 08:12), no EventKit, no system alert, no network.
// - `calendarSuggestions`: the Übersicht with the three cards · `calendarAX5`: the same at the largest text size, `calendarAX5Bottom`
//   scrolled to the stacked buttons
// - `calendarWasYouThere`: „Warst du gefahren? Innsbruck Hbf“ above the cards
// - `calendarSettings` (`…Bottom` scrolled down): Einstellungen › Kalender-Vorschläge, active, with the calendars and the buffer
// - `calendarDenied`, `calendarRestricted`, `calendarWriteOnly`, `calendarNeedsPermission`, `calendarEmpty` (granted, no calendar):
//   the page in each permission state
// - `calendarExplain`: the explanation before the system question · `calendarPicker`: the calendar picker after the grant

struct CalendarScreenshotHost: View {
    static let screens: Set<String> = [
        "calendarSuggestions", "calendarAX5", "calendarAX5Bottom", "calendarWasYouThere", "calendarSettings", "calendarSettingsBottom",
        "calendarDenied", "calendarRestricted", "calendarWriteOnly", "calendarNeedsPermission", "calendarEmpty", "calendarExplain",
        "calendarPicker",
    ]

    let screen: String
    @Environment(AppState.self) private var app
    @State private var isReady = false

    private static let calendarIDs = [CalendarDemoEvents.workCalendarID, CalendarDemoEvents.homeCalendarID]

    var body: some View {
        Group {
            if isReady { content } else { Color.clear.ambientBackground() }
        }
        .dynamicTypeSize(screen.hasPrefix("calendarAX5") ? .accessibility5 : .large)
        .onAppear { install() }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case "calendarSuggestions", "calendarAX5", "calendarAX5Bottom", "calendarWasYouThere":
            overview
        case "calendarExplain":
            CalendarExplainSheet(onContinue: {}, onCancel: {})
        case "calendarPicker":
            NavigationStack { CalendarPickerSheet() }
        default:
            NavigationStack { CalendarSettingsPage(screenshotScrollsDown: screen.hasSuffix("Bottom")) }
        }
    }

    /// The top of the Übersicht with the section under the header (on the device it sits below the Fahrten-Vorschläge).
    private var overview: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker(text: Format.weekdayDayMonth(CalendarDemoEvents.now))
                        Text("Übersicht").font(Theme.Typography.heroTitle).foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, Theme.Spacing.cardGutter + DashStyle.headerInset)
                    .padding(.top, Theme.Spacing.m)
                    CalendarSuggestionsSection(trips: [], isScreenshotScene: true)
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .defaultScrollAnchor(screen.hasSuffix("Bottom") ? .bottom : nil)
            .defaultScrollAnchor(screen.hasSuffix("Bottom") ? .bottom : nil, for: .sizeChanges)
            .background { Color.clear.ambientBackground() }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }

    private func install() {
        let store = CalendarSuggestionStore.shared
        switch screen {
        case "calendarDenied": store.installDemo(access: .denied, enabled: true, calendarIDs: Self.calendarIDs)
        case "calendarRestricted": store.installDemo(access: .restricted, enabled: true, calendarIDs: Self.calendarIDs)
        case "calendarWriteOnly": store.installDemo(access: .writeOnly, enabled: true, calendarIDs: Self.calendarIDs)
        case "calendarNeedsPermission": store.installDemo(access: .notDetermined, enabled: true, calendarIDs: [])
        case "calendarEmpty": store.installDemo(access: .fullAccess, enabled: true, calendarIDs: [], calendars: [], events: [])
        case "calendarExplain": store.installDemo(access: .notDetermined, enabled: false, calendarIDs: [])
        case "calendarPicker": store.installDemo(access: .fullAccess, enabled: true, calendarIDs: [CalendarDemoEvents.workCalendarID])
        case "calendarSettings", "calendarSettingsBottom":
            store.installDemo(access: .fullAccess, enabled: true, calendarIDs: Self.calendarIDs)
        case "calendarWasYouThere":
            // Yesterday's card for Innsbruck: no trip was logged there.
            let yesterday = CalendarDemoEvents.now.addingTimeInterval(-86_400)
            let arrival = Calendar.vienna.date(bySettingHour: 9, minute: 40, second: 0, of: yesterday) ?? yesterday
            store.installDemo(access: .fullAccess, enabled: true, calendarIDs: Self.calendarIDs,
                              followUps: ["demo-followup": CalendarFollowUpEntry(stationID: "at:47:1187", stationName: "Innsbruck Hauptbahnhof",
                                                                                 arrival: arrival)])
        default:
            store.installDemo(access: .fullAccess, enabled: true, calendarIDs: Self.calendarIDs)
        }
        store.refresh(trips: [], stations: app.stations, homeStationID: nil)
        isReady = true
    }
}
