import SwiftUI
import KlimaCore

/// Step 2 – which ticket: KlimaTicket Ö variants, a federal state's regional tickets, or a custom ticket.
struct OnbTicketStep: View {
    @Bindable var model: OnboardingModel
    @Environment(AppState.self) private var app

    var body: some View {
        OnbPage(kicker: OnboardingModel.Step.ticket.kicker,
                title: "Welches Ticket hast du?",
                subtitle: "Wir rechnen mit dem offiziellen Preis – anpassen kannst du ihn jederzeit.") {
            OnbScopePicker(selection: model.scope) { scope in
                withAnimation(.snappy(duration: 0.3)) { model.selectScope(scope) }
            }
            scopeContent
        }
        .sensoryFeedback(.selection, trigger: model.selectedProductID) { _, _ in app.settings.hapticsEnabled }
        .sensoryFeedback(.selection, trigger: model.scope) { _, _ in app.settings.hapticsEnabled }
    }

    @ViewBuilder
    private var scopeContent: some View {
        switch model.scope {
        case .oe:
            oeSection
                .transition(.opacity)
        case .regional:
            OnbRegionalSection(model: model)
                .transition(.opacity)
        case .custom:
            OnbCustomTicketForm(model: model)
                .transition(.opacity)
        }
    }

    private var oeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            OnbSectionLabel(title: "KlimaTicket Ö")
            ForEach(model.oeProducts) { product in
                OnbProductCard(product: product,
                               price: product.price(forStart: model.startDate),
                               isSelected: model.selectedProductID == product.id,
                               isCompact: false) {
                    withAnimation(.snappy(duration: 0.25)) { model.selectProduct(product) }
                }
            }
            Label("Ganz Österreich: Bahn, Bus, Bim und U-Bahn in der 2. Klasse.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.xxs)
                .padding(.top, Theme.Spacing.xxs)
        }
    }
}

// MARK: - Scope picker

private struct OnbScopeOption: Identifiable {
    let scope: TicketFamily
    let title: String
    var id: String { scope.rawValue }
}

/// Glass segmented control "Österreich · Bundesland · Eigenes" with a sliding selection capsule.
private struct OnbScopePicker: View {
    var selection: TicketFamily
    var onSelect: (TicketFamily) -> Void

    @Namespace private var namespace
    @Environment(\.colorScheme) private var colorScheme

    private let options: [OnbScopeOption] = [
        OnbScopeOption(scope: .oe, title: "Österreich"),
        OnbScopeOption(scope: .regional, title: "Bundesland"),
        OnbScopeOption(scope: .custom, title: "Eigenes"),
    ]

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(Theme.Spacing.xxs)
        .glassEffect(.regular, in: .capsule)
    }

    private func segment(_ option: OnbScopeOption) -> some View {
        let isSelected = option.scope == selection
        return Button {
            onSelect(option.scope)
        } label: {
            Text(option.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, Theme.Spacing.xxs)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(colorScheme == .dark ? Theme.surfaceSecondary : Theme.surface)
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 6, y: 2)
                            .matchedGeometryEffect(id: "scope-selection", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Product card

/// Rich selectable ticket card: variant icon · name · eligibility · price · selection mark.
/// Compact variant (local/city tickets) is visually secondary.
private struct OnbProductCard: View {
    var product: TicketProduct
    var price: Double
    var isSelected: Bool
    var isCompact: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                if !isCompact {
                    OnbIconTile(symbol: OnbProductCopy.symbol(for: product.variant),
                                tint: OnbProductCopy.tint(for: product.variant), size: 40)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(OnbProductCopy.title(for: product))
                        .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(OnbProductCopy.detail(for: product))
                        .font(isCompact ? .caption : .subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: Theme.Spacing.xs)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Format.euro(price))
                        .font(isCompact ? .subheadline.weight(.semibold).monospacedDigit() : Theme.Typography.numberSmall)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                    if !isCompact {
                        Text("pro Jahr")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(isCompact ? .body : .title3)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, isCompact ? 11 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frostedCard(cornerRadius: Theme.Radius.tile, tint: isSelected ? Theme.accent : nil)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        }
        .buttonStyle(OnbPressableStyle())
        .accessibilityLabel(product.name)
        .accessibilityValue("\(Format.euro(price)) pro Jahr, \(OnbProductCopy.detail(for: product))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Regional

private struct OnbRegionalSection: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        let main = model.regionalMainProducts
        let local = model.regionalLocalProducts
        VStack(alignment: .leading, spacing: 10) {
            OnbSectionLabel(title: "Bundesland")
            statePicker
            if main.isEmpty && local.isEmpty {
                Text("Für dieses Bundesland sind noch keine Tickets hinterlegt. Wähle „Eigenes“, um dein Ticket selbst anzulegen.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Spacing.xxs)
            }
            ForEach(main) { product in
                card(product, compact: false)
            }
            if !local.isEmpty {
                OnbSectionLabel(title: "Stadt- & Lokaltickets")
                    .padding(.top, Theme.Spacing.s)
                ForEach(local) { product in
                    card(product, compact: true)
                }
            }
        }
    }

    private func card(_ product: TicketProduct, compact: Bool) -> some View {
        OnbProductCard(product: product,
                       price: product.price(forStart: model.startDate),
                       isSelected: model.selectedProductID == product.id,
                       isCompact: compact) {
            withAnimation(.snappy(duration: 0.25)) { model.selectProduct(product) }
        }
    }

    private var statePicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(model.statesWithRegionalProducts) { state in
                        Chip(title: state.displayName, isSelected: state == model.selectedState) {
                            withAnimation(.snappy(duration: 0.3)) { model.selectState(state) }
                        }
                        .id(state)
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Theme.Spacing.cardGutter, for: .scrollContent)
            .padding(.horizontal, -Theme.Spacing.cardGutter)
            .onAppear {
                proxy.scrollTo(model.selectedState, anchor: .center)
            }
        }
    }
}

// MARK: - Custom ticket

private struct OnbCustomTicketForm: View {
    @Bindable var model: OnboardingModel
    @State private var priceText = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable { case name, price }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OnbSectionLabel(title: "Eigenes Ticket")
            OnbFormGroup {
                OnbFieldRow(label: "Bezeichnung", symbol: "ticket.fill", tint: Theme.glacier) {
                    TextField("z. B. Jahreskarte Graz", text: $model.customName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focus, equals: .name)
                        .onSubmit { focus = .price }
                }
                OnbDivider()
                OnbFieldRow(label: "Preis pro Jahr", symbol: "eurosign", tint: Theme.dawn) {
                    TextField("€ 0,00", text: $priceText)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .price)
                }
            }
            Text("Für Jahreskarten, Jobtickets oder Abos, die nicht in der Liste stehen. Gültigkeit und Preis prüfst du im nächsten Schritt.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.xxs)
        }
        .onAppear {
            priceText = OnbPriceParser.text(for: model.customPrice)
        }
        .onChange(of: priceText) { _, newValue in
            model.customPrice = OnbPriceParser.parse(newValue)
        }
    }
}
