import SwiftUI
import KlimaCore

/// Step 3 – validity start (graphical calendar), computed end date, the catalog price for that start,
/// an optional manual price, holder name and ticket number.
struct OnbValidityStep: View {
    @Bindable var model: OnboardingModel
    @Environment(AppState.self) private var app
    @State private var isEditingPrice = false
    @State private var priceText = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable { case price, holder, number }

    var body: some View {
        OnbPage(kicker: OnboardingModel.Step.validity.kicker,
                title: "Gültigkeit & Preis",
                subtitle: "Wähle deinen ersten Geltungstag – wir berechnen das Ablaufdatum und den Preis, der für diesen Start gilt.") {
            calendarCard
            periodCard
            priceCard
            holderSection
        }
        .onAppear {
            isEditingPrice = model.customPrice != nil
            priceText = OnbPriceParser.text(for: model.customPrice)
        }
        .onChange(of: priceText) { _, newValue in
            guard isEditingPrice || model.scope == .custom else { return }
            withAnimation(.snappy(duration: 0.3)) { model.customPrice = OnbPriceParser.parse(newValue) }
        }
        .sensoryFeedback(.selection, trigger: model.startDate) { _, _ in app.settings.hapticsEnabled }
    }

    // MARK: Calendar

    private static var selectableRange: ClosedRange<Date> {
        let cal = Calendar.vienna
        let today = cal.startOfDay(for: Date())
        let lower = cal.date(byAdding: .year, value: -2, to: today) ?? today
        let upper = cal.date(byAdding: .year, value: 1, to: today) ?? today
        return lower...upper
    }

    /// Keeps the start at midnight (Vienna) so trips on the first day always count.
    private var startBinding: Binding<Date> {
        Binding(
            get: { model.startDate },
            set: { newValue in
                let day = Calendar.vienna.startOfDay(for: newValue)
                withAnimation(.snappy(duration: 0.35)) { model.startDate = day }
            }
        )
    }

    private var calendarCard: some View {
        GlassCard(padding: Theme.Spacing.s) {
            DatePicker("Erster Geltungstag", selection: startBinding, in: Self.selectableRange, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Theme.accent)
                .environment(\.locale, Format.locale)
                .environment(\.calendar, Calendar.vienna)
                .environment(\.timeZone, Calendar.vienna.timeZone)
        }
    }

    private var periodCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Theme.Spacing.s) {
                        periodColumn("Gültig ab", model.startDate, alignment: .leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 20)
                        Spacer(minLength: 0)
                        periodColumn("Gültig bis", model.endDate, alignment: .trailing)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        periodColumn("Gültig ab", model.startDate, alignment: .leading)
                        periodColumn("Gültig bis", model.endDate, alignment: .leading)
                    }
                }
                Label("\(model.validityDays) Tage gültig", systemImage: "calendar")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.12), in: .capsule)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func periodColumn(_ label: String, _ date: Date, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: Theme.Spacing.xxs) {
            Kicker(text: label)
            Text(Format.date(date, .long))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                .contentTransition(.numericText())
        }
    }

    // MARK: Price

    private var priceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .center, spacing: Theme.Spacing.xs) {
                    Kicker(text: "Ticketpreis")
                    Spacer(minLength: Theme.Spacing.xs)
                    priceBadge
                }
                Text(model.price > 0 ? Format.euro(model.price) : "€ –")
                    .font(Theme.Typography.priceNumeral)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: model.price))
                    .accessibilityLabel("Ticketpreis")
                    .accessibilityValue(model.price > 0 ? Format.euro(model.price) : "noch offen")
                priceExplanation
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                OnbDivider(inset: 0)
                    .padding(.vertical, Theme.Spacing.xxs)
                if model.scope == .custom {
                    customPriceRow
                } else {
                    overrideRow
                }
            }
        }
    }

    @ViewBuilder
    private var priceBadge: some View {
        if model.isPriceFromCatalog {
            OnbBadge(title: "Offizieller Preis", symbol: "checkmark.seal.fill", tint: Theme.positive, textColor: Theme.positiveText)
        } else if model.customPrice != nil {
            OnbBadge(title: "Eigener Preis", symbol: "pencil", tint: Theme.accent, textColor: Theme.accentText)
        }
    }

    @ViewBuilder
    private var priceExplanation: some View {
        if model.isPriceFromCatalog {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                if let validFrom = model.priceValidFrom {
                    Text("Preis gilt für Tickets ab \(Format.date(validFrom, .long)).")
                } else {
                    Text("Offizieller Preis laut Tarif.")
                }
                if let upcoming = model.upcomingPricePoint, let date = OnboardingModel.date(fromISODay: upcoming.validFrom) {
                    Label("Für Tickets ab \(Format.date(date, .long)): \(Format.euro(upcoming.priceEUR))", systemImage: "arrow.up.right")
                        .font(.footnote)
                }
            }
        } else if let customPrice = model.customPrice, let catalog = model.catalogPrice, customPrice != catalog {
            Text("Statt \(Format.euro(catalog)) laut Tarif – die Bilanz rechnet mit deinem Preis.")
        } else if model.customPrice != nil {
            Text("Die Bilanz rechnet mit deinem Preis.")
        } else {
            Text("Gib den Preis ein, den du für dein Ticket bezahlt hast.")
        }
    }

    private var customPriceRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            OnbIconTile(symbol: "eurosign", tint: Theme.dawn, size: 32)
            TextField("Preis, z. B. 467", text: $priceText)
                .keyboardType(.decimalPad)
                .focused($focus, equals: .price)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    @ViewBuilder
    private var overrideRow: some View {
        if isEditingPrice {
            HStack(spacing: Theme.Spacing.s) {
                OnbIconTile(symbol: "pencil", tint: Theme.dusk, size: 32)
                TextField("Bezahlter Preis, z. B. \(Format.number(model.catalogPrice ?? 0))", text: $priceText)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .price)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Button("Zurücksetzen", action: resetPrice)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
            }
            .transition(.opacity)
        } else {
            Button(action: startEditingPrice) {
                HStack(spacing: Theme.Spacing.s) {
                    OnbIconTile(symbol: "pencil", tint: Theme.dusk, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Anderen Preis bezahlt?")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("z. B. mit Förderung, Jobticket oder Aktion")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: Theme.Spacing.xs)
                    Text("Anpassen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }

    private func startEditingPrice() {
        withAnimation(.snappy(duration: 0.3)) { isEditingPrice = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            focus = .price
        }
    }

    private func resetPrice() {
        focus = nil
        withAnimation(.snappy(duration: 0.3)) {
            isEditingPrice = false
            priceText = ""
            model.customPrice = nil
        }
    }

    // MARK: Holder

    private var holderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            OnbSectionLabel(title: "Für deine Ticket-Karte")
            OnbFormGroup {
                OnbFieldRow(label: "Inhaber:in", symbol: "person.fill", tint: Theme.glacier) {
                    TextField("Vor- und Nachname", text: $model.holderName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focus, equals: .holder)
                        .onSubmit { focus = .number }
                }
                OnbDivider()
                OnbFieldRow(label: "Ticketnummer (optional)", symbol: "number", tint: Theme.dusk) {
                    TextField("z. B. KT 4821 3907", text: $model.ticketNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focus, equals: .number)
                        .onSubmit { focus = nil }
                }
            }
            Text("Erscheint nur auf deiner Begleitkarte in der App – bei Kontrollen zählt dein Original-Ticket.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.xxs)
        }
    }
}
