import SwiftUI
import SwiftData
import UIKit
import KlimaCore

/// What the editor works on.
enum PerkEditorMode {
    /// New benefit from a catalogue partner (prefilled with its typical saving).
    case new(PerkPartner)
    /// New benefit that is not in the catalogue.
    case custom
    /// Existing benefit.
    case edit(BenefitEntity)
}

/// "Vorteil erfassen" / "Vorteil bearbeiten": partner card (offer, how to redeem, promo code, link), the saved
/// amount as a big editable numeral, title, date and note. Saving and deleting go through `Repository`.
struct PerkEditorView: View {
    let mode: PerkEditorMode
    /// Shows a close button (root of a sheet); a pushed editor uses the back button instead.
    var showsCloseButton: Bool = true
    /// Called after saving or deleting – dismisses the whole sheet.
    var onDone: () -> Void

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var title: String
    @State private var amountText: String
    @State private var date: Date
    @State private var note: String
    @State private var confirmsDelete = false
    @State private var copyTick = 0
    @FocusState private var focus: PerkEditorField?

    init(mode: PerkEditorMode, showsCloseButton: Bool = true, onDone: @escaping () -> Void) {
        self.mode = mode
        self.showsCloseButton = showsCloseButton
        self.onDone = onDone
        switch mode {
        case .new(let partner):
            _title = State(initialValue: partner.name)
            _amountText = State(initialValue: PerkFormat.editable(partner.typicalSavingEUR))
            _date = State(initialValue: Date())
            _note = State(initialValue: "")
        case .custom:
            _title = State(initialValue: "")
            _amountText = State(initialValue: "")
            _date = State(initialValue: Date())
            _note = State(initialValue: "")
        case .edit(let benefit):
            _title = State(initialValue: benefit.title)
            _amountText = State(initialValue: PerkFormat.editable(benefit.savedEUR))
            _date = State(initialValue: benefit.date)
            _note = State(initialValue: benefit.note)
        }
    }

    var body: some View {
        let haptics = app.settings.hapticsEnabled
        ScrollView {
            VStack(spacing: PerkStyle.cardSpacing) {
                partnerCard
                amountCard
                detailsCard
                if isEditing {
                    deleteButton
                        .padding(.top, Theme.Spacing.xs)
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xxs)
            .padding(.bottom, Theme.Spacing.l)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background { PerkSheetBackdrop() }
        .navigationTitle(isEditing ? "Vorteil bearbeiten" : "Vorteil erfassen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .safeAreaBar(edge: .bottom) { saveBar }
        .confirmationDialog("Vorteil löschen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { delete() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Ersparnis wird aus deiner Vorteilswelt-Bilanz entfernt.")
        }
        .perkHaptic(.success, trigger: copyTick, enabled: haptics)
    }

    // MARK: Cards

    private var partnerCard: some View {
        GlassCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    PerkIconTile(partner: partner, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(partner?.name ?? "Eigener Vorteil")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Kicker(text: partnerMeta)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                if let partner {
                    Label {
                        Text(partner.benefit)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(PerkStyle.tint(partner.category))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                    if let hint = partner.hint {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let ticketNote = partner.ticketNote {
                        Label(ticketNote, systemImage: "exclamationmark.circle")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.summitText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    partnerActions(partner)
                } else {
                    Text("Erfasse einen Rabatt, der nicht im Katalog steht – etwa eine Gästekarte oder eine Aktion deines Verkehrsverbunds.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func partnerActions(_ partner: PerkPartner) -> some View {
        let url = URL(string: partner.url)
        if partner.code != nil || url != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xs) {
                    codeButton(partner)
                    linkButton(url)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    codeButton(partner)
                    linkButton(url)
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func codeButton(_ partner: PerkPartner) -> some View {
        if let code = partner.code {
            Button {
                UIPasteboard.general.string = code
                copyTick += 1
                app.showToast("doc.on.doc.fill", "Code kopiert", code)
            } label: {
                Label {
                    Text("Code \(Text(code).fontWeight(.bold))")
                } icon: {
                    Image(systemName: "doc.on.doc")
                }
                .font(.subheadline)
                .lineLimit(1)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Rabattcode \(code) kopieren")
        }
    }

    @ViewBuilder
    private func linkButton(_ url: URL?) -> some View {
        if let url {
            Button {
                openURL(url)
            } label: {
                Label("Zum Angebot", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.glass)
            .accessibilityHint("Öffnet die Seite des Partners im Browser")
        }
    }

    private var amountCard: some View {
        GlassCard(padding: Theme.Spacing.l, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Kicker(text: "Gespart")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("€")
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("0,00", text: $amountText)
                        .font(Theme.Typography.priceNumeral)
                        .foregroundStyle(Theme.textPrimary)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .amount)
                        .accessibilityLabel("Gesparter Betrag in Euro")
                }
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(focus == .amount ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.separator))
                        .frame(height: focus == .amount ? 2 : 1)
                        .offset(y: 4)
                }
                .padding(.bottom, Theme.Spacing.xs)
                amountFooter
            }
        }
    }

    @ViewBuilder
    private var amountFooter: some View {
        if let partner {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text("Richtwert \(Format.euroPrecise(partner.typicalSavingEUR)) – passe ihn an deinen echten Preis an.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if amount != partner.typicalSavingEUR {
                    Button("Übernehmen") {
                        withAnimation(reduceMotion ? nil : .snappy) {
                            amountText = PerkFormat.editable(partner.typicalSavingEUR)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .transition(.opacity)
                }
            }
        } else {
            Text("Wie viel hast du dank deines KlimaTickets weniger bezahlt?")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var detailsCard: some View {
        GlassCard(padding: 0, cornerRadius: Theme.Radius.formGroup) {
            VStack(spacing: 0) {
                fieldRow(symbol: "textformat", tint: Theme.glacier) {
                    TextField("Bezeichnung", text: $title)
                        .font(.body)
                        .focused($focus, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focus = .note }
                        .accessibilityLabel("Bezeichnung")
                }
                divider
                fieldRow(symbol: "calendar", tint: Theme.dawn) {
                    DatePicker("Datum", selection: $date, in: ...max(Date(), date), displayedComponents: .date)
                        .environment(\.locale, Format.locale)
                        .foregroundStyle(Theme.textPrimary)
                }
                divider
                fieldRow(symbol: "note.text", tint: Theme.dusk, alignment: .top) {
                    TextField("Notiz (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.body)
                        .focused($focus, equals: .note)
                        .accessibilityLabel("Notiz")
                }
            }
            .padding(.vertical, Theme.Spacing.xxs)
        }
    }

    private func fieldRow<Content: View>(symbol: String, tint: Color, alignment: VerticalAlignment = .center,
                                         @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: alignment, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: .rect(cornerRadius: 9, style: .continuous))
                .environment(\.colorScheme, .light)
                .accessibilityHidden(true)
            content()
                .frame(minHeight: 30)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .padding(.leading, Theme.Spacing.m + 30 + Theme.Spacing.s)
            .accessibilityHidden(true)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmsDelete = true
        } label: {
            Label("Vorteil löschen", systemImage: "trash")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.negativeText)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.glass)
    }

    // MARK: Save bar & toolbar

    private var saveBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if let hint = validationHint {
                Label(hint, systemImage: "info.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Button(action: save) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                    Text(isEditing ? "Änderungen speichern" : "Vorteil speichern")
                    if let amount {
                        Capsule()
                            .fill(Theme.onAccent.opacity(0.4))
                            .frame(width: 1, height: 22)
                        Text(PerkFormat.plusEuro(amount))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: amount))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, Theme.Spacing.m)
            }
            .buttonStyle(.primary)
            .disabled(!canSave)
            .accessibilityLabel(isEditing ? "Änderungen speichern" : "Vorteil speichern")
            .accessibilityValue(amount.map(Format.euroPrecise) ?? "")
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.xxs)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: validationHint)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if showsCloseButton {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .close) {
                    onDone()
                }
                .accessibilityLabel("Schließen")
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Fertig") { focus = nil }
                .fontWeight(.semibold)
        }
    }

    // MARK: Derived state

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var partner: PerkPartner? {
        switch mode {
        case .new(let partner): return partner
        case .custom: return nil
        case .edit(let benefit): return PerkCatalogStore.shared.partner(id: benefit.partnerID)
        }
    }

    private var partnerID: String {
        switch mode {
        case .new(let partner): return partner.id
        case .custom: return PerkCatalog.customID
        case .edit(let benefit): return benefit.partnerID
        }
    }

    private var partnerMeta: String {
        guard let partner else { return "Nicht im Katalog" }
        return "\(partner.category.displayName) · \(partner.regionName)"
    }

    private var amount: Double? { PerkFormat.parseEuro(amountText) }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool { amount != nil && !trimmedTitle.isEmpty }

    private var validationHint: String? {
        if trimmedTitle.isEmpty { return "Gib dem Vorteil eine Bezeichnung." }
        if amount == nil { return amountText.isEmpty ? "Trag ein, wie viel du gespart hast." : "Bitte einen Betrag wie 7,50 eingeben." }
        return nil
    }

    // MARK: Actions

    private func save() {
        focus = nil
        guard let amount, canSave else { return }
        let repository = Repository(context: context, app: app)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .edit(let benefit):
            benefit.title = trimmedTitle
            benefit.savedEUR = amount
            benefit.date = date
            benefit.note = cleanNote
            repository.updateBenefit(benefit)
            app.showToast("checkmark.circle.fill", "Änderungen gespeichert", "\(trimmedTitle) · \(PerkFormat.plusEuro(amount))")
        case .new, .custom:
            let benefit = BenefitEntity(date: date, partnerID: partnerID, title: trimmedTitle, savedEUR: amount, note: cleanNote)
            repository.addBenefit(benefit)
            app.showToast("gift.fill", "Vorteil gespeichert", "\(PerkFormat.plusEuro(amount)) Zusatz-Ersparnis")
        }
        onDone()
    }

    private func delete() {
        guard case .edit(let benefit) = mode else { return }
        Repository(context: context, app: app).deleteBenefit(benefit)
        app.showToast("trash.fill", "Vorteil gelöscht", benefit.title)
        onDone()
    }
}

enum PerkEditorField: Hashable {
    case amount, title, note
}
