import SwiftUI
import SwiftData
import KlimaCore

/// „Fragen an KlimaBilanz“ is reachable from Einstellungen › KI & Siri since the page and Siri's snippet were looked at in two
/// screenshot runs (723, 724); `false` hides the row again (the App Shortcut and the Kurzbefehle action go with `isDiscoverable` in
/// AskKlimaIntent and the entry in Shortcuts.swift).
enum SiriQuestionsRelease {
    static let isLive = true
}

/// CI screenshot routes of „Fragen an KlimaBilanz“ (`-KBScreenshot <screen> -KBDemo YES`, demo year, no network):
/// - `siriQuestions`: the page – opening, „Probier es aus“ with Fahrten · Dieser Monat
/// - `siriAnswer`: „Wert deiner Fahrten · Letzter Monat“ in the tester (scrolled to it), „So fragst du“ below
/// - `siriExamples`: „So fragst du“ with the eight questions; `siriBottom`: Kurzbefehle and Datenschutz
/// - `siriAX5` / `siriAX5Mid`: the opening and the tester at the largest accessibility text size
/// - `siriSnippets` / `siriSnippetsEnd`: what Siri shows for five answers (a month's days, a year's months, a ticket's days, the
///   break-even, no table yet), top and end
/// - `siriSettings`: the section „KI & Siri“ of Einstellungen with the row „Fragen an KlimaBilanz“ (as SettingsView draws it)
/// - MARK: review-siri – `siriAX5Answer`: Siri's platter in the tester at AX5 (scrolled to its end); `siriSnippetsMid`: the
///   gallery's middle – Fahrten im Ticketjahr (the ticket's months only) with one Fahrt still queued from a widget
struct SiriScreenshotHost: View {
    static let screens: Set<String> = ["siriQuestions", "siriAnswer", "siriExamples", "siriBottom", "siriAX5", "siriAX5Mid",
                                       "siriSnippets", "siriSnippetsEnd", "siriSettings",
                                       "siriAX5Answer", "siriSnippetsMid"]   // MARK: review-siri

    let screen: String

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        content
            .dynamicTypeSize(screen.contains("AX5") ? .accessibility5 : .large)
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case "siriAnswer":
            NavigationStack { SiriQuestionsView(question: .value, period: .lastMonth, screenshotAnchor: .tester) }
        case "siriExamples":
            NavigationStack { SiriQuestionsView(question: .co2, period: .ticketYear, screenshotAnchor: .examples) }
        case "siriBottom":
            NavigationStack { SiriQuestionsView(screenshotAnchor: .end) }
        case "siriAX5Mid":
            NavigationStack { SiriQuestionsView(question: .daysLeft, period: .ticketYear, screenshotAnchor: .tester) }
        case "siriAX5Answer":   // MARK: review-siri
            NavigationStack { SiriQuestionsView(question: .value, period: .thisMonth, screenshotAnchor: .answer) }
        case "siriSnippets", "siriSnippetsEnd", "siriSnippetsMid":
            SiriSnippetGallery(table: SiriKpiWriter.makeTable(Repository(context: context, app: app)))
                .defaultScrollAnchor(screen == "siriSnippetsEnd" ? .bottom : screen == "siriSnippetsMid" ? .center : .top)
        case "siriSettings":
            NavigationStack {
                List { SetAssistantSection() }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(Theme.Spacing.l)
                    .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
                    .scrollContentBackground(.hidden)
                    .background { SetBackdrop() }
                    .navigationTitle("Einstellungen")
                    .navigationBarTitleDisplayMode(.inline)
            }
        default:
            NavigationStack { SiriQuestionsView() }
        }
    }
}

/// Siri's platter for several answers at once, on the app's background (Siri itself cannot be captured in CI).
private struct SiriSnippetGallery: View {
    let table: KpiDailyTable

    var body: some View {
        let now = Date()
        let answers: [(String?, KpiAnswer)] = [
            (AskKlimaPhrase.spoken(.value, .lastMonth), KpiAnswer.make(.value, period: .lastMonth, table: table, now: now)),
            (AskKlimaPhrase.spoken(.co2, .calendarYear), KpiAnswer.make(.co2, period: .calendarYear, table: table, now: now)),
            // MARK: review-siri – the ticket's months (April from the 12th) and a Fahrt a widget queued an hour ago
            (AskKlimaPhrase.spoken(.trips, .ticketYear),
             KpiAnswer.make(.trips, period: .ticketYear, table: table, now: now, pending: [now.addingTimeInterval(-3_600)])),
            (AskKlimaPhrase.spoken(.daysLeft, .ticketYear), KpiAnswer.make(.daysLeft, period: .ticketYear, table: table, now: now)),
            (AskKlimaPhrase.spoken(.breakEven, .ticketYear), KpiAnswer.make(.breakEven, period: .ticketYear, table: table, now: now)),
            (AskKlimaPhrase.spoken(.trips, .thisWeek), KpiAnswer.make(.trips, period: .thisWeek, table: nil, now: now)),
        ]
        ScrollView {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(Array(answers.enumerated()), id: \.offset) { _, item in
                    SiriAnswerPlatter(phrase: item.0, answer: item.1)
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.vertical, Theme.Spacing.l)
        }
        .background { SetBackdrop() }
    }
}
