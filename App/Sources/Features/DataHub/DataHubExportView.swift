import SwiftUI
import SwiftData
import KlimaCore

// MARK: data – Daten & Sicherung › Exportieren (docs/DATA_HUB.md §2): one range for every format (Ticketjahr · Kalenderjahr · Alles),
// one row per format with what is in it and how big it is, a share sheet behind each. Files are built only when shared.

struct DataHubExportView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @State private var range: DataHubRange
    @State private var previews: [DataHubExportFormat: String] = [:]

    /// `range`: CI scenes start on another range.
    init(range: DataHubRange = .ticketYear) {
        _range = State(initialValue: range)
    }

    private var source: DataHubExportSource {
        DataHubExportSource(container: context.container, range: range, selectedTicketID: app.settings.selectedTicketID,
                            emissions: app.catalog.emissions)
    }

    var body: some View {
        List {
            Section {
                Picker("Zeitraum", selection: $range) {
                    ForEach(DataHubRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Theme.Spacing.xs, leading: 0, bottom: Theme.Spacing.xs, trailing: 0))
            } footer: {
                SetFooter(text: "Gilt für Tabellen, Kalender und Text. Die Komplettsicherung enthält immer alles, die Fristen alles ab heute.")
            }
            Section {
                ForEach(DataHubExportFormat.allCases) { format in
                    row(format)
                        .listRowBackground(Theme.surface)
                }
            } header: {
                SetSectionHeader(title: "Formate")
            } footer: {
                SetFooter(text: "Die Datei entsteht erst, wenn du teilst – in Mail, Nachrichten, AirDrop oder „In Dateien sichern“. Sie verlässt dein iPhone nur dorthin, wohin du sie schickst.")
            }
            Section {
                RepReportSettingsRow()
                    .listRowBackground(Theme.surface)
            } header: {
                SetSectionHeader(title: "Zum Drucken")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .listSectionMargins(.horizontal, Theme.Spacing.cardGutter)
        .scrollContentBackground(.hidden)
        .background { SetBackdrop() }
        .tint(Theme.accent)
        .navigationTitle("Exportieren")
        .navigationBarTitleDisplayMode(.inline)
        .haptic(.selection, trigger: range)
        .task(id: range) { await loadPreviews() }
    }

    private func row(_ format: DataHubExportFormat) -> some View {
        let preview = previews[format]
        let isEmpty = source.isEmpty(format, previews: previews)
        return shareLink(format) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(format.title)
                            .foregroundStyle(Theme.textPrimary)
                        Text(format.line.replacingOccurrences(of: " · ", with: "\u{00A0}·\u{00A0}"))   // the type stays with its word
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(DataHubText.keep(preview ?? "Wird gezählt …"))
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(isEmpty ? Theme.textTertiary : Theme.accentText)
                            .contentTransition(.numericText())
                            .redacted(reason: preview == nil ? .placeholder : [])
                    }
                } icon: {
                    SetIconTile(symbol: format.symbol, tint: tint(format))
                }
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isEmpty ? Theme.textTertiary : Theme.accentText)
                    .accessibilityHidden(true)
            }
            .motionAnimation(Motion.number, value: preview)
        }
        .disabled(isEmpty)
        .accessibilityHint(isEmpty ? "Nichts zu exportieren in diesem Zeitraum" : "Öffnet das Teilen-Menü")
    }

    @ViewBuilder
    private func shareLink<Label: View>(_ format: DataHubExportFormat, @ViewBuilder label: () -> Label) -> some View {
        let source = self.source
        let subject = Text("KlimaBilanz – \(format.title)")
        let preview = SharePreview("KlimaBilanz – \(format.title)")
        switch format {
        case .backup:
            ShareLink(item: DataHubJSONItem(source: source), subject: subject, preview: preview, label: label)
        case .tripsCSV, .monthlyCSV:
            ShareLink(item: DataHubCSVItem(source: source, format: format), subject: subject, preview: preview, label: label)
        case .tripsCalendar, .deadlinesCalendar:
            ShareLink(item: DataHubCalendarItem(source: source, format: format), subject: subject, preview: preview, label: label)
        case .yearText:
            ShareLink(item: DataHubTextItem(source: source), subject: subject, preview: preview, label: label)
        }
    }

    private func tint(_ format: DataHubExportFormat) -> Color {
        switch format {
        case .backup: Theme.dusk
        case .tripsCSV: Theme.pine
        case .monthlyCSV: Theme.eco
        case .tripsCalendar: Theme.glacier
        case .deadlinesCalendar: Theme.summit
        case .yearText: Theme.dawn
        }
    }

    private func loadPreviews() async {
        let source = self.source
        let lines = await Task.detached(priority: .userInitiated) { source.previews() }.value
        withMotion(Motion.number) { previews = lines }
    }
}
