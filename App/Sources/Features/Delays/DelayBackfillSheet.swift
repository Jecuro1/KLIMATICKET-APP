import SwiftUI
import SwiftData
import KlimaCore

// MARK: delaydiary – „Nachtragen“: the Fahrten of a month (or the year) without an entry, one tap each (docs/DELAY_DIARY.md §4)

/// Lists the Fahrten without a recorded arrival, newest first, with „Pünktlich“ and „Verspätet …“ per row. The list is taken
/// once when the sheet opens, so a row stays put after its tap and shows what it got (with „Rückgängig“). There is no „alle
/// pünktlich“: a share built from guesses would not be the holder's own record.
struct DelayBackfillSheet: View {
    let ticket: TicketEntity
    let request: DelayBackfillRequest

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date)
    private var trips: [TripEntity]

    @State private var rows: [DelayDiaryEntry]?
    /// What a row's trip had before this sheet changed it (for „Rückgängig“).
    @State private var previous: [UUID: (minutes: Int, sourceRaw: String)] = [:]
    @State private var editing: TripEntity?
    @State private var marked = 0
    @State private var undone = 0

    var body: some View {
        let byID = Dictionary(trips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    intro
                    if let rows {
                        if rows.isEmpty {
                            GlassCard {
                                EmptyStateView(symbol: "checkmark.seal", title: "Alles eingetragen",
                                               message: "In diesem Zeitraum hat jede Fahrt einen Eintrag.")
                            }
                        } else {
                            ForEach(rows) { entry in
                                row(entry, trip: byID[entry.editTripID])
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .background(Theme.sheetBackground.ignoresSafeArea())
            .navigationTitle("Nachtragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .haptic(.success, trigger: marked)
        .haptic(.warning, trigger: undone)
        .sheet(item: $editing) { trip in
            DelayEntrySheet(trip: trip)
        }
        .onAppear { if rows == nil { rows = snapshot() } }
        .accessibilityIdentifier("delay.backfill")
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker(text: title)
            Text("War die Fahrt pünktlich? Ein Tipp pro Fahrt – nur was du weißt. Ohne Eintrag bleibt eine Fahrt aus der Quote.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
        .padding(.bottom, Theme.Spacing.xxs)
    }

    private var title: String {
        guard let index = request.monthIndex,
              let month = PerkPassengerRights.validityMonths(start: ticket.startDate, end: ticket.endDate)[safe: index] else {
            return "Ticketjahr \(StatsCalc.ticketYearLabel(ticket.period)) · ohne Eintrag"
        }
        return "\(DelayDiaryFormat.monthTitle(start: month.start, end: month.end)) · ohne Eintrag"
    }

    /// The Fahrten without an entry now, newest first (the month's or the year's).
    private func snapshot() -> [DelayDiaryEntry] {
        let year = DelayDiaryMemo.year(trips: trips, start: ticket.startDate, end: ticket.endDate, now: Date(),
                                       options: DelayDiarySettings.shared.options)
        let months = year.months.filter { request.monthIndex == nil || $0.index == request.monthIndex }
        return months.flatMap(\.unrecordedEntries).sorted { $0.date > $1.date }
    }

    // MARK: Row

    private func row(_ entry: DelayDiaryEntry, trip: TripEntity?) -> some View {
        let recorded = trip?.recordedDelay
        return GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.tile) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    ModeIcon(mode: entry.modes.last ?? .train, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DelayDiaryFormat.when(entry.date))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                        Text(DelayDiaryFormat.route(entry))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(entry.isJourney ? "\(DelayDiaryFormat.train(entry)) · Ankunft der letzten Etappe" : DelayDiaryFormat.train(entry))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                if let trip {
                    if let recorded {
                        doneRow(recorded, trip: trip)
                            .motionTransition(.pop)
                    } else {
                        buttons(trip)
                            .motionTransition(.pop)
                    }
                }
            }
        }
        .motionAnimation(Motion.snappy, value: recorded?.minutes)
    }

    private func buttons(_ trip: TripEntity) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) { onTimeButton(trip); lateButton(trip) }
            VStack(spacing: Theme.Spacing.xs) { onTimeButton(trip); lateButton(trip) }
        }
    }

    private func onTimeButton(_ trip: TripEntity) -> some View {
        Button {
            remember(trip)
            withMotion(Motion.snappy) {
                _ = Repository(context: context, app: app).recordOnTime([trip])
            }
            marked += 1
        } label: {
            Label("Pünktlich", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.positiveText)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .accessibilityHint("Trägt die Fahrt als pünktlich ein")
    }

    private func lateButton(_ trip: TripEntity) -> some View {
        Button {
            remember(trip)
            editing = trip
        } label: {
            Label("Verspätet …", systemImage: "clock.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.summitText)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .accessibilityHint("Öffnet die Eingabe der Minuten")
    }

    private func doneRow(_ recorded: (minutes: Int, source: TripDelaySource), trip: TripEntity) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Label(DelayDiaryText.rowValue(minutes: recorded.minutes, source: recorded.source),
                  systemImage: recorded.minutes == 0 ? "checkmark.circle.fill" : "clock.badge.exclamationmark.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DelayDiaryRules.isLate(recorded.minutes, threshold: DelayDiarySettings.shared.options.thresholdMinutes)
                                 ? Theme.summitText : Theme.positiveText)
            Spacer(minLength: Theme.Spacing.xs)
            if previous[trip.id] != nil {
                Button("Rückgängig") { undo(trip) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .buttonStyle(.plain)
            }
        }
    }

    private func remember(_ trip: TripEntity) {
        if previous[trip.id] == nil { previous[trip.id] = (trip.delayMinutes, trip.delaySourceRaw) }
    }

    private func undo(_ trip: TripEntity) {
        guard let before = previous[trip.id] else { return }
        withMotion(Motion.snappy) {
            _ = Repository(context: context, app: app).restoreDelays([(trip, before.minutes, before.sourceRaw)])
        }
        previous[trip.id] = nil
        undone += 1
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Settings

/// „Tagebuch einstellen“: the personal late mark and which Fahrten count.
struct DelayOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Bindable private var settings = DelayDiarySettings.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    card(kicker: "Verspätet ab",
                         text: "Ab wie vielen Minuten bei der Ankunft eine Fahrt in deinem Tagebuch als verspätet zählt. Die AGB nennen dafür keine Minute (Punkt 24) – die Bahnen messen ihre Pünktlichkeit selbst.") {
                        choice(selection: thresholdBinding, options: DelayDiaryRules.thresholdChoices) { "\($0)\u{00A0}Min." }
                    }
                    card(kicker: "Welche Fahrten",
                         text: settings.options.scope == .rail
                            ? "Nur Zug und S-Bahn – die Bahnen, um die es in Punkt 24 geht. Bei einer Reise zählen nur ihre Bahn-Etappen."
                            : "Alle Fahrten, auch Bus, Bim und U-Bahn – dein persönliches Tagebuch.") {
                        choice(selection: scopeBinding, options: DelayDiaryScope.allCases) { $0 == .all ? "Alle" : "Nur Bahn" }
                    }
                    if !settings.options.isDefault {
                        Button {
                            withMotion(Motion.smooth) { settings.options = DelayDiaryOptions() }
                        } label: {
                            Text("Auf Standard zurücksetzen")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .motionTransition(.rise)
                    }
                    Text("Die Einstellungen ändern nur, wie das Tagebuch zählt – an deinen Einträgen ändert sich nichts.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(Theme.sheetBackground.ignoresSafeArea())
            .navigationTitle("Tagebuch einstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.fraction(0.72), .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("delay.options")
    }

    private var thresholdBinding: Binding<Int> {
        Binding(get: { settings.options.thresholdMinutes }, set: { value in
            withMotion(Motion.smooth) { settings.options.thresholdMinutes = DelayDiaryRules.normalizedThreshold(value) }
        })
    }

    private var scopeBinding: Binding<DelayDiaryScope> {
        Binding(get: { settings.options.scope }, set: { value in
            withMotion(Motion.smooth) { settings.options.scope = value }
        })
    }

    @ViewBuilder
    private func choice<Value: Hashable>(selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String) -> some View {
        if typeSize.isAccessibilitySize {
            WhatIfStackedChoice(selection: selection, options: options, title: title)
        } else {
            GlassSegmentedPicker(selection: selection, options: options) { Text(title($0)) }
        }
    }

    private func card<Content: View>(kicker: String, text: String, @ViewBuilder content: () -> Content) -> some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: kicker)
                content()
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
    }
}
