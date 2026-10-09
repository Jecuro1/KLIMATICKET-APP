import SwiftUI
import SwiftData
import KlimaCore

// MARK: - Draft

/// Editable copy of a ticket – applied on save, so „Abbrechen“ never leaves half-edited data behind.
struct TktDraft: Equatable {
    var name: String
    var productID: String
    var variant: TicketVariant
    var family: TicketFamily
    var states: [String]
    var price: Double
    var start: Date
    var holder: String
    var number: String
    var themeRaw: String
    /// Validity of an existing ticket – kept as long as its first day is unchanged.
    var originalStart: Date? = nil
    var originalEnd: Date? = nil
    /// Renews automatically per SEPA unless the holder objects (Ticket-Ratgeber).
    var autoRenews: Bool = false
    /// Jobticket / Zuschuss – the payoff is measured against the own share.
    var employerContribution: Double = 0
    /// ÖBB add-ons (`TicketAddOn` raw values) and what was paid for them.
    var addOns: [String] = []
    var addOnPrice: Double = 0

    static let customProductID = "custom"

    var theme: TicketTheme { TicketTheme.from(themeRaw) }
    var isCustom: Bool { family == .custom || productID == TktDraft.customProductID }

    var end: Date {
        if let originalStart, let originalEnd, Calendar.vienna.isDate(originalStart, inSameDayAs: start) {
            return originalEnd
        }
        return TicketPeriod.standardEnd(for: Calendar.vienna.startOfDay(for: start))
    }
}

extension TktDraft {
    init(ticket: TicketEntity) {
        self.init(name: ticket.name, productID: ticket.productID, variant: ticket.variant, family: ticket.family,
                  states: ticket.states, price: ticket.price, start: ticket.startDate, holder: ticket.holderName,
                  number: ticket.ticketNumber, themeRaw: ticket.themeRaw,
                  originalStart: ticket.startDate, originalEnd: ticket.endDate,
                  autoRenews: ticket.autoRenews, employerContribution: ticket.employerContribution,
                  addOns: ticket.addOns, addOnPrice: ticket.addOnPrice)
    }

    /// New ticket year: continues the current one (day after it ends) with the catalog price, or starts today.
    static func newTicket(basedOn base: TicketEntity?, catalog: TariffCatalog, now: Date = Date()) -> TktDraft {
        let cal = Calendar.vienna
        var start = cal.startOfDay(for: now)
        if let base, base.endDate > now, let next = cal.date(byAdding: .day, value: 1, to: base.endDate) {
            start = cal.startOfDay(for: next)
        }
        let theme = base?.themeRaw ?? TicketTheme.twilight.rawValue
        let holder = base?.holderName ?? ""
        let baseIsCustom = base.map { $0.family == .custom || catalog.product(id: $0.productID) == nil } ?? false
        if !baseIsCustom, let product = catalog.product(id: base?.productID ?? "oe-klassik") ?? catalog.product(id: "oe-klassik") {
            return TktDraft(name: product.name, productID: product.id, variant: product.variant, family: product.family,
                            states: product.states, price: product.price(forStart: start), start: start,
                            holder: holder, number: "", themeRaw: theme,
                            autoRenews: base?.autoRenews ?? false, employerContribution: base?.employerContribution ?? 0)
        }
        return TktDraft(name: base?.name ?? "Mein Jahresticket", productID: customProductID, variant: base?.variant ?? .klassik,
                        family: .custom, states: base?.states ?? [], price: base?.price ?? 0, start: start,
                        holder: holder, number: "", themeRaw: theme,
                        autoRenews: base?.autoRenews ?? false, employerContribution: base?.employerContribution ?? 0)
    }

    func apply(to ticket: TicketEntity) {
        let cal = Calendar.vienna
        let newStart = cal.startOfDay(for: start)
        if !cal.isDate(ticket.startDate, inSameDayAs: newStart) {
            ticket.startDate = newStart
            ticket.endDate = TicketPeriod.standardEnd(for: newStart)
        }
        ticket.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.productID = productID
        ticket.variant = variant
        ticket.family = family
        ticket.states = states
        ticket.price = price
        ticket.holderName = holder.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.ticketNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.themeRaw = themeRaw
        ticket.autoRenews = autoRenews
        ticket.employerContribution = employerContribution
        ticket.addOns = addOns
        ticket.addOnPrice = addOnPrice
    }

    func makeEntity() -> TicketEntity {
        let ticket = TicketEntity(productID: productID, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                  variant: variant, family: family, states: states, price: price,
                                  startDate: Calendar.vienna.startOfDay(for: start),
                                  holderName: holder.trimmingCharacters(in: .whitespacesAndNewlines),
                                  ticketNumber: number.trimmingCharacters(in: .whitespacesAndNewlines))
        ticket.themeRaw = themeRaw
        ticket.autoRenews = autoRenews
        ticket.employerContribution = employerContribution
        ticket.addOns = addOns
        ticket.addOnPrice = addOnPrice
        return ticket
    }

    /// "1400" / "1400,50" – plain, easy to edit.
    static func priceString(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "" }
        if value == value.rounded(), value < 1_000_000_000 { return String(Int(value)) }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// Accepts "1400", "1.400", "1400,50", "1.400,50", "€ 1 400".
    static func parsePrice(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for junk in ["€", " ", "\u{00A0}", "\u{202F}"] {
            s = s.replacingOccurrences(of: junk, with: "")
        }
        guard !s.isEmpty else { return nil }
        if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if let dot = s.lastIndex(of: "."), s.distance(from: dot, to: s.endIndex) == 4 {
            s = s.replacingOccurrences(of: ".", with: "")
        }
        guard let value = Double(s), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

/// Sheet payload: edit an existing ticket or create a new one (`ticket == nil`).
struct TktEditRequest: Identifiable {
    let id = UUID()
    let ticket: TicketEntity?
    let draft: TktDraft
}

// MARK: - Sheet

/// Edit form: live pass preview, card theme, name, product (catalog), start date, price, holder and number.
struct TktEditSheet: View {
    let ticket: TicketEntity?
    let initial: TktDraft
    /// Row id to scroll to on appear (e.g. `AdvEditAnchor.renewal` from the Ratgeber / screenshots).
    var scrollTarget: String? = nil

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TktDraft
    @State private var priceText: String
    @State private var employerText: String
    @State private var addOnPriceText: String

    init(ticket: TicketEntity?, initial: TktDraft, scrollTarget: String? = nil) {
        self.ticket = ticket
        self.initial = initial
        self.scrollTarget = scrollTarget
        _draft = State(initialValue: initial)
        _priceText = State(initialValue: TktDraft.priceString(initial.price))
        _employerText = State(initialValue: AdvisorEuro.editString(initial.employerContribution))
        _addOnPriceText = State(initialValue: AdvisorEuro.editString(initial.addOnPrice))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    previewSection
                    designSection
                    ticketSection
                    validitySection
                    priceSection
                    AdvEditRenewalSection(autoRenews: $draft.autoRenews, employerText: $employerText, family: draft.family,
                                          fullPrice: parsedPrice.map { $0 + (showsAddOns ? (parsedAddOnPrice ?? 0) : 0) },
                                          hapticsEnabled: app.settings.hapticsEnabled)
                    if showsAddOns {
                        AdvEditAddOnsSection(addOns: $draft.addOns, priceText: $addOnPriceText, productID: draft.productID,
                                             variant: draft.variant, hapticsEnabled: app.settings.hapticsEnabled)
                    }
                    holderSection
                }
                .task {
                    guard let scrollTarget else { return }
                    try? await Task.sleep(for: .milliseconds(450))
                    proxy.scrollTo(scrollTarget, anchor: .top)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.sheetBackground)
            .navigationTitle(isNew ? "Neues Ticket" : "Ticket bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onChange(of: draft.start) { oldValue, newValue in
                startChanged(from: oldValue, to: newValue)
            }
        }
        .environment(\.locale, Format.locale)
        .interactiveDismissDisabled(hasChanges)
    }

    // MARK: State

    private var isNew: Bool { ticket == nil }
    private var parsedPrice: Double? { TktDraft.parsePrice(priceText) }
    /// Empty amount fields mean 0; anything else must parse ("800", "1.234,50").
    private var parsedEmployer: Double? { Self.amount(employerText) }
    private var parsedAddOnPrice: Double? { Self.amount(addOnPriceText) }
    /// ÖBB extras exist for the KlimaTicket Ö (also when entered as an own ticket), not for regional tickets.
    private var showsAddOns: Bool { draft.family != .regional }
    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (parsedPrice ?? 0) > 0
            && parsedEmployer != nil && parsedAddOnPrice != nil
    }
    /// An empty price field equals a price of 0 – a pristine custom draft must stay swipe-dismissable.
    private var hasChanges: Bool {
        draft != initial || (parsedPrice ?? 0) != initial.price
            || (parsedEmployer ?? -1) != initial.employerContribution || (parsedAddOnPrice ?? -1) != initial.addOnPrice
    }

    private static func amount(_ text: String) -> Double? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : AdvisorEuro.parse(text)
    }
    private var catalogProduct: TicketProduct? { draft.isCustom ? nil : app.catalog.product(id: draft.productID) }

    private var productLabel: String {
        if draft.isCustom { return "Eigenes Ticket" }
        return catalogProduct?.name ?? draft.name
    }

    /// Official price for the chosen start day when it differs from the entered one.
    private var differingCatalogPrice: Double? {
        guard let product = catalogProduct else { return nil }
        let official = product.price(forStart: draft.start)
        guard let parsed = parsedPrice else { return official }
        return abs(parsed - official) > 0.004 ? official : nil
    }

    private var priceFooter: String {
        guard let parsed = parsedPrice, parsed > 0 else { return "Trag den Preis ein, den du für dein Ticket bezahlt hast." }
        return "Grundlage für deine Bilanz ist der Preis, den du tatsächlich bezahlt hast."
    }

    // MARK: Sections

    private var previewSection: some View {
        Section {
            TicketCard(title: draft.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Mein Ticket" : draft.name,
                       subtitle: TktText.passKicker(name: draft.name, variant: draft.variant, family: draft.family, states: draft.states),
                       holder: draft.holder.trimmingCharacters(in: .whitespaces),
                       validFrom: draft.start, validUntil: draft.end,
                       ticketNumber: draft.number.trimmingCharacters(in: .whitespaces),
                       theme: draft.theme, roll: 0.25, pitch: 0.08)
                .animation(.smooth(duration: 0.35), value: draft.themeRaw)
                .padding(.vertical, Theme.Spacing.s)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private var designSection: some View {
        Section("Kartendesign") {
            TktThemePicker(selection: $draft.themeRaw, hapticsEnabled: app.settings.hapticsEnabled)
                .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: 0, bottom: Theme.Spacing.s, trailing: 0))
        }
    }

    private var ticketSection: some View {
        Section("Ticket") {
            TextField("Name des Tickets", text: $draft.name)
                .textInputAutocapitalization(.words)
            NavigationLink {
                TktProductPicker(selectedID: draft.isCustom ? TktDraft.customProductID : draft.productID, start: draft.start) { product in
                    select(product)
                }
            } label: {
                LabeledContent("Ticketart") {
                    Text(productLabel)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var validitySection: some View {
        Section {
            DatePicker("Gültig ab", selection: $draft.start, displayedComponents: .date)
            LabeledContent("Gültig bis", value: Format.date(draft.end, .long))
        } header: {
            Text("Gültigkeit")
        } footer: {
            Text("Dein Ticket gilt ein Jahr ab dem ersten Geltungstag.")
        }
    }

    private var priceSection: some View {
        Section {
            HStack(spacing: Theme.Spacing.xs) {
                Text("Bezahlt")
                Spacer(minLength: Theme.Spacing.s)
                Text("€")
                    .foregroundStyle(Theme.textSecondary)
                TextField("0", text: $priceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 140)
            }
            if let official = differingCatalogPrice {
                Button {
                    priceText = TktDraft.priceString(official)
                } label: {
                    Label("Offiziellen Preis übernehmen · \(Format.euroPrecise(official))", systemImage: "arrow.uturn.backward")
                        .foregroundStyle(Theme.accentText)
                }
            }
        } header: {
            Text("Preis")
        } footer: {
            Text(priceFooter)
        }
    }

    private var holderSection: some View {
        Section {
            TextField("Vor- und Nachname", text: $draft.holder)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
            TextField("Ticketnummer (optional)", text: $draft.number)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        } header: {
            Text("Inhaber:in & Nummer")
        } footer: {
            Text("Steht nur auf deiner Begleitkarte – sie ersetzt nie das Original-Ticket.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Abbrechen") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(isNew ? "Anlegen" : "Sichern") { save() }
                .fontWeight(.semibold)
                .disabled(!isValid)
        }
    }

    // MARK: Actions

    private func select(_ product: TicketProduct?) {
        if let product {
            draft.productID = product.id
            draft.name = product.name
            draft.variant = product.variant
            draft.family = product.family
            draft.states = product.states
            priceText = TktDraft.priceString(product.price(forStart: draft.start))
        } else {
            draft.productID = TktDraft.customProductID
            draft.family = .custom
            draft.states = []
        }
    }

    /// Keeps the catalog price in sync with the start day (KlimaTicket prices depend on it) unless it was edited.
    private func startChanged(from oldValue: Date, to newValue: Date) {
        guard let product = catalogProduct else { return }
        let oldOfficial = product.price(forStart: oldValue)
        if let parsed = parsedPrice, abs(parsed - oldOfficial) < 0.005 {
            priceText = TktDraft.priceString(product.price(forStart: newValue))
        }
    }

    private func save() {
        guard isValid, let price = parsedPrice else { return }
        var result = draft
        result.price = price
        result.employerContribution = parsedEmployer ?? 0
        if showsAddOns && !result.addOns.isEmpty {
            result.addOnPrice = parsedAddOnPrice ?? 0
        } else {
            result.addOns = []
            result.addOnPrice = 0
        }
        let repo = Repository(context: context, app: app)
        if let ticket {
            result.apply(to: ticket)
            repo.updateTicket(ticket)
            app.showToast("checkmark.circle.fill", "Ticket gespeichert", ticket.name)
        } else {
            let previousSelection = app.settings.selectedTicketID
            let running = Analytics.activeTicket(in: repo.liveTickets(), selectedID: previousSelection)
            let entity = result.makeEntity()
            repo.addTicket(entity)
            let keptRunning = TktSelection.keepRunningTicket(repo: repo, app: app, added: entity,
                                                             previousSelection: previousSelection, running: running)
            app.showToast("ticket.fill", "Ticket angelegt",
                          keptRunning ? "\(entity.name) · ab \(Format.dayMonth(entity.startDate))" : entity.name)
        }
        dismiss()
    }
}

// MARK: - Theme picker

/// Mini passes in every theme; the selection drives the live preview above.
private struct TktThemePicker: View {
    @Binding var selection: String
    var hapticsEnabled: Bool

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(TicketTheme.allCases) { theme in
                    swatch(theme)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.xxs)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selection) { _, _ in hapticsEnabled }
    }

    private func swatch(_ theme: TicketTheme) -> some View {
        let isSelected = TicketTheme.from(selection) == theme
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.modeTile, style: .continuous)
        return Button {
            withAnimation(.snappy(duration: 0.25)) { selection = theme.rawValue }
        } label: {
            VStack(spacing: Theme.Spacing.xs - 2) {
                shape
                    .fill(LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 60, height: 40)
                    .overlay {
                        TopoLines()
                            .stroke(theme.ink.opacity(0.18), lineWidth: 0.5)
                            .clipShape(shape)
                    }
                    .overlay(alignment: .topLeading) {
                        Image(systemName: "mountain.2.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.ink.opacity(0.85))
                            .padding(6)
                    }
                    .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.modeTile + 3, style: .continuous)
                            .strokeBorder(isSelected ? Theme.accent : Color.clear, lineWidth: 2)
                    )
                    .scaleEffect(isSelected ? 1 : 0.94)
                Text(theme.title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Design \(theme.title)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Product picker

private struct TktProductGroup: Identifiable {
    let id: String
    let title: String
    let products: [TicketProduct]
}

/// All catalog tickets grouped (KlimaTicket Ö, then per Bundesland) with the price for the chosen start day.
private struct TktProductPicker: View {
    var selectedID: String
    var start: Date
    var onSelect: (TicketProduct?) -> Void

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            if !oeProducts.isEmpty {
                Section("KlimaTicket Ö") {
                    ForEach(oeProducts) { product in
                        row(product)
                    }
                }
            }
            ForEach(stateGroups) { group in
                Section(group.title) {
                    ForEach(group.products) { product in
                        row(product)
                    }
                }
            }
            Section {
                customRow
            } footer: {
                Text("Für Tickets, die nicht im Katalog sind – Name und Preis trägst du selbst ein.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.sheetBackground)
        .navigationTitle("Ticketart")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Ticket suchen")
    }

    private var oeProducts: [TicketProduct] {
        app.catalog.products.filter { $0.family == .oe && matches($0) }
    }

    private var stateGroups: [TktProductGroup] {
        let products = app.catalog.products
        var groups: [TktProductGroup] = []
        for state in FederalState.allCases where state != .foreign {
            let items = products.filter { $0.family == .regional && $0.states.contains(state.rawValue) && matches($0) }
            if !items.isEmpty {
                groups.append(TktProductGroup(id: state.rawValue, title: state.displayName, products: items))
            }
        }
        return groups
    }

    private func matches(_ product: TicketProduct) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty || product.name.localizedCaseInsensitiveContains(needle)
    }

    private func row(_ product: TicketProduct) -> some View {
        let isSelected = product.id == selectedID
        return Button {
            onSelect(product)
            dismiss()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                    if !product.eligibility.isEmpty {
                        Text(product.eligibility)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: Theme.Spacing.xs)
                Text(Format.euro(product.price(forStart: start)))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var customRow: some View {
        let isSelected = selectedID == TktDraft.customProductID
        return Button {
            onSelect(nil)
            dismiss()
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eigenes Ticket")
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Name, Preis und Startdatum selbst festlegen")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
