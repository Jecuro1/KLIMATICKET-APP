import SwiftUI
import SwiftData
import KlimaCore

/// „Fragen an KlimaBilanz“ is reachable (Einstellungen › KI & Siri, the App Shortcut, the action in the Kurzbefehle-App) once the
/// screen and Siri's snippet were looked at in screenshots; `false` hides all three again.
enum SiriQuestionsRelease {
    static let isLive = false
}

/// CI screenshot routes of „Fragen an KlimaBilanz“ (`-KBScreenshot <screen> -KBDemo YES`, demo year, no network):
/// - `siriQuestions`: the page – opening, „Probier es aus“ with Fahrten · Dieser Monat
/// - `siriAnswer`: „Wert deiner Fahrten · Letzter Monat“ in the tester and „So fragst du“ below it
/// - `siriAX5`: the page at the largest accessibility text size
/// - `siriSnippets`: what Siri shows for five answers (a month's days, a year's months, a ticket's days, the break-even, no table yet)
struct SiriScreenshotHost: View {
    static let screens: Set<String> = ["siriQuestions", "siriAnswer", "siriAX5", "siriSnippets"]

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
            NavigationStack { SiriQuestionsView(question: .value, period: .lastMonth) }
                .defaultScrollAnchor(UnitPoint(x: 0.5, y: 0.32))
        case "siriSnippets":
            SiriSnippetGallery(table: SiriKpiWriter.makeTable(Repository(context: context, app: app)))
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
