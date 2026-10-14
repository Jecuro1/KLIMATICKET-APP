import SwiftUI
import KlimaCore

// Alarme einsehen (docs/ROUTES_ALARMS.md §2): the last 30 delivered notices, newest first, kept on this device only.

struct AlarmHistoryView: View {
    let model: AlarmsModel
    @State private var confirmsClear = false

    var body: some View {
        List {
            if model.history.isEmpty {
                Section {
                    EmptyStateView(symbol: "tray", title: "Noch nichts angekommen",
                                   message: "Hier stehen die letzten 30 Mitteilungen, die auf diesem Gerät angekommen sind.")
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(model.history) { notice in
                        entry(notice)
                            .listRowBackground(Theme.surface)
                    }
                } footer: {
                    Text("\(model.history.count) von 30 · nur auf diesem Gerät gespeichert")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.sheetBackground)
        .navigationTitle("Verlauf")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Leeren", role: .destructive) { confirmsClear = true }
                }
            }
        }
        .confirmationDialog("Verlauf leeren?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Verlauf leeren", role: .destructive) { model.clearHistory() }
        } message: {
            Text("Der Verlauf auf diesem Gerät wird geleert. Mitteilungen, die noch in der Mitteilungs-Zentrale stehen, bleiben dort.")
        }
    }

    private func entry(_ notice: DeliveredNotice) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: notice.kind.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(notice.kind.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if !notice.body.isEmpty {
                    Text(notice.body)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Theme.Spacing.xs)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.relativeDay(notice.deliveredAt))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(Format.time(notice.deliveredAt))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
