import SwiftUI
import KlimaCore

// Zugsuche ("Züge suchen"), opened from the Fahrplan header, not a tab (docs/OEBB_LIVE.md §R9). One train by name or
// number: its runs in the timetable period, earliest first, with date, first and last stop, realtime and delay.
// Copy in Du-Form.

struct TrainSearchView: View {
    /// Text the field starts with (a recent search, screenshots).
    var initialText: String? = nil
    /// Sends the initial text at once (screenshots).
    var autoSubmit = false

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model = TrainSearchModel()
    @State private var mapRun: TrainRun?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    searchField
                    content
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .ambientBackground(.standard, glow: 0.4)
            .navigationTitle("Züge suchen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .fullScreenCover(item: $mapRun) { run in
                RadarView(focusTripID: run.tripID)
            }
            .task {
                guard let initialText else { return }
                model.text = initialText
                if autoSubmit { model.submit(using: app.live.trainSearch) }
            }
        }
    }

    // MARK: Field

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            TextField("RJX 66 oder 66", text: $model.text)
                .font(Theme.Typography.body)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($fieldFocused)
                .onSubmit { model.submit(using: app.live.trainSearch) }
                .accessibilityLabel("Zugnummer")
            if !model.text.isEmpty {
                Button {
                    model.text = ""
                    model.reset()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Eingabe löschen")
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .frostedCard(cornerRadius: Theme.Radius.card)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if app.live.trainSearch == nil, let reason = app.live.timetableUnavailable {
            PlannerUnavailableView(reason: reason) { app.isShowingSettings = true }
        } else {
            switch model.phase {
            case .idle:
                suggestionsCard
            case .invalid:
                EmptyStateView(symbol: "questionmark.circle", title: "Das ist keine Zugnummer",
                               message: "Gib die Nummer mit Kategorie ein, z. B. RJX 66, oder nur die Nummer, z. B. 66.")
            case .loading:
                loadingCard
            case .noMatch:
                EmptyStateView(symbol: "magnifyingglass", title: "Keine Fahrt gefunden",
                               message: "Im Fahrplan gibt es keine Fahrt mit der Nummer \(model.name?.display ?? ""). Prüf die Schreibweise.")
            case .failed(let message):
                EmptyStateView(symbol: "wifi.exclamationmark", title: "Die Suche hat nicht geklappt", message: message,
                               actionTitle: "Erneut suchen") {
                    model.submit(using: app.live.trainSearch)
                }
            case .results:
                resultsSection
            }
        }
    }

    @ViewBuilder private var suggestionsCard: some View {
        let items = model.suggestions
        if items.isEmpty {
            EmptyStateView(symbol: "train.side.front.car", title: "Welcher Zug?",
                           message: "Gib die Nummer ein, z. B. RJX 66. KlimaBilanz zeigt dir alle Fahrten dieses Zugs im Fahrplan: Datum, erster und letzter Halt, Verspätung.")
        } else {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionHeader(title: model.text.isEmpty ? "Zuletzt gesucht" : "Vorschläge")
                    ForEach(items, id: \.self) { item in
                        Button {
                            model.text = item
                            model.submit(using: app.live.trainSearch)
                        } label: {
                            HStack {
                                Text(item)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer(minLength: Theme.Spacing.s)
                                Image(systemName: "arrow.up.left")
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.vertical, Theme.Spacing.xxs)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var loadingCard: some View {
        GlassCard {
            HStack(spacing: Theme.Spacing.m) {
                ProgressView()
                Text("Suche läuft …")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: model.runs.count == 1 ? "1 Fahrt" : "\(model.runs.count) Fahrten")
            ForEach(model.runs) { run in
                let active = run.isActive(on: Date())
                TrainRunCard(run: run, isActive: active,
                             onFollow: { follow(run) },
                             onMap: { mapRun = run })
            }
            if let note = footnote {
                Text(note)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Spacing.xxs)
            }
        }
    }

    private var footnote: String? {
        var parts: [String] = []
        if let updated = model.realtimeUpdatedAt { parts.append("Echtzeit-Stand \(Format.time(updated))") }
        if model.hiddenCount > 0 { parts.append("\(model.hiddenCount) mit längerer Nummer ausgeblendet") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func follow(_ run: TrainRun) {
        guard let target = run.followTarget else { return }
        LiveFollowTracker.shared.start(target, live: app.live)
        dismiss()
    }
}

/// One run: date, direction, first and last stop with realtime, and the actions for a run that is on the road today.
private struct TrainRunCard: View {
    var run: TrainRun
    var isActive: Bool
    var onFollow: () -> Void
    var onMap: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    if let line = run.line {
                        PlannerLinePlate(line: line, size: .m)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.plannedDate.map { Format.weekdayDayMonth($0) } ?? "Datum unbekannt")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.textPrimary)
                        if let direction = run.direction {
                            Text("Richtung \(direction)")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        } else if isActive {
                            Text("Heute unterwegs")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let origin = run.origin {
                    stopRow("Ab", name: origin.location.name, event: origin.departure)
                }
                if let destination = run.destination {
                    stopRow("An", name: destination.location.name, event: destination.arrival)
                }
                if run.isCancelled {
                    Text("Diese Fahrt fällt aus.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.negativeText)
                }
                actions
            }
        }
    }

    private func stopRow(_ label: String, name: String, event: StopEvent?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, alignment: .leading)
            Text(name)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.s)
            if let event {
                RealtimeTime(planned: event.planned, label: RealtimePresentation.label(event), style: .row)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if isActive {
            // Stacked, full width: two labels side by side truncated at the phone width.
            VStack(spacing: Theme.Spacing.s) {
                Button(action: onFollow) {
                    Label("Live verfolgen", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(run.followTarget == nil)
                Button(action: onMap) {
                    Label("Auf der Karte zeigen", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        } else {
            Text("Live verfolgen und Karte gibt es am Tag der Fahrt.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
