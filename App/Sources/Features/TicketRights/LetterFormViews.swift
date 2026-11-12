import SwiftUI
import UIKit
import KlimaCore

// Ticket-Schreiben: the building blocks of the two letter sheets – hero with progress, input rows, the A4 preview with its
// „Bereit“ stamp, the hint block and the bottom bar with „Als PDF teilen“ and „Drucken“.

// MARK: - Hero

/// Medallion, title and the progress of the form: it fills as the required fields get filled in and turns into „Bereit zum
/// Unterschreiben“ when nothing is missing.
struct LetterHero: View {
    var kicker: String
    var title: String
    var subtitle: String
    var symbol: String
    var done: Int
    var total: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isComplete: Bool { done >= total }
    private var progress: Double { total > 0 ? Double(done) / Double(total) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // At accessibility sizes the medallion sits above the words instead of squeezing them.
            let heading = VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Kicker(text: kicker)
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    medallion
                    heading
                }
            } else {
                HStack(alignment: .center, spacing: Theme.Spacing.m) {
                    medallion
                    heading
                }
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ProgressRail(progress: progress, height: 8,
                             fill: isComplete ? AnyShapeStyle(Theme.positive) : AnyShapeStyle(Theme.progressGradient))
                HStack(spacing: 6) {
                    Image(systemName: isComplete ? "checkmark.seal.fill" : "square.and.pencil")
                        .symbolReplaceTransition()
                        .foregroundStyle(isComplete ? Theme.positiveText : Theme.textSecondary)
                        .accessibilityHidden(true)
                    Text(isComplete ? "Bereit zum Unterschreiben" : "\(done) von \(total) Angaben")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(isComplete ? Theme.positiveText : Theme.textSecondary)
                        .contentTransition(.opacity)
                }
                .motionAnimation(Motion.smooth, value: isComplete)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fortschritt")
            .accessibilityValue(isComplete ? "Bereit zum Unterschreiben" : "\(done) von \(total) Angaben")
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var medallion: some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: 52, height: 52)
            .background(Theme.ctaGradient, in: .circle)
            .shadow(color: Theme.accent.opacity(0.3), radius: 10, y: 5)
            .symbolBounce(on: isComplete)
            .accessibilityHidden(true)
    }
}

// MARK: - Input rows

/// One labelled text field of the form (the label stays visible above the field – also with a filled field and at the largest
/// text size). VoiceOver reads the label once, from the field itself.
struct LetterInputRow: View {
    var label: String
    @Binding var text: String
    var prompt: String
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .words
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            TextField(label, text: $text, prompt: Text(prompt), axis: axis)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .font(.body)
                .lineLimit(axis == .vertical ? 2...6 : 1...2)
        }
        .padding(.vertical, 2)
    }
}

/// „Deine Angaben“: name and address.
struct LetterSenderSection: View {
    @Binding var form: LetterForm

    var body: some View {
        Section {
            LetterInputRow(label: "Name", text: $form.name, prompt: "Vor- und Nachname", contentType: .name)
            LetterInputRow(label: "Straße und Hausnummer", text: $form.street, prompt: "Straße und Hausnummer",
                           contentType: .fullStreetAddress)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    LetterInputRow(label: "Postleitzahl", text: $form.postcode, prompt: "PLZ", contentType: .postalCode,
                                   keyboard: .numbersAndPunctuation, capitalization: .never)
                        .frame(maxWidth: 110)
                    LetterInputRow(label: "Ort", text: $form.place, prompt: "Ort", contentType: .addressCity)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    LetterInputRow(label: "Postleitzahl", text: $form.postcode, prompt: "PLZ", contentType: .postalCode,
                                   keyboard: .numbersAndPunctuation, capitalization: .never)
                    LetterInputRow(label: "Ort", text: $form.place, prompt: "Ort", contentType: .addressCity)
                }
            }
        } header: {
            Text("Deine Angaben")
        } footer: {
            Text("Das erscheint als Absender im Brief. Es verlässt dein iPhone nicht, solange du den Brief nicht selbst teilst.")
        }
    }
}

/// „Ort und Datum“ of the letter and the ticket number.
struct LetterDateSection: View {
    @Binding var form: LetterForm
    var numberFooter: String

    var body: some View {
        Section {
            LetterInputRow(label: "Ticketnummer", text: $form.ticketNumber, prompt: "Ticket- oder Vertragsnummer",
                           keyboard: .asciiCapable, capitalization: .characters)
            LetterInputRow(label: "Ort des Briefs",
                           text: Binding(get: { form.placeForLetter }, set: { form.letterPlace = $0 }),
                           prompt: "Ort", contentType: .addressCity)
            DatePicker("Datum", selection: $form.letterDate, displayedComponents: .date)
                .datePickerStyle(.compact)
        } header: {
            Text("Ticket, Ort und Datum")
        } footer: {
            Text(numberFooter)
        }
    }
}

/// „An“: the Kundenservice address from the AGB, editable.
struct LetterRecipientSection: View {
    @Binding var form: LetterForm

    var body: some View {
        Section {
            LetterInputRow(label: "Empfängeradresse", text: $form.recipientText, prompt: LetterRecipient.placeholder,
                           capitalization: .words, axis: .vertical)
            if !form.recipient.isKundenservice {
                Button {
                    withMotion(Motion.snappy) { form.recipientText = LetterRecipient.kundenservice.text }
                } label: {
                    Label("Adresse aus den AGB einsetzen", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .motionTransition(.rise)
            }
        } header: {
            Text("An")
        } footer: {
            Text(LetterText.recipientCaption)
        }
        .motionAnimation(Motion.smooth, value: form.recipient.isKundenservice)
    }
}

/// „Name und Adresse merken“ – default off, Keychain, this device only.
struct LetterRememberSection: View {
    @Binding var remembers: Bool

    var body: some View {
        Section {
            Toggle(isOn: $remembers) {
                Label("Name und Adresse merken", systemImage: "key.fill")
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)
            .haptic(.selection, trigger: remembers)
        } footer: {
            Text(LetterText.rememberCaption)
        }
    }
}

// MARK: - A date only the holder knows

/// A required date the app cannot know: the deadline in the renewal letter, the day a reason for cancelling arose. It starts
/// empty; the button shows a *suggestion* in the picker, and the date only counts once the holder has changed it or taken it
/// over. A guessed day never lands in a letter as if it were a fact.
struct LetterDateChoice<Accessory: View>: View {
    var title: String
    var pickerLabel: String
    /// The confirmed date: nil until the holder chose or confirmed one.
    @Binding var date: Date?
    var suggestion: Date
    /// The latest day the picker allows (the day a reason arose cannot lie in the future).
    var upperBound: Date?
    var suggestionHint: String
    var trailing: (Date) -> Accessory

    @State private var draft: Date?

    /// `startsWithSuggestion` shows the suggestion at once (CI screenshot of that state).
    init(title: String, pickerLabel: String, date: Binding<Date?>, suggestion: Date, upperBound: Date? = nil, suggestionHint: String,
         startsWithSuggestion: Bool = false, @ViewBuilder trailing: @escaping (Date) -> Accessory) {
        _draft = State(initialValue: startsWithSuggestion ? suggestion : nil)
        self.title = title
        self.pickerLabel = pickerLabel
        _date = date
        self.suggestion = suggestion
        self.upperBound = upperBound
        self.suggestionHint = suggestionHint
        self.trailing = trailing
    }

    private var isShowingPicker: Bool { date != nil || draft != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if isShowingPicker {
                HStack(spacing: Theme.Spacing.s) {
                    picker
                    Spacer(minLength: Theme.Spacing.xs)
                    if let date { trailing(date) }
                }
                if date == nil {
                    suggestionRow
                        .motionTransition(.rise)
                }
            } else {
                Button {
                    withMotion(Motion.snappy) { draft = suggestion }
                } label: {
                    Label(title, systemImage: "calendar.badge.plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .motionAnimation(Motion.smooth, value: isShowingPicker)
        .motionAnimation(Motion.smooth, value: date == nil)
    }

    /// One picker for the suggestion and for the confirmed date (so it is not rebuilt, and a popover stays open, when it is taken over).
    @ViewBuilder
    private var picker: some View {
        let selection = Binding<Date>(get: { date ?? draft ?? suggestion }, set: { date = $0; draft = nil })
        if let upperBound {
            DatePicker(pickerLabel, selection: selection, in: ...upperBound, displayedComponents: .date)
                .labelsHidden()
        } else {
            DatePicker(pickerLabel, selection: selection, displayedComponents: .date)
                .labelsHidden()
        }
    }

    private var suggestionRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Label("Nur ein Vorschlag", systemImage: "questionmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.summitText)
            Text(suggestionHint)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                withMotion(Motion.snappy) {
                    date = draft ?? suggestion
                    draft = nil
                }
            } label: {
                Label("Datum übernehmen", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Preview

/// The A4 page with its „Bereit“ stamp and a button that opens it large.
struct LetterPreviewCard: View {
    var content: LetterContent
    @State private var showsLarge = false

    var body: some View {
        GeometryReader { proxy in
            LetterPaper(content: content, width: proxy.size.width)
                .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
                .overlay(alignment: .topTrailing) {
                    if content.isReady {
                        stamp
                            .padding(10)
                            .dynamicTypeSize(...DynamicTypeSize.large)   // a stamp on a page, not text
                            .motionTransition(.pop)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        showsLarge = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(10)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .accessibilityLabel("Brief groß ansehen")
                }
        }
        .aspectRatio(LetterLayout.pageWidth / LetterLayout.pageHeight, contentMode: .fit)
        .motionAnimation(Motion.bouncy, value: content.isReady)
        .sheet(isPresented: $showsLarge) { LetterZoomSheet(content: content) }
    }

    private var stamp: some View {
        Label("Bereit", systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.heavy))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.pine, in: .capsule)
            .rotationEffect(.degrees(-6))
            .shadow(color: Theme.pine.opacity(0.35), radius: 6, y: 3)
    }
}

/// The page at reading size: scrolls in both directions.
private struct LetterZoomSheet: View {
    var content: LetterContent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView([.vertical, .horizontal]) {
                LetterPaper(content: content, width: LetterLayout.pageWidth * (dynamicTypeSize.isAccessibilitySize ? 2.2 : 1.15))   // larger for large text sizes
                    .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
                    .padding(Theme.Spacing.m)
            }
            .background(Theme.sheetBackground)
            .navigationTitle("Brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Hint block

/// The honest rules under the preview: what the AGB say and what they do not.
struct LetterHintBlock: View {
    var title: String
    var paragraphs: [String]
    var symbol: String = "doc.text.magnifyingglass"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(Theme.accentText)
            }
            .accessibilityAddTraits(.isHeader)
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                Text(paragraph)
                    .font(index == 0 ? .subheadline : .footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.10), in: .rect(cornerRadius: Theme.Radius.formGroup, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// A calm line for an answer instead of a form (no letter needed, other conditions apply).
struct LetterNoticeCard: View {
    var symbol: String
    var title: String
    var message: String
    var tone: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(tone)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Bottom bar

/// „Als PDF teilen“ and „Drucken“ – pinned at the bottom (at accessibility sizes inline after the form, where the buttons
/// would take half the screen), enabled when nothing is missing. While something is missing it says what.
struct LetterActionBar: View {
    var content: LetterContent
    var fileName: String
    var printJobName: String
    /// Inside the form instead of pinned: no backdrop.
    var isInline = false

    @Environment(AppState.self) private var app
    @State private var printTrigger = 0

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if !content.isReady, let issue = content.issues.first {
                Text(summary(issue))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.summitText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .motionTransition(.rise)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.s) {
                    shareButton
                    printButton.frame(width: 148)
                }
                VStack(spacing: Theme.Spacing.s) {
                    shareButton
                    printButton
                }
            }
        }
        .padding(.horizontal, isInline ? 0 : Theme.Spacing.m)
        .padding(.top, isInline ? 0 : Theme.Spacing.s)
        .padding(.bottom, isInline ? 0 : Theme.Spacing.xs)
        .background(alignment: .top) {
            if !isInline {
                // A short fade above the bar, solid below it: nothing of the form shows between the buttons.
                LinearGradient(colors: [Theme.sheetBackground.opacity(0), Theme.sheetBackground], startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
                    .offset(y: -24)
            }
        }
        .background {
            if !isInline { Theme.sheetBackground.ignoresSafeArea(edges: .bottom) }
        }
        .motionAnimation(Motion.smooth, value: content.isReady)
        .haptic(.success, trigger: content.isReady, when: { old, new in !old && new })
    }

    /// „Es fehlt noch: Name, Ort.“ – the place of the letter follows the holder's place, so it is not named twice.
    private func summary(_ issue: LetterIssue) -> String {
        let missing = content.missingFields
        let shown = missing.contains(.place) ? missing.filter { $0 != .letterPlace } : missing
        if shown.count > 1 {
            return "Es fehlt noch: " + shown.map(\.title).joined(separator: ", ") + "."
        }
        if let only = shown.first { return LetterIssue.missing(only).message }
        return issue.message
    }

    private var shareButton: some View {
        ShareLink(item: LetterPDFDocument(content: content, fileName: fileName),
                  preview: SharePreview(fileName, image: Image(systemName: "doc.richtext.fill"))) {
            Label("Als PDF teilen", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.primary)
        .disabled(!content.isReady)
    }

    private var printButton: some View {
        Button {
            printTrigger += 1
            if !LetterPrinter.printLetter(content, jobName: printJobName) {
                app.showToast("printer.fill", "Drucken geht gerade nicht", "Teile das PDF und drucke es aus der Dateien-App.")
            }
        } label: {
            Label("Drucken", systemImage: "printer.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.glass)
        .disabled(!content.isReady || !LetterPrinter.isAvailable)
        .haptic(.tap, trigger: printTrigger)
    }
}

/// The bar at the bottom of a letter sheet – or, at accessibility sizes, nothing here: the actions are a section of the form.
struct LetterBottomBar: ViewModifier {
    var content: LetterContent
    var fileName: String
    var printJobName: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content view: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            view
        } else {
            view.safeAreaInset(edge: .bottom, spacing: 0) {
                LetterActionBar(content: content, fileName: fileName, printJobName: printJobName)
            }
        }
    }
}

/// Inline actions for accessibility sizes (a form section; empty otherwise).
struct LetterInlineActions: View {
    var content: LetterContent
    var fileName: String
    var printJobName: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Section {
                LetterActionBar(content: content, fileName: fileName, printJobName: printJobName, isInline: true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
    }
}
