import SwiftUI
import KlimaCore

/// „Kündigungsschreiben“ (docs/TICKET_LETTERS.md §2): the cancellation of a KlimaTicket Ö – without a reason from the 7th
/// validity month (fee = one monthly amount, AGB 17.1) or, at any time, for an important reason (moving abroad, illness of at
/// least three months, unemployment; no fee; four weeks, AGB 17.2). Before the 7th month it says from which date the ordinary
/// cancellation is possible and never produces an ordinary letter. The letter accompanies the signed Kündigungsformular and the
/// card at a Servicestelle, it does not replace them.
struct CancellationLetterView: View {
    let context: TicketLetterContext
    private var fileName: String { mode == .ordinary ? "Kuendigung-KlimaTicket.pdf" : "Ausserordentliche-Kuendigung-KlimaTicket.pdf" }
    /// Scrolls to a block on appear (screenshot routes).
    var screenshotAnchor: LetterAnchor? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var form: LetterForm
    @State private var mode: Mode
    @State private var reason: CancellationLetter.Reason
    @State private var reasonDate: Date?
    @State private var remembers: Bool

    enum Mode: Hashable {
        case ordinary, extraordinary
    }

    /// `preset` fills the sheet for CI screenshots (nothing is read from or written to the device then).
    init(context: TicketLetterContext, preset: CancellationPreset? = nil, screenshotAnchor: LetterAnchor? = nil) {
        self.context = context
        self.screenshotAnchor = screenshotAnchor
        let remembered = preset == nil ? LetterStore.loadSender() : nil
        let status = CancellationLetter.status(for: context.ticket)
        _form = State(initialValue: preset?.form ?? LetterForm.initial(for: context, remembered: remembered))
        _mode = State(initialValue: preset?.mode ?? (status.canWriteOrdinary ? .ordinary : .extraordinary))
        _reason = State(initialValue: preset?.reason ?? .unemployment)
        _reasonDate = State(initialValue: preset?.reasonDate)
        _remembers = State(initialValue: preset?.remembers ?? LetterStore.remembersSender)
    }

    private var status: CancellationLetter.Status { CancellationLetter.status(for: context.ticket) }

    var body: some View {
        NavigationStack {
            Group {
                switch status.kind {
                case .ordinaryPossible, .notYet: formView
                case .beforeStart: notice(symbol: "calendar.badge.clock", title: "Dein Ticket gilt noch nicht",
                                          message: "Vor dem ersten Gültigkeitstag gibst du das Ticket bei einer Servicestelle gebührenfrei zurück (AGB Punkt 18.1). Das ist keine Kündigung – dafür brauchst du kein Schreiben.")
                case .expired: notice(symbol: "checkmark.circle.fill", title: "Dein Ticket ist abgelaufen",
                                      message: "Es gibt nichts mehr zu kündigen.")
                case .regionalTicket: notice(symbol: "info.circle.fill", title: "Dieses Schreiben passt nicht", message: LetterText.regionalTicket)
                case .otherTicket: notice(symbol: "info.circle.fill", title: "Dieses Schreiben passt nicht", message: LetterText.otherTicket)
                }
            }
            .background(Theme.sheetBackground)
            .navigationTitle("Kündigungsschreiben")
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

    /// `nil` only when the chosen kind is not possible – the form never offers that.
    private var content: LetterContent? {
        let kind: CancellationLetter.Kind = mode == .ordinary ? .ordinary : .extraordinary(reason, since: reasonDate)
        return CancellationLetter.make(CancellationLetter.Input(
            ticket: context.ticket, ticketNumber: form.ticketNumber, sender: form.sender, recipient: form.recipient, kind: kind,
            place: form.placeForLetter, letterDate: form.letterDate))
    }

    private func progress(_ content: LetterContent) -> (done: Int, total: Int) {
        var required: [KlimaCore.LetterField] = [.name, .street, .postcode, .place, .ticketNumber]
        if mode == .extraordinary { required.append(.reasonDate) }
        let missing = Set(content.missingFields)
        return (required.filter { !missing.contains($0) }.count, required.count)
    }

    // MARK: Form

    @ViewBuilder
    private var formView: some View {
        if let letter = content {
            let steps = progress(letter)
            ScrollViewReader { proxy in
                Form {
                    Section {
                        LetterHero(kicker: "Kündigungsschreiben", title: "Deine Kündigung",
                                   subtitle: mode == .ordinary ? "\(context.ticket.name) – ohne Angabe von Gründen, mit dem Kündigungsentgelt aus den AGB."
                                                              : "\(context.ticket.name) – mit wichtigem Grund: ohne Kündigungsentgelt, aber mit Frist und Nachweis.",
                                   symbol: "xmark.seal.fill", done: steps.done, total: steps.total)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.xs, bottom: 0, trailing: Theme.Spacing.xs))
                    modeSection
                    if mode == .extraordinary { reasonSection } else { feeSection }
                    LetterSenderSection(form: $form)
                    LetterDateSection(form: $form, numberFooter: "Die Nummer steht auf deiner Karte.")
                    LetterRecipientSection(form: $form)
                    LetterRememberSection(remembers: $remembers)
                    Section {
                        LetterPreviewCard(content: letter)
                            .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.m, bottom: Theme.Spacing.s, trailing: Theme.Spacing.m))
                            .id(LetterAnchor.preview)
                        LetterHintBlock(title: "Das brauchst du zusätzlich", paragraphs: hint)
                            .listRowInsets(EdgeInsets())
                    } header: {
                        Text("Vorschau")
                    }
                    .listRowBackground(Color.clear)
                    LetterInlineActions(content: letter, fileName: fileName, printJobName: letter.documentTitle)
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
                .modifier(LetterBottomBar(content: letter, fileName: fileName, printJobName: letter.documentTitle))
                .onChange(of: form.sender) { _, sender in
                    if remembers { LetterStore.saveSender(sender) }
                }
                .onChange(of: remembers) { _, isOn in
                    LetterStore.remembersSender = isOn
                    if isOn { LetterStore.saveSender(form.sender) }
                }
                .motionAnimation(Motion.smooth, value: mode)
                .task {
                    guard let screenshotAnchor else { return }
                    try? await Task.sleep(for: .milliseconds(350))
                    proxy.scrollTo(screenshotAnchor, anchor: .top)
                }
            }
        } else {
            notice(symbol: "info.circle.fill", title: "Dieses Schreiben ist gerade nicht möglich",
                   message: "Prüf im Ratgeber, ab wann du kündigen kannst.")
        }
    }

    private var hint: [String] {
        if mode == .ordinary {
            return ["Laut AGB (Stand \(TicketRights.agbStandShort), Punkt 17.1) braucht eine wirksame Kündigung das Kündigungsformular mit deiner eigenhändigen Unterschrift und die nachweisliche Rückgabe deiner Karte bei einer Servicestelle. Dieses Schreiben legst du dazu – es ersetzt das Formular nicht.",
                    "Frag beim Kundenservice oder in einer Servicestelle nach dem Kündigungsformular."]
        }
        return ["Laut AGB (Stand \(TicketRights.agbStandShort), Punkt 17.2) gibst du Karte, unterschriebenes Kündigungsformular und Nachweis innerhalb von vier Wochen nach Eintritt des Grundes bei einer Servicestelle ab. Das Kündigungsentgelt entfällt. Dieses Schreiben legst du dazu – es ersetzt das Formular nicht.",
                "Frag beim Kundenservice oder in einer Servicestelle nach dem Kündigungsformular."]
    }

    // MARK: Mode

    private var modeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if status.canWriteOrdinary {
                    GlassSegmentedPicker(selection: $mode, options: [Mode.ordinary, .extraordinary]) { option in
                        Text(option == .ordinary ? "Ohne Grund" : "Wichtiger Grund")
                    }
                    .accessibilityLabel("Art der Kündigung")
                } else {
                    lockedOrdinary
                }
            }
            .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.m, bottom: Theme.Spacing.s, trailing: Theme.Spacing.m))
        } footer: {
            if !status.canWriteOrdinary {
                Text("Bis dahin geht es nur mit einem wichtigen Grund (AGB Punkt 17.2).")
            }
        }
    }

    /// Before the 7th month: the ordinary letter is not offered – the date from which it becomes possible instead.
    private var lockedOrdinary: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "lock.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.summitText)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ohne Grund ab dem \(Format.date(status.possibleFrom, .long))")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Du bist im \(status.currentMonth). Gültigkeitsmonat – erst der \(status.possibleFromMonth). erlaubt die Kündigung ohne Angabe von Gründen.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Fee (ordinary)

    private var feeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(status.isKennenlern ? "Kündigungsentgelt (Kennenlern-Aktion)" : "Kündigungsentgelt")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: Theme.Spacing.s)
                    Text(status.fee > 0 ? Format.euroPrecise(status.fee) : "kein Entgelt")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .numericValue(status.fee)
                }
                .accessibilityElement(children: .combine)
                Text(feeExplanation)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Kosten")
        }
    }

    private var feeExplanation: String {
        let payment = context.ticket.isMonthlyPayment
            ? "Bei monatlicher Abbuchung wird es als letzter Monatsbetrag abgebucht, für nicht angefangene Gültigkeitsmonate wird nichts mehr abgebucht."
            : "Bei Einmalzahlung bekommst du die Monatsbeträge der nicht angefangenen Gültigkeitsmonate abzüglich des Entgelts überwiesen."
        if status.isKennenlern { return "Im Rahmen der Kennenlern-Aktion 2026 entfällt es. \(payment)" }
        return "Ein Monatsbetrag, ein Zwölftel des Kaufpreises (AGB Punkt 17.1, Anhang 4). \(payment)"
    }

    // MARK: Reason (extraordinary)

    private var reasonSection: some View {
        Section {
            Picker("Grund", selection: $reason) {
                ForEach(CancellationLetter.Reason.allCases) { option in
                    Label(option.title, systemImage: option.symbol)
                        .tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .haptic(.selection, trigger: reason)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(reason.sinceHint)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                if let reasonDate {
                    HStack(spacing: Theme.Spacing.s) {
                        DatePicker(reason.sinceHint, selection: Binding(get: { reasonDate }, set: { self.reasonDate = $0 }),
                                   in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                        Spacer(minLength: Theme.Spacing.xs)
                    }
                    windowLine(since: reasonDate)
                } else {
                    Button {
                        withMotion(Motion.snappy) { reasonDate = Calendar.vienna.startOfDay(for: Date()) }
                    } label: {
                        Label("Datum wählen", systemImage: "calendar.badge.plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accentText)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .motionAnimation(Motion.smooth, value: reasonDate != nil)
            .haptic(.selection, trigger: reasonDate)
        } header: {
            Text("Wichtiger Grund")
        } footer: {
            Text("Nachweis, der beiliegen muss: \(reason.proof). Er steht im Brief als „liegt bei“ – leg ihn wirklich dazu. Bei Krankheit schreiben wir keine Angaben zur Erkrankung in den Brief.")
        }
    }

    private func windowLine(since: Date) -> some View {
        let window = FilingWindow(since: since)
        let state = window.status()
        let isClosed: Bool = { if case .closed = state { return true } else { return false } }()
        return Label(LetterText.windowStatus(state, lastDay: window.lastDay),
                     systemImage: isClosed ? "exclamationmark.triangle.fill" : "clock.badge.checkmark.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isClosed ? Theme.negativeText : Theme.positiveText)
            .fixedSize(horizontal: false, vertical: true)
            .motionTransition(.rise)
    }

    // MARK: Notices

    private func notice(symbol: String, title: String, message: String) -> some View {
        ScrollView {
            LetterNoticeCard(symbol: symbol, title: title, message: message)
                .padding(Theme.Spacing.m)
        }
    }
}

/// Screenshot presets of the cancellation sheet.
struct CancellationPreset {
    var form: LetterForm
    var mode: CancellationLetterView.Mode?
    var reason: CancellationLetter.Reason?
    var reasonDate: Date?
    var remembers = false
}
