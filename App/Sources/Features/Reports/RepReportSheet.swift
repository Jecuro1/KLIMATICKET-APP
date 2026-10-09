import SwiftUI
import SwiftData
import PDFKit
import KlimaCore

/// "Jahresbericht (PDF)": builds "Dein KlimaTicket-Jahr" for a ticket year, shows it in a PDFKit preview and shares it
/// (Mail, Drucken, Dateien …) via ShareLink. Presented from Einstellungen › Daten and the Statistik share menu.
struct RepReportSheet: View {
    /// Ticket year to start with (nil = the active ticket).
    var ticketID: UUID? = nil

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date)
    private var trips: [TripEntity]
    @Query(filter: #Predicate<BenefitEntity> { $0.deletedAt == nil })
    private var benefits: [BenefitEntity]

    @State private var selectedID: UUID?
    @State private var report: RepRenderedReport?
    @State private var isRendering = false
    @State private var failed = false

    private var ticket: TicketEntity? {
        Analytics.activeTicket(in: tickets, selectedID: selectedID ?? ticketID ?? app.settings.selectedTicketID)
    }

    /// Re-render whenever the ticket or anything that changes the numbers changes.
    private var renderKey: String {
        guard let ticket else { return "none" }
        let inPeriod = trips.filter { ticket.period.contains($0.date) }
        let value = inPeriod.reduce(0) { $0 + $1.totalValue }
        let latest = inPeriod.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        return "\(ticket.id)|\(ticket.updatedAt.timeIntervalSince1970)|\(inPeriod.count)|\(Int(value * 100))|\(Int(latest))|\(benefits.count)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SetBackdrop(skyOpacity: 0.35, fadeEnd: 0.35)
                content
            }
            .navigationTitle("Jahresbericht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: renderKey) { await render() }
        .repHaptic(.selection, trigger: selectedID, enabled: app.settings.hapticsEnabled)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let ticket {
            let data = RepReportData.make(ticket: ticket, trips: trips, benefits: benefits, catalog: app.catalog)
            if !data.hasTrips {
                ScrollView {
                    EmptyStateView(symbol: "doc.richtext", title: "Noch nichts zu berichten",
                                   message: "In deinem Ticketjahr \(data.yearLabel) sind noch keine Fahrten erfasst. Sobald du unterwegs warst, entsteht hier dein Jahresbericht.",
                                   actionTitle: "Fahrt erfassen") {
                        dismiss()
                        app.presentAddTrip()
                    }
                    .padding(.top, Theme.Spacing.xxl)
                }
            } else {
                VStack(spacing: Theme.Spacing.s) {
                    header(data)
                        .padding(.horizontal, Theme.Spacing.screen)
                    preview
                }
                .padding(.top, Theme.Spacing.xs)
            }
        } else {
            ScrollView {
                EmptyStateView(symbol: "ticket", title: "Noch kein Ticket",
                               message: "Lege dein KlimaTicket an – dann fasst dir KlimaBilanz dein Ticketjahr als PDF zusammen.")
                    .padding(.top, Theme.Spacing.xxl)
            }
        }
    }

    private func header(_ data: RepReportData) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Kicker(text: "Dein KlimaTicket-Jahr")
                Text(data.yearLabel)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(headerLine(data))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.xs)
            Text(Format.percent(data.summary.amortizedFraction))
                .font(.system(size: 34, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(data.summary.isPaidOff ? Theme.positiveText : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }

    private func headerLine(_ data: RepReportData) -> String {
        var parts = [RepText.trips(data.summary.tripCount)]
        if let report { parts.append(report.pageCount == 1 ? "1 Seite A4" : "\(report.pageCount) Seiten A4") }
        parts.append(data.ticketName)
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            if let report {
                RepPDFPreview(url: report.url, key: report.key)
                    .transition(.opacity)
                    .accessibilityLabel("Vorschau des Jahresberichts, \(report.pageCount) Seiten")
            }
            if isRendering {
                VStack(spacing: Theme.Spacing.s) {
                    ProgressView()
                        .controlSize(.large)
                    Text(report == nil ? "Bericht wird erstellt …" : "Wird aktualisiert …")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(Theme.Spacing.l)
                .frostedCard(cornerRadius: Theme.Radius.tile)
                .transition(.opacity)
            } else if failed {
                EmptyStateView(symbol: "exclamationmark.triangle", title: "Das hat nicht geklappt",
                               message: "Der Bericht ließ sich nicht erstellen. Versuch es bitte noch einmal.",
                               actionTitle: "Erneut versuchen") {
                    Task { await render() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.3), value: isRendering)
    }

    // MARK: Toolbar & actions

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Schließen", systemImage: "xmark") { dismiss() }
        }
        if tickets.count > 1 {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Ticketjahr", selection: Binding(get: { ticket?.id }, set: { selectedID = $0 })) {
                        ForEach(tickets) { item in
                            Text("\(StatsCalc.ticketYearLabel(item.period)) · \(item.name)").tag(Optional(item.id))
                        }
                    }
                } label: {
                    Label("Ticketjahr wählen", systemImage: "calendar")
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let report, ticket != nil {
            RepBottomBar {
                ShareLink(item: report.url,
                          subject: Text("Mein KlimaTicket-Jahr"),
                          message: Text("Mein KlimaTicket-Jahr – erstellt mit KlimaBilanz."),
                          preview: SharePreview(report.url.lastPathComponent, image: Image(uiImage: report.thumbnail ?? UIImage()))) {
                    Label("Teilen oder drucken", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.primary)
                .disabled(isRendering)
                Text("Erstellt mit KlimaBilanz · keine offizielle Auswertung")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: Rendering

    private func render() async {
        guard let ticket else { return }
        let key = renderKey
        let data = RepReportData.make(ticket: ticket, trips: trips, benefits: benefits, catalog: app.catalog)
        guard data.hasTrips else {
            report = nil
            return
        }
        failed = false
        isRendering = true
        // Let the sheet appear (and show the spinner) before the main-actor rendering work starts.
        try? await Task.sleep(for: .milliseconds(LaunchMode.isScreenshot ? 50 : 180))
        guard !Task.isCancelled else { return }
        let rendered = RepPDFRenderer.render(data, key: key)
        withAnimation(.smooth(duration: 0.35)) {
            report = rendered
            failed = rendered == nil
            isRendering = false
        }
    }
}

/// PDFKit preview: continuous vertical pages, fitted to the width, page shadows on the pale sheet background.
struct RepPDFPreview: UIViewRepresentable {
    let url: URL
    let key: String

    final class Coordinator {
        var loadedKey: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.pageShadowsEnabled = true
        view.pageBreakMargins = UIEdgeInsets(top: 10, left: 16, bottom: 14, right: 16)
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.loadedKey != key else { return }
        context.coordinator.loadedKey = key
        view.document = PDFDocument(url: url)
        view.autoScales = true
    }
}
