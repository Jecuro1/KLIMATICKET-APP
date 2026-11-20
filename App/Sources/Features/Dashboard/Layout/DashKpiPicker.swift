import SwiftUI
import SwiftData
import KlimaCore

// MARK: uebersicht – „Kennzahlen“: the catalog with each figure's value today and a live preview of the tiles on top. A tap picks or
// drops a figure; the number in the circle is its place in the grid. Four at most – a fifth row is greyed until one is dropped.

struct DashKpiPicker: View {
    @Environment(AppState.self) private var app
    @State private var tick = 0
    /// A fifth figure was tapped: the header says why nothing happened (a warning tap, no greyed-out rows).
    @State private var fullTick = 0
    @State private var showsFull = false

    private var store: DashLayoutStore { .shared }

    var body: some View {
        DashEditorSnapshot { snapshot, trips in
            let input = snapshot.map { DashKpiInput.make(snapshot: $0, tripsNewestFirst: trips) }
            List {
                previewSection(snapshot: snapshot, input: input)
                catalogSection(snapshot: snapshot, input: input)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(Theme.Spacing.l)
            .scrollContentBackground(.hidden)
            .background { SetBackdrop(skyOpacity: 0.35, fadeEnd: 0.4) }
        }
        .navigationTitle("Kennzahlen")
        .navigationBarTitleDisplayMode(.inline)
        .haptic(.selection, trigger: tick)
        .haptic(.warning, trigger: fullTick)
        .task(id: fullTick) {
            guard fullTick > 0 else { return }
            withMotion(Motion.snappy) { showsFull = true }
            try? await Task.sleep(for: .seconds(2.6))
            withMotion(Motion.smooth) { showsFull = false }
        }
    }

    @ViewBuilder
    private func previewSection(snapshot: AnalyticsSnapshot?, input: KpiInput?) -> some View {
        Section {
            if let snapshot, let input, !store.kpis.kinds.isEmpty {
                DashKpiGrid(readings: KpiCatalog.readings(store.kpis.kinds, input: input), summary: snapshot.summary, compact: true)
                    .listRowInsets(EdgeInsets(top: Theme.Spacing.xs, leading: 0, bottom: Theme.Spacing.xs, trailing: 0))
                    .listRowBackground(Color.clear)
            } else {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "square.grid.2x2")
                        .font(.title3)
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                    Text("Noch keine Kennzahl gewählt – die Karte erscheint, sobald du eine wählst.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.Spacing.xs)
                .listRowBackground(Theme.surface)
            }
        } header: {
            SetSectionHeader(title: "So sieht es aus")
        }
    }

    private func catalogSection(snapshot: AnalyticsSnapshot?, input: KpiInput?) -> some View {
        let kinds = input.map(KpiCatalog.offered(for:)) ?? KpiKind.allCases
        // A picked figure stays listed even when it has no value right now (a forecast after the ticket ended).
        let listed = kinds + store.kpis.kinds.filter { !kinds.contains($0) }
        return Section {
            ForEach(listed) { kind in
                row(kind, snapshot: snapshot, input: input)
            }
        } header: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                SetSectionHeader(title: "Katalog · \(store.kpis.kinds.count) von \(KpiCatalog.maxTiles)")
                if showsFull {
                    Label("Vier sind gewählt – nimm erst eine heraus.", systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.summitText)
                        .textCase(nil)
                        .motionTransition(.rise)
                }
            }
        } footer: {
            SetFooter(text: "Höchstens vier. Die Zahl im Kreis ist der Platz der Kachel. Alle Werte stammen aus deinem Ticketjahr, wie in Statistik; „Prognose Endwert“ gibt es, solange das Ticket läuft.")
        }
    }

    private func row(_ kind: KpiKind, snapshot: AnalyticsSnapshot?, input: KpiInput?) -> some View {
        let place = store.kpis.kinds.firstIndex(of: kind).map { $0 + 1 }
        let isPicked = place != nil
        let blocked = !isPicked && store.kpis.isFull
        let value = input.flatMap { input in
            snapshot.map { KpiDisplay.make(KpiCatalog.reading(kind, input: input), summary: $0.summary) }
        }
        return Button {
            if store.toggleKpi(kind) { tick += 1 } else { fullTick += 1 }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetIconTile(symbol: kind.symbol, tint: kind.tint)
                    .opacity(blocked ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .foregroundStyle(Theme.textPrimary)
                    Text(kind.explanation)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let value {
                        Text(valueLine(value))
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: Theme.Spacing.xs)
                placeBadge(place)
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.surface)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityValue([place.map { "gewählt, Platz \($0)" } ?? (blocked ? "nicht wählbar, vier sind gewählt" : "nicht gewählt"),
                             value?.spoken].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(kind.explanation)
        .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
    }

    private func valueLine(_ display: KpiDisplay) -> String {
        guard let unit = display.unit else { return "Jetzt: " + display.value }
        return display.isText ? "Jetzt: \(display.value) · \(unit)" : "Jetzt: \(display.value) \(unit)"
    }

    @ViewBuilder
    private func placeBadge(_ place: Int?) -> some View {
        ZStack {
            Circle()
                .strokeBorder(place == nil ? Theme.textTertiary : Color.clear, lineWidth: 1.5)
            if let place {
                Circle().fill(Theme.accent)
                Text("\(place)")
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .motionTransition(.pop)
            }
        }
        .frame(width: 26, height: 26)
        .motionAnimation(Motion.bouncy, value: place)
        .accessibilityHidden(true)
    }
}
