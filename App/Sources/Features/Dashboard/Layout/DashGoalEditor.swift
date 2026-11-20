import SwiftUI
import KlimaCore

// MARK: uebersicht – the goal editor: what to count, the target with a stepper (Fahrten 1–100, Wert € 10–2.000 in steps of 10, CO₂
// 1–500 kg) or the day within the ticket's validity, and the real ring of the draft against today's trips before anything is saved.

struct DashGoalEditorTarget: Identifiable {
    let id = UUID()
    /// nil: a new goal.
    var goal: Goal?
}

struct DashGoalEditor: View {
    let target: DashGoalEditorTarget
    let snapshot: AnalyticsSnapshot?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var kind: GoalKind
    @State private var amount: Double
    @State private var until: Date
    @State private var stepTick = 0
    @State private var confirmsDelete = false

    private var store: DashLayoutStore { .shared }

    init(target: DashGoalEditorTarget, snapshot: AnalyticsSnapshot?) {
        self.target = target
        self.snapshot = snapshot
        let goal = target.goal
        _kind = State(initialValue: goal?.kind ?? .tripsPerMonth)
        _amount = State(initialValue: goal?.target ?? GoalKind.tripsPerMonth.suggestedTarget)
        let fallback = snapshot.map { Self.defaultDay(for: $0.ticket) } ?? Date()
        _until = State(initialValue: goal?.until ?? fallback)
    }

    /// The draft as it would be saved.
    private var draft: Goal {
        Goal(id: target.goal?.id ?? target.id, kind: kind, target: kind == .breakEvenBy ? nil : amount,
             until: kind == .breakEvenBy ? until : nil)
    }

    /// MARK: review-uebersicht – „Break-even bis“ needs a day inside the validity; after the ticket's end there is none.
    private var ticketHasEnded: Bool { snapshot.map { Date() > $0.ticket.end } ?? false }

    private var preview: GoalProgress? {
        snapshot.flatMap { DashGoalEvaluation.progress([draft], snapshot: $0, catalog: app.catalog).first }
    }

    var body: some View {
        List {
            kindSection
            targetSection
            if let preview {
                Section {
                    DashGoalRow(progress: preview, isVisible: false)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .listRowBackground(Theme.surface)
                        .id(preview.goal.kind.rawValue + "\(preview.target)" + preview.periodKey)
                } header: {
                    SetSectionHeader(title: "So stehst du heute")
                } footer: {
                    SetFooter(text: footer)
                }
            }
            if target.goal != nil {
                Section {
                    Button(role: .destructive) {
                        confirmsDelete = true
                    } label: {
                        Label("Ziel löschen", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .scrollContentBackground(.hidden)
        .background(Theme.sheetBackground)
        .navigationTitle(target.goal == nil ? "Neues Ziel" : "Ziel bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { save() }
                    .fontWeight(.semibold)
                    .disabled(snapshot == nil)
            }
        }
        .haptic(.selection, trigger: kind)
        .haptic(.increase, trigger: stepTick)
        .confirmationDialog("Ziel löschen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let id = target.goal?.id { store.removeGoal(id: id) }
                dismiss()
            }
        } message: {
            Text("Der Ring verschwindet von der Übersicht. Deine Fahrten bleiben, wie sie sind.")
        }
        .onChange(of: kind) { _, new in
            guard new != target.goal?.kind else { amount = target.goal?.target ?? new.suggestedTarget; return }
            amount = new.suggestedTarget
        }
    }

    // MARK: Sections

    private var kindSection: some View {
        Section {
            ForEach(GoalKind.allCases) { option in
                let unavailable = option == .breakEvenBy && ticketHasEnded
                Button {
                    withMotion(Motion.snappy) { kind = option }
                } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        SetIconTile(symbol: option.symbol, tint: Theme.pine)
                            .opacity(option == kind ? 1 : 0.45)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .foregroundStyle(Theme.textPrimary)
                            Text(option == .breakEvenBy && ticketHasEnded ? "Dein Ticket ist abgelaufen – kein Tag mehr frei"
                                 : kindDetail(option))
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Theme.Spacing.xs)
                        Image(systemName: option == kind ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(option == kind ? Theme.accentText : Theme.textTertiary)
                            .symbolReplaceTransition()
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(unavailable)
                .opacity(unavailable ? 0.5 : 1)
                .listRowBackground(Theme.surface)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(option == kind ? [.isButton, .isSelected] : .isButton)
            }
        } header: {
            SetSectionHeader(title: "Was zählt")
        }
    }

    private func kindDetail(_ kind: GoalKind) -> String {
        switch kind {
        case .tripsPerMonth: "Fahrten im Kalendermonat – eine Reise mit Umstieg zählt einmal"
        case .valuePerMonth: "Normalpreis deiner Fahrten im Kalendermonat"
        case .co2PerMonth: "CO₂, das du gegenüber dem Auto sparst, ca."
        case .breakEvenBy: "Bis zu einem Tag soll sich dein Ticket rentiert haben"
        }
    }

    @ViewBuilder
    private var targetSection: some View {
        Section {
            if kind == .breakEvenBy {
                if let snapshot {
                    DatePicker("Tag", selection: $until, in: GoalEvaluator.dateRange(for: snapshot.ticket, now: Date()),
                               displayedComponents: .date)
                        .environment(\.locale, Format.locale)
                        .environment(\.timeZone, Format.timeZone)
                        .listRowBackground(Theme.surface)
                }
            } else if let range = kind.targetRange {
                // The tick only for a step – a new kind sets the amount too and plays its own .selection.
                Stepper(value: Binding(get: { amount }, set: { amount = $0; stepTick += 1 }), in: range, step: kind.targetStep) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(amountText)
                            .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                            .numericValue(amount)
                        Text("im Monat")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .listRowBackground(Theme.surface)
            }
        } header: {
            SetSectionHeader(title: "Ziel")
        } footer: {
            if kind == .breakEvenBy {
                SetFooter(text: "Ein Tag zwischen heute und dem letzten Gültigkeitstag deines Tickets.")
            }
        }
    }

    private var amountText: String {
        switch kind {
        case .tripsPerMonth: GoalText.trips(Int(amount))
        case .valuePerMonth: Format.euro(amount, decimals: 0)
        case .co2PerMonth: Format.kg(amount)
        case .breakEvenBy: ""
        }
    }

    private var footer: String {
        kind == .breakEvenBy
            ? "„Auf Kurs“ heißt: die Prognose der Bilanz-Karte liegt vor dem Tag. Sie rechnet mit deinem bisherigen Tempo – kein Versprechen."
            : "Gezählt wird der laufende Kalendermonat. „Auf Kurs“ misst an den Tagen, die schon vorbei sind; am 1. ist noch nichts fällig."
    }

    private func save() {
        store.save(draft, progress: preview)
        dismiss()
    }

    /// A first day for „Break-even bis“: the ticket's last day.
    private static func defaultDay(for ticket: TicketPeriod) -> Date {
        let range = GoalEvaluator.dateRange(for: ticket, now: Date())
        return range.upperBound
    }
}

/// A goal in the editor's list: icon, title, where it stands.
struct DashGoalEditorRow: View {
    let goal: Goal
    let progress: GoalProgress?

    var body: some View {
        let format = DashGoalFormat.formatter
        HStack(spacing: Theme.Spacing.s) {
            SetIconTile(symbol: goal.kind.symbol, tint: Theme.pine)
            VStack(alignment: .leading, spacing: 2) {
                Text(GoalText.title(goal, format: format))
                    .foregroundStyle(Theme.textPrimary)
                if let progress {
                    Text("\(GoalText.status(progress, format: format)) · \(GoalText.stateLabel(progress.state))")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: Theme.Spacing.xs)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
