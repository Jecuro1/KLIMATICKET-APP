import SwiftUI
import SwiftData
import KlimaCore

// MARK: - Source label

/// Shown next to every AI-related text: where it came from. Never hidden, so the user always knows what wrote it.
struct AssistantSourceLabel: View {
    var source: AssistantSource

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .accessibilityLabel(text)
    }

    private var text: String {
        switch source {
        case .model: "Mit der KI auf deinem Gerät formuliert"
        case .rules: "Aus deinen Zahlen per Regeln"
        case .demo: "Demo – kein Modell befragt"
        }
    }

    private var symbol: String {
        switch source {
        case .model: "sparkles"
        case .rules: "list.bullet.rectangle"
        case .demo: "tag"
        }
    }
}

// MARK: - Warum lohnt sich mein Ticket?

/// The Übersicht entry under the balance card. The sheet shows the rule text at once and replaces it with the model's
/// text when that has passed the number check.
struct AssistantWhyTicketButton: View {
    var snapshot: AnalyticsSnapshot
    @State private var showsExplanation = false

    var body: some View {
        Button { showsExplanation = true } label: {
            Label("Warum lohnt sich mein Ticket?", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.glass)
        .sheet(isPresented: $showsExplanation) {
            AssistantBalanceSheet(facts: BalanceFacts.make(ticketName: snapshot.ticket.name, summary: snapshot.summary,
                                                           isExpired: Date() > snapshot.ticket.end))
        }
    }
}

struct AssistantBalanceSheet: View {
    var facts: BalanceFacts
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var shown: AssistantText?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    let text = shown ?? AssistantText(text: facts.ruleText, source: .rules)
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        AssistantSourceLabel(source: text.source)
                        Text(text.text)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(Theme.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frostedCard()
                    .motionTransition(.rise)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Kicker(text: "Diese Zahlen flossen ein")
                        ForEach(facts.lines, id: \.self) { line in
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    SetFooter(text: "Nichts verlässt dein Gerät. Die KI erfindet keine Zahlen: Jede Zahl im Text muss in der Liste oben stehen, sonst zeigt KlimaBilanz den Regeltext.")
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.vertical, Theme.Spacing.m)
            }
            .background { Theme.sheetBackground.ignoresSafeArea() }
            .navigationTitle("Warum lohnt sich mein Ticket?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .task {
                shown = await app.assistant.explainBalance(facts)
            }
        }
    }
}

// MARK: - Suche in Worten (planner)

/// The entry in the planner: a glass capsule above the route slots.
struct AssistantTripQueryButton: View {
    @State private var showsQuery = false

    var body: some View {
        Button { showsQuery = true } label: {
            Label("In Worten suchen", systemImage: "text.magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.glass)
        .sheet(isPresented: $showsQuery) { AssistantTripQuerySheet() }
        .accessibilityHint("Sag zum Beispiel: nächste Woche Freitag nach Innsbruck")
    }
}

/// Reads a sentence into the planner's fields. The planner keeps the search itself: the sheet fills origin, destination and
/// time, then the user starts the search (or it starts once both ends are set, as with the station picker).
struct AssistantTripQuerySheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var result: LocalAssistant.TripQueryResult?
    @State private var isWorking = false
    private let autoRun: Bool

    init(initialText: String = "", autoRun: Bool = false) {
        _text = State(initialValue: initialText)
        self.autoRun = autoRun
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text("Sag, wohin und wann. KlimaBilanz füllt den Planer aus, dann prüfst du und suchst.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    TextField("z. B. nächste Woche Freitag nach Innsbruck, Rückfahrt Sonntag", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(Theme.Spacing.s)
                        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.chip, style: .continuous))
                        .submitLabel(.search)
                        .onSubmit { Task { await run() } }
                    Button { Task { await run() } } label: {
                        Text("Verstehen").font(.headline).frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.prominentTint)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                    if let result {
                        resultCard(result)
                            .motionTransition(.rise)
                    }
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.vertical, Theme.Spacing.m)
            }
            .background { Theme.sheetBackground.ignoresSafeArea() }
            .navigationTitle("Suche in Worten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .task {
                if autoRun, result == nil, !text.isEmpty { await run() }
            }
        }
    }

    private func run() async {
        isWorking = true
        result = await app.assistant.parseTripQuery(text, stations: app.stations)
        isWorking = false
    }

    @ViewBuilder
    private func resultCard(_ result: LocalAssistant.TripQueryResult) -> some View {
        let draft = result.draft
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            AssistantSourceLabel(source: result.source)
            queryRow("Von", result.origin?.name ?? "noch offen")
            queryRow("Nach", result.destination?.name ?? "noch offen")
            queryRow(draft.isArrival ? "Ankunft" : "Abfahrt", timeText(draft))
            if let back = draft.returnDay {
                queryRow("Rückfahrt", Format.weekdayDayMonth(back))
                Text("Die Rückfahrt suche ich nicht mit. Sie steht hier zur Erinnerung, du suchst sie separat.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(result.unresolved, id: \.self) { name in
                Text("„\(name)“ finde ich nicht als Bahnhof. Wähle den Ort im Planer.")
                    .font(.footnote)
                    .foregroundStyle(Theme.negativeText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { apply(result) } label: {
                Text("In den Planer übernehmen").font(.headline).frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.prominentTint)
            .disabled(result.origin == nil && result.destination == nil)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard()
    }

    private func queryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func timeText(_ draft: TripQueryDraft) -> String {
        guard let day = draft.outboundDay else { return draft.outboundHour == nil ? "heute, jetzt" : "heute" }
        let dayText = Format.weekdayDayMonth(day)
        guard let hour = draft.outboundHour else { return dayText }
        return "\(dayText), \(String(format: "%02ld:%02ld", hour, draft.outboundMinute ?? 0)) Uhr"
    }

    /// The planner's own setters: a station fills its slot, the time goes to the time row, and a full query starts the search.
    private func apply(_ result: LocalAssistant.TripQueryResult) {
        let model = app.planner
        if let origin = result.origin { model.origin = .station(origin) }
        if let destination = result.destination { model.destination = .station(destination) }
        model.mode = .connections
        model.setWhen(planned(result.draft), arrival: result.draft.isArrival)
        dismiss()
        if model.hasBoth { model.startSearch() }
    }

    private func planned(_ draft: TripQueryDraft) -> Date? {
        let calendar = Calendar.vienna
        guard draft.outboundDay != nil || draft.outboundHour != nil else { return nil }
        let day = draft.outboundDay ?? calendar.startOfDay(for: Date())
        return calendar.date(bySettingHour: draft.outboundHour ?? 0, minute: draft.outboundMinute ?? 0, second: 0, of: day)
    }
}

// MARK: - Strecken zur üblichen Zeit (planner)

/// "Du fährst meist um diese Zeit": a saved relation driven often around this hour. Rules pick it; the model may only word it.
struct AssistantRouteHint: View {
    var trips: [TripEntity]
    @Environment(AppState.self) private var app
    @State private var wording: AssistantText?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 900)) { context in
            if let hint = hint(at: context.date) {
                card(hint)
                    .task(id: hint.key) {
                        wording = nil
                        wording = await app.assistant.routeWording(hint.suggestion, fromName: hint.from.name, toName: hint.to.name)
                    }
            }
        }
    }

    private struct Hint {
        var from: Station
        var to: Station
        var suggestion: RouteTimeSuggestion
        var key: String { "\(suggestion.fromID)>\(suggestion.toID)>\(suggestion.matching)" }
    }

    private func hint(at now: Date) -> Hint? {
        let records = trips.map { (from: $0.fromStationID, to: $0.toStationID, start: $0.date) }
        guard let top = RouteTimeSuggestions.suggest(RouteStarts.group(records), now: now).first,
              let from = app.stations.station(id: top.fromID), let to = app.stations.station(id: top.toID) else { return nil }
        return Hint(from: from, to: to, suggestion: top)
    }

    private func card(_ hint: Hint) -> some View {
        let model = app.planner
        let shown = wording ?? AssistantText(text: hint.suggestion.ruleText(fromName: hint.from.name, toName: hint.to.name), source: .rules)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Kicker(text: "Vorschlag für jetzt")
            Text(shown.text)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            AssistantSourceLabel(source: shown.source)
            Button {
                model.origin = .station(hint.from)
                model.destination = .station(hint.to)
                model.when = nil
                model.mode = .connections
                model.startSearch()
            } label: {
                Text("Verbindungen suchen").font(.headline).frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.glass)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard()
        .accessibilityElement(children: .contain)
    }
}
