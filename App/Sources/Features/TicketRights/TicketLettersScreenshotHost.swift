import SwiftUI
import SwiftData
import PDFKit
import KlimaCore

/// CI screenshot routes of the Ticket-Schreiben (`-KBScreenshot <screen> -KBDemo YES`, demo data, no network). The letters are
/// written by the fictional holder „Maria Beispiel, Musterweg 1, 1234 Musterstadt“ – no real person or address anywhere.
/// - `lettersObjection` / `lettersObjectionPreview` / `lettersReminder`: the Widerspruchsbrief (top, A4 preview with the hint,
///   the reminder set)
/// - `lettersEmptyAddress`: the same without name, address and deadline (blank lines, progress)
/// - `lettersCancellation` / `lettersCancellationPreview`: ordinary cancellation (fee line from the advisor quote)
/// - `lettersExtraordinary`: cancellation for an important reason (illness) with the four-week window
/// - `lettersCancellationEarly`: month 4 – ordinary cancellation not possible yet, from which date
/// - `lettersInstallments` / `lettersInstallmentsList`: the Raten-Übersicht (summary, and the timeline of 12 installments)
/// - `lettersEntry` / `lettersCancelEntry`: the entries in the Ticket-Ratgeber
/// - `lettersAX5` / `lettersAX5Preview`: the Widerspruchsbrief at the largest accessibility text size
/// - `lettersSuggestion`: the deadline picker shows only a suggestion (not taken over yet): nothing in the letter, the bar says what is missing
/// - `lettersOlderAGB`: a ticket that began before 1.1.2026 – the hint block says an earlier version of the AGB may apply
/// - `lettersPDF` / `lettersPDFExtra`: the PDF of the Widerspruchsbrief and of the longest cancellation letter, drawn by
///   `LetterPDF`, read back with PDFKit (pages, extractable text, title) and page 1 shown – proof that it is a real document
struct TicketLettersScreenshotHost: View {
    static let screens: Set<String> = [
        "lettersObjection", "lettersObjectionPreview", "lettersReminder", "lettersEmptyAddress", "lettersCancellation",
        "lettersCancellationPreview", "lettersExtraordinary", "lettersCancellationEarly", "lettersInstallments",
        "lettersInstallmentsList", "lettersEntry", "lettersCancelEntry", "lettersAX5", "lettersAX5Preview", "lettersPDF",
        "lettersPDFExtra", "lettersSuggestion", "lettersOlderAGB",
    ]

    let screen: String

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date) private var trips: [TripEntity]
    @Environment(AppState.self) private var app
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady, let ticket = tickets.first {
                content(for: ticket)
            } else {
                Color.clear.ambientBackground()
            }
        }
        .dynamicTypeSize(screen.hasPrefix("lettersAX5") ? .accessibility5 : .large)
        .onAppear {
            guard !isReady else { return }
            AdvDemoData.enrich(context: modelContext)   // SEPA auto-renewal on, like the Ratgeber demo
            if let ticket = tickets.first {
                ticket.holderName = Self.holder.name
                ticket.isMonthlyPayment = screen.hasPrefix("lettersInstallments") || screen == "lettersEntry"
                try? modelContext.save()
            }
            isReady = true
        }
    }

    // MARK: Fixtures

    static let holder = LetterSender(name: "Maria Beispiel", street: "Musterweg 1", postcode: "1234", place: "Musterstadt")

    private func filledForm(_ context: TicketLetterContext) -> LetterForm {
        var form = LetterForm()
        form.name = Self.holder.name
        form.street = Self.holder.street
        form.postcode = Self.holder.postcode
        form.place = Self.holder.place
        form.ticketNumber = context.number
        return form
    }

    /// Only the ticket number (it comes from the ticket) – name, address and deadline are still open.
    private func emptyForm(_ context: TicketLetterContext) -> LetterForm {
        var form = LetterForm()
        form.ticketNumber = context.number
        return form
    }

    private var today: Date { Calendar.vienna.startOfDay(for: Date()) }

    private func day(_ offset: Int) -> Date { Calendar.vienna.date(byAdding: .day, value: offset, to: today) ?? today }

    // MARK: Screens

    @ViewBuilder
    private func content(for ticket: TicketEntity) -> some View {
        let context = TicketLetterContext(ticket)
        switch screen {
        case "lettersObjection", "lettersAX5":
            ObjectionLetterView(context: context, preset: ObjectionPreset(form: filledForm(context), deadline: day(40)))
        case "lettersObjectionPreview", "lettersAX5Preview":
            ObjectionLetterView(context: context, preset: ObjectionPreset(form: filledForm(context), deadline: day(40)),
                                screenshotAnchor: .preview)
        case "lettersReminder":
            ObjectionLetterView(context: context, preset: ObjectionPreset(form: filledForm(context), deadline: day(40),
                                                                         reminderDates: LetterDeadline(day: day(40)).reminders().map(\.fireDate)),
                                screenshotAnchor: .reminder)
        case "lettersSuggestion":
            ObjectionLetterView(context: context, preset: ObjectionPreset(form: filledForm(context), deadline: nil, showsDeadlineSuggestion: true))
        case "lettersOlderAGB":
            ObjectionLetterView(context: olderContext(context), preset: ObjectionPreset(form: filledForm(context), deadline: day(40)),
                                screenshotAnchor: .preview)
        case "lettersEmptyAddress":
            ObjectionLetterView(context: context, preset: ObjectionPreset(form: emptyForm(context), deadline: nil))
        case "lettersCancellation":
            CancellationLetterView(context: context, preset: CancellationPreset(form: filledForm(context), mode: .ordinary))
        case "lettersCancellationPreview":
            CancellationLetterView(context: context, preset: CancellationPreset(form: filledForm(context), mode: .ordinary),
                                   screenshotAnchor: .preview)
        case "lettersExtraordinary":
            CancellationLetterView(context: context, preset: CancellationPreset(form: filledForm(context), mode: .extraordinary,
                                                                               reason: .illness, reasonDate: day(-9)))
        case "lettersCancellationEarly":
            CancellationLetterView(context: earlyContext(context), preset: CancellationPreset(form: filledForm(context), mode: nil))
        case "lettersInstallments":
            NavigationStack { InstallmentsView(context: context, tripValue: tripValue(for: ticket)) }
        case "lettersInstallmentsList":
            NavigationStack { InstallmentsView(context: context, tripValue: tripValue(for: ticket)) }
                .defaultScrollAnchor(.bottom)
        case "lettersEntry":
            NavigationStack { AdvisorView(ticket: ticket, initialAnchor: .renewalReminder) }
        case "lettersCancelEntry":
            NavigationStack { AdvisorView(ticket: ticket, initialAnchor: .lettersCancellation) }
        case "lettersPDF":
            LettersPDFCheck(content: RenewalObjectionLetter.make(RenewalObjectionLetter.Input(
                sender: Self.holder, ticketNumber: context.number, productName: context.ticket.name, validUntil: context.ticket.end,
                deadline: day(40), place: Self.holder.place, letterDate: today)))
        case "lettersPDFExtra":
            LettersPDFCheck(content: CancellationLetter.make(CancellationLetter.Input(
                ticket: context.ticket, ticketNumber: context.number, sender: Self.holder,
                kind: .extraordinary(.illness, since: day(-9)), place: Self.holder.place, letterDate: today))
                ?? RenewalObjectionLetter.make(RenewalObjectionLetter.Input(
                    sender: Self.holder, ticketNumber: context.number, productName: context.ticket.name, validUntil: context.ticket.end,
                    deadline: day(40), place: Self.holder.place, letterDate: today)))
        default:
            Color.clear.ambientBackground()
        }
    }

    /// The demo ticket moved to validity month 4: the ordinary cancellation is not possible yet.
    private func earlyContext(_ context: TicketLetterContext) -> TicketLetterContext {
        var early = context
        let start = Calendar.vienna.date(byAdding: .day, value: -100, to: today) ?? today
        early.ticket.start = start
        early.ticket.end = TicketPeriod.standardEnd(for: start)
        return early
    }

    /// The demo ticket moved to a start in 2025: it was bought under an earlier version of the AGB.
    private func olderContext(_ context: TicketLetterContext) -> TicketLetterContext {
        var older = context
        let start = Calendar.vienna.date(from: DateComponents(year: 2025, month: 12, day: 1)) ?? today
        older.ticket.start = start
        older.ticket.end = TicketPeriod.standardEnd(for: start)
        return older
    }

    private func tripValue(for ticket: TicketEntity) -> Double {
        AdvAdvisor.advice(for: ticket, trips: trips, app: app).summary.totalValue
    }
}

/// CI proof that the PDF is a real document: draws it with `LetterPDF`, reads it back with PDFKit and shows what it finds.
private struct LettersPDFCheck: View {
    let content: LetterContent

    var body: some View {
        let data = LetterPDF.data(for: content)
        let document = PDFDocument(data: data)
        let text = document?.string ?? ""
        let title = document?.documentAttributes?["Title"] as? String
        let page = document?.page(at: 0)
        let image = page?.thumbnail(of: CGSize(width: 595, height: 842), for: .mediaBox)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("PDF-Prüfung")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                check("\(document?.pageCount ?? 0) Seite(n), \(data.count / 1024) KB", ok: (document?.pageCount ?? 0) >= 1)
                check("\(text.count) Zeichen Text auslesbar (markierbar)", ok: text.count > 200)
                check("Titel: \(title ?? "fehlt")", ok: title == content.documentTitle)
                check("Beginnt mit: \(text.split(separator: "\n").first.map(String.init) ?? "–")", ok: !text.isEmpty)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .background(Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
                        .accessibilityHidden(true)
                }
            }
            .padding(Theme.Spacing.m)
            .padding(.top, Theme.Spacing.xl)
        }
        .background(Theme.sheetBackground)
    }

    private func check(_ text: String, ok: Bool) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ok ? Theme.positiveText : Theme.negativeText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
