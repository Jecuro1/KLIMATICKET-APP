import SwiftUI
import SwiftData
import KlimaCore

// MARK: delaydiary – „Nachweis als PDF“: pick the months, see the PDF, share it (docs/DELAY_DIARY.md §6)

/// The months of the diary as toggles (those with a late Fahrt ticked), the holder's name on or off, a PDFKit preview of the
/// real file and the share sheet. The PDF is drawn on the device; only the share sheet takes it anywhere.
struct DelayReportSheet: View {
    let ticket: TicketEntity
    let year: DelayDiaryYear

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var selection: Set<Int>
    @State private var includesName = true
    @State private var rendered: (url: URL, pages: Int, key: String)?
    @State private var failed = false
    @State private var picked = 0

    init(ticket: TicketEntity, year: DelayDiaryYear) {
        self.ticket = ticket
        self.year = year
        _selection = State(initialValue: DelayReportBuilder.defaultSelection(year))
    }

    private var holderName: String? {
        let name = ticket.holderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private var report: DelayReport { DelayReportBuilder.make(year, months: selection) }

    private var renderKey: String {
        let rows = report.rows.map { "\($0.id)\($0.minutes)\($0.source.rawValue)" }.joined()
        return "\(selection.sorted())|\(includesName)|\(year.threshold)|\(year.options.scope.rawValue)|\(rows.hashValue)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        monthPicker
                        if holderName != nil { nameToggle }
                        preview
                    }
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.bottom, Theme.Spacing.m)
                }
                .scrollIndicators(.hidden)
            }
            .background(Theme.sheetBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { shareBar }
            .navigationTitle("Nachweis als PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel("Schließen")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .haptic(.selection, trigger: picked)
        .task(id: renderKey) { render() }
        .accessibilityIdentifier("delay.report")
    }

    // MARK: Months

    private var monthPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(text: "Welche Monate")
                Spacer(minLength: Theme.Spacing.xs)
                Button(allSelected ? "Keine" : "Alle") {
                    withMotion(Motion.snappy) {
                        selection = allSelected ? [] : Set(year.months.map(\.index))
                    }
                    picked += 1
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 200 : 104), spacing: Theme.Spacing.xs)],
                      spacing: Theme.Spacing.xs) {
                ForEach(year.months) { month in
                    monthChip(month)
                }
            }
        }
    }

    private var allSelected: Bool { selection.count == year.months.count }

    private func monthChip(_ month: DelayMonth) -> some View {
        let isOn = selection.contains(month.index)
        return Button {
            withMotion(Motion.snappy) {
                if isOn { selection.remove(month.index) } else { selection.insert(month.index) }
            }
            picked += 1
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOn ? Theme.onAccent : Theme.textTertiary)
                    .symbolReplaceTransition()
                VStack(alignment: .leading, spacing: 0) {
                    Text(DelayDiaryFormat.shortMonth(month.start) + " " + String(Calendar.vienna.component(.year, from: month.start)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? Theme.onAccent : Theme.textPrimary)
                    Text(month.lateCount == 1 ? "1 verspätet" : "\(month.lateCount) verspätet")
                        .font(.caption2)
                        .foregroundStyle(isOn ? Theme.onAccent.opacity(0.85) : Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isOn ? AnyShapeStyle(Theme.prominentTint) : AnyShapeStyle(Theme.surfaceSecondary),
                        in: .rect(cornerRadius: Theme.Radius.chip, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(DelayDiaryFormat.monthTitle(month)), \(month.lateCount) verspätet")
        .accessibilityValue(isOn ? "im PDF" : "nicht im PDF")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var nameToggle: some View {
        GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.tile) {
            Toggle(isOn: $includesName) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Name aufs PDF")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(holderName ?? "")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        if selection.isEmpty {
            GlassCard {
                EmptyStateView(symbol: "calendar.badge.plus", title: "Kein Monat gewählt",
                               message: "Wähle oben mindestens einen Gültigkeitsmonat für das PDF.")
            }
        } else if let rendered {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("\(report.rows.count == 1 ? "1 verspätete Fahrt" : "\(report.rows.count) verspätete Fahrten") · \(rendered.pages == 1 ? "1 Seite A4" : "\(rendered.pages) Seiten A4")")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
                RepPDFPreview(url: rendered.url, key: rendered.key)
                    .frame(height: 520)
                    .clipShape(.rect(cornerRadius: Theme.Radius.tile, style: .continuous))
                    .accessibilityLabel("Vorschau des PDF, \(rendered.pages) Seiten")
            }
            .motionTransition(.rise)
        } else if failed {
            GlassCard {
                EmptyStateView(symbol: "exclamationmark.triangle", title: "Das hat nicht geklappt",
                               message: "Das PDF ließ sich nicht erstellen. Versuch es bitte noch einmal.",
                               actionTitle: "Erneut versuchen") { render() }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private var shareBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if let rendered, !selection.isEmpty {
                ShareLink(item: rendered.url,
                          subject: Text(DelayDiaryText.title),
                          message: Text("Mein Verspätungs-Tagebuch – erstellt mit KlimaBilanz."),
                          preview: SharePreview(rendered.url.lastPathComponent)) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("delay.report.share")
            }
            Text("Persönliche Aufzeichnung · keine amtlichen Pünktlichkeitswerte")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xs)
        .background(Theme.sheetBackground.opacity(0.94).ignoresSafeArea())
    }

    // MARK: Rendering

    private func render() {
        guard !selection.isEmpty else { return }
        let head = DelayReportHead(ticketName: ticket.name, yearLabel: StatsCalc.ticketYearLabel(ticket.period),
                                   validFrom: ticket.startDate, validTo: ticket.endDate,
                                   holderName: includesName ? holderName : nil, createdAt: Date())
        do {
            let file = try DelayReportPDF.write(report, head: head)
            withMotion(Motion.smooth) {
                rendered = (file.url, file.pages, renderKey)
                failed = false
            }
        } catch {
            failed = true
        }
    }
}
