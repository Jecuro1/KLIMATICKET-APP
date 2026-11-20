import SwiftUI
import SwiftData
import AppIntents
import KlimaCore

// MARK: siri – Einstellungen › KI & Siri › „Fragen an KlimaBilanz“ (docs/SIRI_QUESTIONS.md §6): what Siri and the Kurzbefehle-App can
// be asked, „Probier es aus“ with the sentence Siri says (KpiAnswer from a table built from the data on screen, the same code the
// intent runs), how to ask, and what the answers read.

struct SiriQuestionsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var question: KpiQuestion
    @State private var period: KpiPeriod
    @State private var table: KpiDailyTable?
    @State private var isLoaded = false

    /// CI screenshots: where the list stands (`SiriScreenshotHost`).
    var screenshotAnchor: Anchor? = nil

    init(question: KpiQuestion = .trips, period: KpiPeriod = .thisMonth, screenshotAnchor: Anchor? = nil) {
        _question = State(initialValue: question)
        _period = State(initialValue: period)
        self.screenshotAnchor = screenshotAnchor
    }

    enum Anchor: Hashable { case tester, examples, end }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    SiriQuestionsHero()
                        .listRowBackground(Theme.surface)
                }

                Section {
                    choiceRow(title: "Frage", symbol: question.symbol, value: question.title) {
                        Picker("Frage", selection: $question) {
                            ForEach(KpiQuestion.allCases) { item in
                                Label(item.title, systemImage: item.symbol).tag(item)
                            }
                        }
                    }
                    choiceRow(title: "Zeitraum", symbol: "calendar", value: period.title,
                              note: question.isTicketOnly ? "Diese Frage gilt immer fürs Ticketjahr." : nil) {
                        Picker("Zeitraum", selection: $period) {
                            ForEach(KpiPeriod.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                    }
                    SiriAnswerPlatter(phrase: AskKlimaPhrase.spoken(question, period), answer: answer)
                        .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.s, bottom: Theme.Spacing.s, trailing: Theme.Spacing.s))
                        .listRowBackground(Theme.surface)
                } header: {
                    SetSectionHeader(title: "Probier es aus")
                        .id(Anchor.tester)
                } footer: {
                    SetFooter(text: "Genau diesen Satz sagt Siri – aus denselben Zahlen wie Statistik und die Übersicht.")
                }

                Section {
                    ForEach(KpiQuestion.allCases) { item in
                        exampleRow(item) {
                            withMotion(Motion.snappy) {
                                question = item
                                period = item == .trips ? .thisMonth : .ticketYear
                            }
                            withMotion(Motion.smooth) { proxy.scrollTo(Anchor.tester, anchor: .top) }
                        }
                    }
                } header: {
                    SetSectionHeader(title: "So fragst du")
                        .id(Anchor.examples)
                } footer: {
                    SetFooter(text: "Sag „… in KlimaBilanz“. Nennst du keinen Zeitraum, gilt das Ticketjahr – Siri fragt nicht nach. Für Fahrten geht auch „Wie viele Fahrten diese Woche, diesen Monat, letzten Monat oder heuer in KlimaBilanz“.")
                }

                Section {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("In der Kurzbefehle-App heißt die Aktion „Frag KlimaBilanz“. Du wählst Frage und Zeitraum, sie gibt die Zahl als Text weiter – etwa „€ 186,40“ – für eine Notiz, eine Nachricht oder eine Automation.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ShortcutsLink()
                            .shortcutsLinkStyle(.automaticOutline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, Theme.Spacing.xxs)
                    .listRowBackground(Theme.surface)
                } header: {
                    SetSectionHeader(title: "Kurzbefehle")
                }

                Section {
                    Text("Siri liest nur Tagessummen, die KlimaBilanz auf deinem iPhone ablegt: Fahrten, Wert, Kilometer und CO₂ pro Tag und die Zahlen deines Ticketjahrs. Keine Haltestellen, keine Orte, keine einzelnen Fahrten. Die Antwort entsteht auf dem iPhone. Gibst du sie in einem Kurzbefehl weiter, bestimmst du, wohin.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(Theme.surface)
                } header: {
                    SetSectionHeader(title: "Datenschutz")
                } footer: {
                    SetFooter(text: "Die Zahlen werden mit jeder gespeicherten Fahrt neu abgelegt. Ist der Stand älter als einen Tag, sagt Siri dazu, von wann er ist.")
                        .id(Anchor.end)
                }
            }
            .listStyle(.insetGrouped)
            .haptic(.selection, trigger: question)
            .haptic(.selection, trigger: period)
            .listSectionSpacing(Theme.Spacing.l)
            .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
            .scrollContentBackground(.hidden)
            .background { SetBackdrop() }
            .navigationTitle("Fragen an KlimaBilanz")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Built from the data on screen (the file Siri reads is written with the widgets; this one is never stale).
                guard !isLoaded else { return }
                table = SiriKpiWriter.makeTable(Repository(context: context, app: app))
                isLoaded = true
            }
            .task {
                guard let screenshotAnchor else { return }
                try? await Task.sleep(for: .milliseconds(400))
                proxy.scrollTo(screenshotAnchor, anchor: screenshotAnchor == .end ? .bottom : .top)
            }
        }
    }

    private var answer: KpiAnswer {
        KpiAnswer.make(question, period: period, table: isLoaded ? table : nil, now: Date())
    }

    /// A labelled choice: the title on the left, the current value as a menu on the right (stacked at accessibility sizes).
    @ViewBuilder
    private func choiceRow<P: View>(title: String, symbol: String, value: String, note: String? = nil,
                                    @ViewBuilder picker: () -> P) -> some View {
        let menu = Menu {
            picker()
        } label: {
            HStack(spacing: 4) {
                Text(value)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.accentText)
            .contentTransition(.opacity)
        }
        .accessibilityLabel(title)
        .accessibilityValue(value)
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                SetRowLabel(title: title, symbol: symbol, tint: Theme.glacier)
                menu
            } else {
                HStack(spacing: Theme.Spacing.s) {
                    SetRowLabel(title: title, symbol: symbol, tint: Theme.glacier)
                    Spacer(minLength: Theme.Spacing.xs)
                    menu
                }
            }
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .motionTransition(.rise)
            }
        }
        .motionAnimation(Motion.snappy, value: note)
        .listRowBackground(Theme.surface)
    }

    private func exampleRow(_ item: KpiQuestion, select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                SetRowLabel(title: item.title, subtitle: WidSiriPhrase.unbreakableNames("„\(AskKlimaPhrase.example(item))“"),
                            symbol: item.symbol, tint: AskKlimaPhrase.tint(item))
                Spacer(minLength: 0)
                if item == question {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.accentText)
                        .motionTransition(.pop)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.pressableCard)
        .foregroundStyle(Theme.textPrimary)
        .accessibilityLabel("\(item.title): „\(AskKlimaPhrase.example(item))“")
        .accessibilityHint("Zeigt die Antwort oben unter „Probier es aus“")
        .accessibilityAddTraits(item == question ? [.isSelected, .isButton] : .isButton)
        .listRowBackground(Theme.surface)
    }
}

/// The page's opening: a Siri-like orb in the route gradient, what this is, one example.
private struct SiriQuestionsHero: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.m))
        layout {
            orb
            VStack(alignment: .leading, spacing: 6) {
                Text("Frag Siri nach deinen Zahlen")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Fahrten, Wert, Kilometer, CO₂ und dein Ticket – Siri antwortet mit einem Satz und der Zahl, ohne dass du die App öffnest.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(WidSiriPhrase.unbreakableNames("„Wie viele Fahrten diesen Monat in KlimaBilanz?“"))
                    .accessibilityLabel("„Wie viele Fahrten diesen Monat in KlimaBilanz?“")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            // The opening grows to AX3 – at AX5 it alone would fill the screen above „Probier es aus“.
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var orb: some View {
        ZStack {
            Circle()
                .fill(Theme.routeGradient)
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            Image(systemName: "waveform")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
        }
        .frame(width: 56, height: 56)
        .shadow(color: Theme.accent.opacity(0.3), radius: 10, y: 4)
        .accessibilityHidden(true)
    }
}

/// What one says, Siri's sentence and its snippet – on a platter like Siri's.
struct SiriAnswerPlatter: View {
    /// What to say for this question and period; nil when only a Kurzbefehl asks it that way.
    var phrase: String?
    var answer: KpiAnswer

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: phrase == nil ? "square.stack.3d.up.fill" : "mic.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                    // „KlimaBilanz“ never hyphenates („Klima-“ | „Bilanz“; display only, VoiceOver reads the label below).
                    Text(WidSiriPhrase.unbreakableNames(phrase.map { "„\($0)“" }
                         ?? "Nur im Kurzbefehl: Frag KlimaBilanz · \(answer.question.title) · \(answer.period.title)"))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(phrase.map { "Du sagst: \($0)" } ?? "Nur in der Kurzbefehle-App")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text(WidSiriPhrase.unbreakableNames(answer.sentence))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Siri sagt: \(answer.sentence)")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            AskKlimaSnippet(answer: answer)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Theme.background.opacity(0.55)))
        .overlay(shape.strokeBorder(Theme.separator, lineWidth: 0.8))
        .motionAnimation(Motion.smooth, value: answer.sentence)
    }
}

/// How a question is said to Siri (the phrases of KlimaBilanzShortcuts and the synonyms of AskKlimaQuestion / AskKlimaPeriod).
enum AskKlimaPhrase {
    /// „Wie viele Fahrten diesen Monat in KlimaBilanz“ – nil for a combination only the Kurzbefehle-App can ask (a period other than
    /// the Ticketjahr for anything but Fahrten).
    static func spoken(_ question: KpiQuestion, _ period: KpiPeriod) -> String? {
        if question == .trips {
            let named: String
            switch period {
            case .thisWeek: named = "diese Woche"
            case .thisMonth: named = "diesen Monat"
            case .lastMonth: named = "letzten Monat"
            case .ticketYear: named = "im Ticketjahr"
            case .calendarYear: named = "heuer"
            }
            return "Wie viele Fahrten \(named) in KlimaBilanz"
        }
        // A ticket question asked for another period starts with „Das gibt es nur fürs ganze Ticketjahr“ – by voice it never is.
        guard period == .ticketYear || question.ignoresPeriod else { return nil }
        return "\(question.example) in KlimaBilanz"
    }

    /// The example in „So fragst du“.
    static func example(_ question: KpiQuestion) -> String { "\(question.example) in KlimaBilanz?" }

    static func tint(_ question: KpiQuestion) -> Color {
        switch question {
        case .trips, .distance: Theme.glacier
        case .value, .costPerDay: Theme.dusk
        case .co2: Theme.pine
        case .net, .breakEven: Theme.dawn
        case .daysLeft: Theme.alpenglow
        }
    }
}
