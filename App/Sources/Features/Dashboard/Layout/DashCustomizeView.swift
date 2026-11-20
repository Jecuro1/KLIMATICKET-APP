import SwiftUI
import SwiftData
import KlimaCore

// MARK: uebersicht – „Übersicht anpassen“ (docs/DASHBOARD_LAYOUT.md §5): presets, the cards with an eye each (drag to reorder – the
// handles show with „Bearbeiten“, a long press drags at any time), the picked figures and the goals. Every change applies at once behind
// the sheet (Motion.smooth). Opened by the button at the end of the Übersicht, by „Anpassen“ on the Kennzahlen and Ziele cards and from
// Einstellungen › Darstellung (pushed there, the same page).

/// The editor as a sheet over the Übersicht: half height first, so the cards can be seen moving above it.
struct DashCustomizeSheet: View {
    var focus: DashEditorFocus?
    /// CI scenes open it at full height.
    var startsLarge = false
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            DashCustomizeView(isSheet: true, focus: focus)
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .modifier(DashSceneTypeSize())   // CI: a sheet does not take the presenter's text size
        .onAppear {
            // Kennzahlen and Ziele sit further down: open tall when „Anpassen“ on their card asked for them.
            if startsLarge || focus == .kpis || focus == .goals { detent = .large }
        }
    }
}

/// CI scene dashEditAX5: the sheet at the largest text size.
private struct DashSceneTypeSize: ViewModifier {
    func body(content: Content) -> some View {
        if LaunchMode.screenshotScreen == "dashEditAX5" {
            content.dynamicTypeSize(.accessibility5)
        } else {
            content
        }
    }
}

extension View {
    /// The Übersicht presents the editor (DashboardView, `// MARK: uebersicht`).
    func dashCustomizeHost() -> some View {
        modifier(DashCustomizeHost())
    }
}

private struct DashCustomizeHost: ViewModifier {
    @Bindable private var store = DashLayoutStore.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: $store.isEditing) {
            DashCustomizeSheet(focus: store.editorFocus, startsLarge: store.editorStartsLarge)
        }
    }
}

/// The snapshot the editor reads (its live values): the Übersicht's ticket and trips, through the same memoised Analytics.make.
struct DashEditorSnapshot<Content: View>: View {
    @ViewBuilder var content: (AnalyticsSnapshot?, [TripEntity]) -> Content

    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse)
    private var trips: [TripEntity]

    var body: some View {
        let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID)
        content(ticket.map { Analytics.make(ticket: $0, trips: trips, catalog: app.catalog) }, trips)
    }
}

struct DashCustomizeView: View {
    var isSheet = false
    var focus: DashEditorFocus?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var editMode: EditMode = .inactive
    @State private var goalTarget: DashGoalEditorTarget?
    @State private var resetTick = 0

    private var store: DashLayoutStore { .shared }

    var body: some View {
        DashEditorSnapshot { snapshot, trips in
            ScrollViewReader { proxy in
                List {
                    presetsSection
                    sectionsSection
                    kpiSection(snapshot: snapshot, trips: trips)
                    goalsSection(snapshot: snapshot)
                    resetSection
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(Theme.Spacing.l)
                .scrollContentBackground(.hidden)
                .background { SetBackdrop(skyOpacity: 0.35, fadeEnd: 0.4) }
                .environment(\.editMode, $editMode)
                .task {
                    guard let focus else { return }
                    try? await Task.sleep(for: .milliseconds(350))
                    withMotion(Motion.smooth) { proxy.scrollTo(focus, anchor: .center) }
                }
                .sheet(item: $goalTarget) { target in
                    NavigationStack {
                        DashGoalEditor(target: target, snapshot: snapshot)
                    }
                    .presentationDragIndicator(.visible)
                }
            }
        }
        .navigationTitle("Übersicht anpassen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .haptic(.warning, trigger: resetTick)
        .haptic(.success, trigger: store.goalSaveTick)
        .haptic(.warning, trigger: store.goalDeleteTick)
        .onAppear {
            if LaunchMode.screenshotScreen == "dashEditSort" { editMode = .active }
        }
    }

    // MARK: Presets

    private var presetsSection: some View {
        Section {
            DashPresetGrid(current: DashPreset.matching(store.layout)) { preset in
                store.apply(preset)
            }
            .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.s, bottom: Theme.Spacing.s, trailing: Theme.Spacing.s))
            .listRowBackground(Color.clear)
        } header: {
            SetSectionHeader(title: "Vorlagen")
        } footer: {
            SetFooter(text: DashPreset.matching(store.layout) == nil
                      ? "Eigene Anordnung. Eine Vorlage ersetzt Reihenfolge und Sichtbarkeit – Kennzahlen und Ziele bleiben."
                      : "Eine Vorlage ersetzt Reihenfolge und Sichtbarkeit – Kennzahlen und Ziele bleiben.")
        }
    }

    // MARK: Cards

    private var sectionsSection: some View {
        Section {
            ForEach(store.layout.order) { id in
                DashSectionRow(id: id, layout: store.layout, offNote: offNote(id), contentNote: contentNote(id),
                               isEditing: editMode.isEditing)
                    .listRowBackground(Theme.surface)
            }
            .onMove { source, destination in
                store.move(fromOffsets: source, toOffset: destination)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                SetSectionHeader(title: "Karten")
                Spacer(minLength: Theme.Spacing.xs)
                // The handles to drag: on with „Sortieren“ (a long press drags at any time).
                Button {
                    withMotion(Motion.smooth) { editMode = editMode.isEditing ? .inactive : .active }
                } label: {
                    Label(editMode.isEditing ? "Fertig" : "Sortieren",
                          systemImage: editMode.isEditing ? "checkmark" : "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .labelStyle(.titleAndIcon)
                        .contentTransition(.opacity)
                }
                .buttonStyle(.pressable)
                .textCase(nil)
                .accessibilityHint("Zeigt die Griffe zum Verschieben der Karten")
            }
        } footer: {
            SetFooter(text: "„Sortieren“ zeigt die Griffe – oder halte eine Karte gedrückt und zieh sie an ihren Platz. Eine Karte ohne Inhalt bleibt unsichtbar, egal was hier steht. Kopf, Ticket und Gipfel stehen immer oben.")
        }
    }

    /// What Kennzahlen and Ziele hold right now („4 gewählt“, „2 Ziele“) instead of when they would show.
    private func contentNote(_ id: DashSectionID) -> String? {
        switch id {
        case .kpis:
            let n = store.kpis.kinds.count
            return n == 0 ? nil : "\(n) von \(KpiCatalog.maxTiles) gewählt"
        case .goals:
            let n = store.goals.goals.count
            return n == 0 ? nil : (n == 1 ? "1 Ziel" : "\(n) Ziele")
        default:
            return nil
        }
    }

    /// „Funktion aus“: a feature switched off in Funktionen hides its card whatever the layout says.
    private func offNote(_ id: DashSectionID) -> String? {
        let feature: FeatureID? = switch id {
        case .achievements: .achievementsTeaser
        case .week: .weekInsight
        case .perks: .perksCard
        default: nil
        }
        guard let feature, !FeatureCenter.shared.isOn(feature, app: app) else { return nil }
        return "Funktion aus · in Einstellungen › Funktionen"
    }

    // MARK: Figures

    private func kpiSection(snapshot: AnalyticsSnapshot?, trips: [TripEntity]) -> some View {
        Section {
            if let snapshot, !store.kpis.kinds.isEmpty {
                DashKpiGrid(readings: KpiCatalog.readings(store.kpis.kinds, input: DashKpiInput.make(snapshot: snapshot, tripsNewestFirst: trips)),
                            summary: snapshot.summary, compact: true)
                    .listRowInsets(EdgeInsets(top: Theme.Spacing.xs, leading: 0, bottom: Theme.Spacing.xs, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            NavigationLink {
                DashKpiPicker()
            } label: {
                SetRowLabel(title: store.kpis.kinds.isEmpty ? "Kennzahlen wählen" : "Kennzahlen ändern",
                            subtitle: kpiSummary, symbol: "square.grid.2x2.fill", tint: Theme.dusk)
            }
            .listRowBackground(Theme.surface)
            .disabled(editMode.isEditing)
            .id(DashEditorFocus.kpis)
        } header: {
            SetSectionHeader(title: "Kennzahlen")
        } footer: {
            SetFooter(text: "Bis zu vier eigene Zahlen aus dem Ticketjahr – dieselben, die Statistik zeigt.")
        }
    }

    private var kpiSummary: String {
        let kinds = store.kpis.kinds
        guard !kinds.isEmpty else { return "Keine gewählt – die Karte bleibt unsichtbar" }
        return kinds.map(\.title).joined(separator: " · ")
    }

    // MARK: Goals

    private func goalsSection(snapshot: AnalyticsSnapshot?) -> some View {
        let goals = store.goals.goals
        let progress = snapshot.map { DashGoalEvaluation.progress(goals, snapshot: $0, catalog: app.catalog) } ?? []
        return Section {
            ForEach(goals) { goal in
                Button {
                    goalTarget = DashGoalEditorTarget(goal: goal)
                } label: {
                    DashGoalEditorRow(goal: goal, progress: progress.first { $0.id == goal.id })
                }
                .buttonStyle(.pressableCard)
                .listRowBackground(Theme.surface)
                .disabled(editMode.isEditing)
                .accessibilityHint("Ziel bearbeiten")
            }
            Button {
                goalTarget = DashGoalEditorTarget(goal: nil)
            } label: {
                SetRowLabel(title: "Ziel hinzufügen",
                            subtitle: store.goals.isFull ? "Höchstens drei Ziele – lösch erst eines" : "Fahrten, Wert oder CO₂ im Monat, Break-even bis …",
                            symbol: "plus", tint: Theme.pine)
            }
            .disabled(store.goals.isFull || snapshot == nil || editMode.isEditing)
            .listRowBackground(Theme.surface)
            .id(DashEditorFocus.goals)
        } header: {
            SetSectionHeader(title: "Ziele")
        } footer: {
            SetFooter(text: "Ein Monatsziel zählt im Kalendermonat, wie Statistik. Der Ring zeigt, wie weit du bist; was „auf Kurs“ heißt, misst die App an den Tagen, die schon vorbei sind. Eine Prognose bleibt eine Prognose.")
        }
    }

    // MARK: Reset

    private var resetSection: some View {
        Section {
            Button {
                store.resetLayout()
                resetTick += 1
            } label: {
                Label("Zurücksetzen", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .disabled(store.layout.isStandard)
            .listRowBackground(Theme.surface)
        } footer: {
            SetFooter(text: "Reihenfolge und Sichtbarkeit wie ausgeliefert. Kennzahlen und Ziele bleiben.")
        }
    }
}

// MARK: - Presets

/// Four preset tiles, two per row (one at accessibility sizes); the matching one carries a ring and a check.
struct DashPresetGrid: View {
    let current: DashPreset?
    var onSelect: (DashPreset) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectionTick = 0

    var body: some View {
        // A Grid: the tiles of a row share its height. One column at accessibility sizes.
        let perRow = typeSize.isAccessibilitySize ? 1 : 2
        let presets = DashPreset.allCases
        let rows = stride(from: 0, to: presets.count, by: perRow).map { Array(presets[$0..<min($0 + perRow, presets.count)]) }
        Grid(horizontalSpacing: Theme.Spacing.s, verticalSpacing: Theme.Spacing.s) {
            ForEach(rows, id: \.first) { row in
                GridRow {
                    ForEach(row) { preset in
                        tile(preset)
                    }
                }
            }
        }
        .haptic(.selection, trigger: selectionTick)
    }

    private func tile(_ preset: DashPreset) -> some View {
        // „Alles“ shares the standard layout – only the one that was named lights up; „Standard“ when both match.
        let isCurrent = current == preset
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        return Button {
            selectionTick += 1
            onSelect(preset)
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isCurrent ? Theme.onAccent : Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(isCurrent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.14)), in: .circle)
                    .symbolReplaceTransition()
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(preset.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: shape)
            .overlay {
                shape.strokeBorder(isCurrent ? Theme.accent : Theme.separator, lineWidth: isCurrent ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.accentText)
                        .padding(6)
                        .motionTransition(.pop)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .motionAnimation(Motion.snappy, value: isCurrent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vorlage \(preset.title)")
        .accessibilityValue(preset.subtitle)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Card row

/// One card: icon, name, when it shows (or why it does not), the eye. VoiceOver: „Nach oben“, „Nach unten“, „Ausblenden“.
private struct DashSectionRow: View {
    let id: DashSectionID
    let layout: DashLayout
    let offNote: String?
    let contentNote: String?
    let isEditing: Bool

    private var store: DashLayoutStore { .shared }
    private var isHidden: Bool { layout.isHidden(id) }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            SetIconTile(symbol: id.symbol, tint: tint)
                .opacity(isHidden ? 0.4 : 1)
                .saturation(isHidden ? 0 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(id.title)
                    .foregroundStyle(isHidden ? Theme.textSecondary : Theme.textPrimary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(offNote != nil && !isHidden ? Theme.summitText : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.xs)
            eye
            if !isEditing {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(id.title)
        .accessibilityValue(isHidden ? "Ausgeblendet" : (offNote ?? "Sichtbar"))
        .accessibilityActions {
            Button("Nach oben") { store.move(id, up: true) }
            Button("Nach unten") { store.move(id, up: false) }
            if !id.isCore {
                Button(isHidden ? "Einblenden" : "Ausblenden") { store.setHidden(id, !isHidden) }
            }
        }
        .motionAnimation(Motion.snappy, value: isHidden)
    }

    private var detail: String {
        if isHidden { return "Ausgeblendet" }
        return offNote ?? contentNote ?? id.whenShown
    }

    @ViewBuilder
    private var eye: some View {
        if id.isCore {
            Image(systemName: "lock.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
        } else {
            Button {
                store.setHidden(id, !isHidden)
            } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isHidden ? Theme.textSecondary : Theme.accentText)
                    .symbolReplaceTransition()
                    .frame(width: 36, height: 36)
                    .contentShape(.circle)
            }
            .buttonStyle(.borderless)
            .haptic(.selection, trigger: isHidden)
            .accessibilityLabel(isHidden ? "Einblenden" : "Ausblenden")
        }
    }

    private var tint: Color {
        switch id {
        case .balance, .kpis: Theme.dusk
        case .goals, .commute: Theme.pine
        case .yearReview, .perks: Theme.dawn
        case .quickLog, .achievements: Theme.gold
        case .suggestions, .calendarSuggestions: Theme.alpenglow
        case .recentTrips, .week: Theme.glacier
        }
    }
}
