import SwiftUI
import UIKit
import KlimaCore

/// „Widerspruchsbrief“ (docs/TICKET_LETTERS.md §1): the written objection to the automatic renewal of a KlimaTicket Ö paid by
/// SEPA. Fields, a live A4 preview, the honest hint about what the AGB say, PDF / print and two local reminders before the
/// deadline from the holder's own renewal letter.
struct ObjectionLetterView: View {
    let context: TicketLetterContext
    static let fileName = "Widerspruch-KlimaTicket.pdf"
    /// Scrolls to a block on appear (screenshot routes).
    var screenshotAnchor: LetterAnchor? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var form: LetterForm
    @State private var deadline: Date?
    @State private var remembers: Bool
    @State private var reminderDates: [Date]
    @State private var reminderState: ReminderState = .idle
    @State private var reminderTrigger = 0

    private enum ReminderState: Equatable {
        case idle, working, denied
    }

    /// `preset` fills the sheet for CI screenshots (nothing is read from or written to the device then).
    init(context: TicketLetterContext, preset: ObjectionPreset? = nil, screenshotAnchor: LetterAnchor? = nil) {
        self.context = context
        self.screenshotAnchor = screenshotAnchor
        let remembered = preset == nil ? LetterStore.loadSender() : nil
        _form = State(initialValue: preset?.form ?? LetterForm.initial(for: context, remembered: remembered))
        _deadline = State(initialValue: preset == nil ? LetterStore.deadline(for: context.id) : preset?.deadline)
        _remembers = State(initialValue: preset?.remembers ?? LetterStore.remembersSender)
        _reminderDates = State(initialValue: preset?.reminderDates ?? [])
    }

    var body: some View {
        NavigationStack {
            Group {
                switch RenewalObjectionLetter.eligibility(for: context.ticket) {
                case .available: formView
                case .nothingToDo: notice(.nothingToDo)
                case .notApplicable: notice(.notApplicable)
                }
            }
            .background(Theme.sheetBackground)
            .navigationTitle("Widerspruchsbrief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .environment(\.locale, Format.locale)
    }

    // MARK: Letter

    private var content: LetterContent {
        RenewalObjectionLetter.make(RenewalObjectionLetter.Input(
            sender: form.sender, recipient: form.recipient, ticketNumber: form.ticketNumber, productName: context.ticket.name,
            validUntil: context.ticket.end, deadline: deadline, place: form.placeForLetter, letterDate: form.letterDate))
    }

    /// The required fields and how many of them are filled in.
    private func progress(_ content: LetterContent) -> (done: Int, total: Int) {
        let required: [KlimaCore.LetterField] = [.name, .street, .postcode, .place, .ticketNumber, .deadline]
        let missing = Set(content.missingFields)
        return (required.filter { !missing.contains($0) }.count, required.count)
    }

    // MARK: Form

    private var formView: some View {
        let letter = content
        let steps = progress(letter)
        return ScrollViewReader { proxy in
            Form {
                Section {
                    LetterHero(kicker: "Widerspruchsbrief", title: "Dein Widerspruch",
                               subtitle: "\(context.ticket.name) – fertig formuliert nach den AGB. Du trägst ein, was nur du weißt, druckst aus und unterschreibst.",
                               symbol: "envelope.fill", done: steps.done, total: steps.total)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.xs, bottom: 0, trailing: Theme.Spacing.xs))
                deadlineSection
                LetterSenderSection(form: $form)
                LetterDateSection(form: $form, numberFooter: "Die Nummer steht auf deiner Karte und in deinem Verlängerungsbrief.")
                LetterRecipientSection(form: $form)
                LetterRememberSection(remembers: $remembers)
                Section {
                    LetterPreviewCard(content: letter)
                        .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.m, bottom: Theme.Spacing.s, trailing: Theme.Spacing.m))
                        .id(LetterAnchor.preview)
                    LetterHintBlock(title: "So kommt der Brief an", paragraphs: [RenewalObjectionLetter.deliveryHint, RenewalObjectionLetter.alternativeWaysHint])
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text("Vorschau")
                }
                .listRowBackground(Color.clear)
                reminderSection
                    .id(LetterAnchor.reminder)
                LetterInlineActions(content: letter, fileName: Self.fileName, printJobName: letter.documentTitle)
                Section {
                    Text(LetterText.notLegalAdvice)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .modifier(LetterBottomBar(content: letter, fileName: Self.fileName, printJobName: letter.documentTitle))
            .onChange(of: form.sender) { _, sender in
                if remembers { LetterStore.saveSender(sender) }
            }
            .onChange(of: remembers) { _, isOn in
                LetterStore.remembersSender = isOn
                if isOn { LetterStore.saveSender(form.sender) }
            }
            .onChange(of: deadline) { _, newValue in
                LetterStore.setDeadline(newValue, for: context.id)
                reschedule(for: newValue)
            }
            .task {
                if let screenshotAnchor {
                    try? await Task.sleep(for: .milliseconds(350))
                    proxy.scrollTo(screenshotAnchor, anchor: .top)
                }
                guard !LaunchMode.isSandboxed else { return }
                reminderDates = await LetterReminders.scheduledDates(ticketID: context.id)
            }
        }
    }

    // MARK: Deadline

    private var deadlineSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Frist laut deinem Brief")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                if let deadline {
                    HStack(spacing: Theme.Spacing.s) {
                        DatePicker("Frist laut deinem Brief", selection: Binding(get: { deadline }, set: { self.deadline = $0 }),
                                   displayedComponents: .date)
                            .labelsHidden()
                        Spacer(minLength: Theme.Spacing.xs)
                        deadlinePill(deadline)
                    }
                } else {
                    Button {
                        withMotion(Motion.snappy) {
                            deadline = Calendar.vienna.date(byAdding: .day, value: 14, to: Calendar.vienna.startOfDay(for: Date()))
                        }
                    } label: {
                        Label("Datum aus deinem Brief wählen", systemImage: "calendar.badge.plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accentText)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .motionAnimation(Motion.smooth, value: deadline != nil)
            .haptic(.selection, trigger: deadline)
        } header: {
            Text("Frist")
        } footer: {
            Text(LetterText.deadlineCaption)
        }
    }

    private func deadlinePill(_ date: Date) -> some View {
        let status = LetterDeadline(day: date).status()
        let isPassed: Bool = { if case .passed = status { return true } else { return false } }()
        return Label(LetterText.deadlineStatus(status), systemImage: isPassed ? "exclamationmark.triangle.fill" : "hourglass")
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(isPassed ? Theme.negativeText : Theme.accentText)
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .contentTransition(.numericText())
    }

    // MARK: Reminders

    private var reminderSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    TktIconTile(symbol: reminderDates.isEmpty ? "bell.fill" : "bell.badge.fill", color: Theme.glacier)
                        .symbolBounce(on: reminderTrigger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminderDates.isEmpty ? "Erinnerung setzen" : "Erinnerung ist gesetzt")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(reminderSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                if reminderState == .denied {
                    deniedNotice
                }
                reminderButton
            }
            .motionAnimation(Motion.smooth, value: reminderDates)
            .motionAnimation(Motion.smooth, value: reminderState)
            .haptic(.success, trigger: reminderTrigger)
        } header: {
            Text("Erinnerung")
        } footer: {
            Text("Die Erlaubnis für Mitteilungen fragen wir erst, wenn du hier tippst. Du findest die Erinnerung danach unter Einstellungen › Alarme.")
        }
    }

    private var reminderSubtitle: String {
        if !reminderDates.isEmpty {
            // „17. Dez. und 21. Dez. 2026, jeweils um 9:00 Uhr.“
            let days = reminderDates.map { Format.dayMonth($0) }.joined(separator: " und ")
            let year = reminderDates.last.map { Calendar.vienna.component(.year, from: $0) } ?? 0
            return "\(days) \(year), jeweils um 9:00 Uhr."
        }
        guard let deadline else { return "Wähle zuerst die Frist aus deinem Brief." }
        if LetterDeadline(day: deadline).reminders().isEmpty { return "Die Frist ist zu nah oder vorbei – eine Erinnerung hilft nicht mehr." }
        return "5 Tage und 1 Tag vor der Frist, jeweils um 9:00 Uhr."
    }

    private var deniedNotice: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Label("Mitteilungen sind ausgeschaltet", systemImage: "bell.slash.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.summitText)
            Text("Erlaube Mitteilungen für KlimaBilanz in den iOS-Einstellungen, damit die Erinnerung ankommt.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Einstellungen öffnen") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accentText)
            .buttonStyle(.plain)
            .frame(minHeight: 44, alignment: .leading)
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.dawn.opacity(0.10), in: .rect(cornerRadius: Theme.Radius.chip, style: .continuous))
        .motionTransition(.rise)
    }

    @ViewBuilder
    private var reminderButton: some View {
        if reminderDates.isEmpty {
            Button {
                setReminder()
            } label: {
                Label(reminderState == .working ? "Einen Moment …" : "Erinnerung setzen", systemImage: "bell.badge")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glass)
            .disabled(deadline == nil || LetterDeadline(day: deadline ?? Date()).reminders().isEmpty || reminderState == .working)
        } else {
            Button(role: .destructive) {
                Task {
                    await LetterReminders.cancelNow(ticketID: context.id)
                    withMotion(Motion.smooth) { reminderDates = [] }
                }
            } label: {
                Label("Erinnerung entfernen", systemImage: "bell.slash")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.negativeText)
        }
    }

    private func setReminder() {
        guard let deadline, reminderState != .working else { return }
        reminderState = .working
        Task {
            let outcome = await LetterReminders.schedule(ticketID: context.id, ticketName: context.ticket.name, deadline: deadline)
            apply(outcome)
        }
    }

    /// A new deadline moves existing reminders along (the permission is there already); no deadline removes them.
    private func reschedule(for newDeadline: Date?) {
        guard !reminderDates.isEmpty, !LaunchMode.isSandboxed else { return }
        guard let newDeadline else {
            Task {
                await LetterReminders.cancelNow(ticketID: context.id)
                reminderDates = []
            }
            return
        }
        Task {
            let outcome = await LetterReminders.schedule(ticketID: context.id, ticketName: context.ticket.name, deadline: newDeadline)
            apply(outcome, announce: false)
        }
    }

    private func apply(_ outcome: LetterReminders.Outcome, announce: Bool = true) {
        switch outcome {
        case .scheduled(let dates):
            withMotion(Motion.bouncy) {
                reminderDates = dates
                reminderState = .idle
            }
            reminderTrigger += 1
            if announce {
                app.showToast("bell.badge.fill", "Erinnerung gesetzt", "Du bekommst sie kurz vor der Frist")
            }
        case .denied:
            withMotion(Motion.smooth) {
                reminderDates = []
                reminderState = .denied
            }
        case .tooLate:
            withMotion(Motion.smooth) {
                reminderDates = []
                reminderState = .idle
            }
        }
    }

    // MARK: Notices

    private func notice(_ kind: RenewalObjectionLetter.Eligibility) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if kind == .nothingToDo {
                    LetterNoticeCard(symbol: "checkmark.circle.fill", title: LetterText.nothingToDo,
                                     message: "Einen Widerspruch brauchst du nur, wenn du per SEPA zahlst und dein Ticket deshalb von selbst verlängert wird. Das stellst du in den Ticket-Angaben unter „Verlängerung“ ein.",
                                     tone: Theme.positive)
                } else {
                    LetterNoticeCard(symbol: "info.circle.fill", title: "Dieser Brief passt nicht",
                                     message: context.ticket.family == .regional ? LetterText.regionalTicket : LetterText.otherTicket)
                }
            }
            .padding(Theme.Spacing.m)
        }
    }
}

/// Screenshot presets of the objection sheet.
struct ObjectionPreset {
    var form: LetterForm
    var deadline: Date?
    var remembers = false
    var reminderDates: [Date] = []
}
