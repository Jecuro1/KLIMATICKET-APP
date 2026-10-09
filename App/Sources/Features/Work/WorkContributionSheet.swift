import SwiftUI
import SwiftData
import KlimaCore

/// "Arbeitgeberzuschuss": enter what the employer pays for the ticket, right from "Arbeit & Steuer".
/// Live preview of the own share; saved through Repository (sync, widgets, reminders stay consistent).
struct WorkContributionSheet: View {
    let ticket: TicketEntity
    /// Called after saving (the presenter plays the success haptic – this sheet is gone by then).
    var onSave: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 46
    @State private var draft: Double

    init(ticket: TicketEntity, onSave: @escaping () -> Void = {}) {
        self.ticket = ticket
        self.onSave = onSave
        _draft = State(initialValue: min(max(0, ticket.employerContribution), max(0, ticket.price + ticket.addOnPrice)))
    }

    private var fullPrice: Double { max(0, ticket.price + ticket.addOnPrice) }
    private var contribution: Double { min(max(0, draft), fullPrice) }
    private var ownShare: Double { fullPrice - contribution }
    private var hasChanges: Bool { abs(contribution - ticket.employerContribution) > 0.004 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    preview
                        .listRowBackground(Theme.surface)
                }
                Section {
                    Group {
                        WorkDecimalField(title: "Zuschuss", symbol: "building.2.fill", tint: Theme.glacier,
                                         value: $draft, unit: "€", fractionDigits: 2, range: 0...max(fullPrice, 0.01))
                        presets
                    }
                    .listRowBackground(Theme.surface)
                } header: {
                    SetSectionHeader(title: "Arbeitgeberzuschuss")
                } footer: {
                    SetFooter(text: "Steuerfrei nach § 26 Z 5 lit. b EStG. KlimaBilanz misst deine Bilanz dann an deinem Eigenanteil – die Obergrenze für Dienstreisen und der Hinweis zum Pendlerpauschale passen sich automatisch an.")
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(Theme.Spacing.l)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background { SetBackdrop(skyOpacity: 0.35, fadeEnd: 0.35) }
            .navigationTitle("Zuschuss")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .fontWeight(.semibold)
                        .disabled(!hasChanges)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Kicker(text: "Dein Eigenanteil")
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                WorkEuroNumeral(value: ownShare, size: numeralSize, color: contribution > 0 ? Theme.positive : Theme.textPrimary)
                Text("von \(Format.euro(fullPrice, decimals: 0))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            WorkSplitBar(parts: [
                .init(label: "Arbeitgeber", value: contribution,
                      detail: fullPrice > 0 ? "\(Format.euro(contribution, decimals: 0)) · \(Format.percent(contribution / fullPrice))"
                                            : Format.euro(contribution, decimals: 0),
                      color: Theme.glacier),
                .init(label: "Du", value: ownShare, detail: Format.euro(ownShare, decimals: 0), color: Theme.dawn),
            ], height: 10)
            .animation(.snappy, value: contribution)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dein Eigenanteil")
        .accessibilityValue("\(Format.euro(ownShare, decimals: 0)) von \(Format.euro(fullPrice, decimals: 0)), Arbeitgeber \(Format.euro(contribution, decimals: 0))")
    }

    // MARK: Presets

    private var presets: some View {
        HStack(spacing: Theme.Spacing.xs) {
            presetButton("Keiner", value: 0)
            presetButton("Hälfte", value: (fullPrice / 2).rounded())
            presetButton("Ganzes Ticket", value: fullPrice)
        }
        .padding(.vertical, 2)
    }

    private func presetButton(_ title: String, value: Double) -> some View {
        let isActive = abs(contribution - value) < 0.5
        return Button {
            withAnimation(.snappy) { draft = value }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .foregroundStyle(isActive ? Theme.accentText : Theme.textPrimary)
        }
        .buttonStyle(.glass)
        .tint(isActive ? Theme.accent : nil)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func save() {
        Repository(context: context, app: app).workSetEmployerContribution(contribution, for: ticket)
        onSave()
        dismiss()
    }
}
