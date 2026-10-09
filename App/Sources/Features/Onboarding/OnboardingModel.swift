import Foundation
import SwiftData
import KlimaCore

/// State + logic of the onboarding flow (UI-agnostic).
@Observable
@MainActor
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome, ticket, validity, habits, notifications, done

        var progress: Double { Double(rawValue) / Double(Step.allCases.count - 1) }

        /// Number of the numbered setup steps ("Schritt 2 von 4").
        static let numberedCount = 4

        /// 1…4 for the setup steps, nil for welcome and done.
        var number: Int? { (1...Step.numberedCount).contains(rawValue) ? rawValue : nil }

        /// Eyebrow above the step title ("SCHRITT 2 VON 4").
        var kicker: String? { number.map { "Schritt \($0) von \(Step.numberedCount)" } }

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }
    }

    /// One renewal reminder ("7 Tage vorher · 1. Oktober 2027").
    struct ReminderPreview: Identifiable {
        let offset: Int
        let date: Date
        var id: Int { offset }
    }

    /// Reminder offsets in days before expiry (matches `TicketEntity.remindersRaw` default).
    static let reminderOffsets = [30, 7, 1]

    var step: Step = .welcome

    // Ticket
    var scope: TicketFamily = .oe
    var selectedProductID: String?
    var selectedState: FederalState = .tirol
    var startDate: Date = Calendar.vienna.startOfDay(for: Date())
    var customPrice: Double?
    var customName: String = ""
    var holderName: String = ""
    var ticketNumber: String = ""

    // Habits
    var homeStation: Station?
    var commuteDestination: Station?
    var commuteRoundTrip = true
    var discount: FareDiscount = .none

    // Notifications
    var remindersEnabled = true

    let app: AppState

    init(app: AppState) {
        self.app = app
        selectedProductID = app.catalog.products.first { $0.family == .oe && $0.variant == .klassik }?.id
            ?? app.catalog.products.first { $0.family == .oe }?.id
        if let name = app.auth.profile?.displayName, app.auth.profile?.provider != .local { holderName = name }
        if let home = app.settings.homeStationID.flatMap(app.stations.station(id:)) { homeStation = home }
        discount = app.settings.defaultDiscount
    }

    // MARK: Catalog

    var oeProducts: [TicketProduct] {
        app.catalog.products.filter { $0.family == .oe }
    }

    /// Regional products of the selected federal state (incl. VOR tickets covering several states).
    var regionalProducts: [TicketProduct] {
        app.catalog.products.filter { $0.family == .regional && $0.states.contains(selectedState.rawValue) }
            .sorted { ($0.isLocal == true ? 1 : 0, $0.priceEUR) < ($1.isLocal == true ? 1 : 0, $1.priceEUR) }
    }

    /// State-wide products, ordered Klassik → Jugend → Senior → Spezial → Familie; within a variant,
    /// tickets for this state alone come before multi-state ones (e.g. Jahreskarte Wien before VOR MetropolRegion),
    /// otherwise the curated catalog order is kept (e.g. VMOBIL MAXIMO before LOKAL).
    var regionalMainProducts: [TicketProduct] {
        let state = selectedState.rawValue
        return app.catalog.products.enumerated()
            .filter { $0.element.family == .regional && $0.element.states.contains(state) && $0.element.isLocal != true }
            .sorted { lhs, rhs in
                let l = OnboardingModel.variantRank(lhs.element.variant), r = OnboardingModel.variantRank(rhs.element.variant)
                if l != r { return l < r }
                if lhs.element.states.count != rhs.element.states.count { return lhs.element.states.count < rhs.element.states.count }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }

    /// City / local tickets of the selected state in catalog order (shown as secondary options).
    var regionalLocalProducts: [TicketProduct] {
        let state = selectedState.rawValue
        return app.catalog.products.filter { $0.family == .regional && $0.states.contains(state) && $0.isLocal == true }
    }

    var statesWithRegionalProducts: [FederalState] {
        FederalState.allCases.filter { s in s != .foreign && app.catalog.products.contains { $0.family == .regional && $0.states.contains(s.rawValue) } }
    }

    var selectedProduct: TicketProduct? { selectedProductID.flatMap(app.catalog.product(id:)) }

    /// Catalog price of the selected product for the chosen start date (ignores a manual override).
    var catalogPrice: Double? {
        guard scope != .custom else { return nil }
        return selectedProduct?.price(forStart: startDate)
    }

    /// Price for the chosen start date (prices depend on the validity start), or the custom price.
    var price: Double {
        if let customPrice { return customPrice }
        return catalogPrice ?? 0
    }

    var isPriceFromCatalog: Bool { customPrice == nil && catalogPrice != nil }

    var endDate: Date { TicketPeriod.standardEnd(for: startDate) }

    /// 365 (or 366 when the period contains 29 February).
    var validityDays: Int {
        let cal = Calendar.vienna
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: startDate), to: cal.startOfDay(for: endDate)).day ?? 364
        return max(1, days + 1)
    }

    /// Ticket cost per day of validity ("€ 3,84").
    var costPerDay: Double { price / Double(validityDays) }

    var ticketName: String {
        if scope == .custom {
            let name = customName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "Mein Jahresticket" : name
        }
        return selectedProduct?.name ?? "KlimaTicket"
    }

    /// Second line of the ticket card ("Jahresticket · Ganz Österreich").
    var ticketSubtitle: String {
        switch scope {
        case .oe:
            return "Jahresticket · Ganz Österreich"
        case .regional:
            let names = (selectedProduct?.states ?? []).compactMap { FederalState(rawValue: $0)?.displayName }
            return names.isEmpty ? "Jahresticket · Regional" : "Jahresticket · " + names.joined(separator: ", ")
        case .custom:
            return "Eigenes Jahresticket"
        }
    }

    // MARK: Price validity ("Preis gilt für Tickets ab 1. Jänner 2026")

    private var pricePoints: [TicketProduct.PricePoint] {
        guard scope != .custom, let p = selectedProduct else { return [] }
        return ((p.priceHistory ?? []) + [TicketProduct.PricePoint(validFrom: p.validFrom, priceEUR: p.priceEUR)])
            .sorted { $0.validFrom < $1.validFrom }
    }

    /// First day of the tariff period whose price applies to the chosen start date.
    var priceValidFrom: Date? {
        let day = OnboardingModel.isoDay(startDate)
        guard let point = pricePoints.last(where: { $0.validFrom <= day }) else { return nil }
        return OnboardingModel.date(fromISODay: point.validFrom)
    }

    /// The next known price change after the chosen start date (e.g. when back-dating a ticket).
    var upcomingPricePoint: TicketProduct.PricePoint? {
        let day = OnboardingModel.isoDay(startDate)
        return pricePoints.first { $0.validFrom > day }
    }

    var canContinue: Bool {
        switch step {
        case .ticket: scope == .custom ? !customName.trimmingCharacters(in: .whitespaces).isEmpty || customPrice != nil : selectedProduct != nil
        case .validity: price > 0
        default: true
        }
    }

    // MARK: Commute

    /// Estimated value of the commute favourite (for the habits step preview).
    var commuteEstimate: FareEstimate? {
        guard let a = homeStation, let b = commuteDestination, a.id != b.id else { return nil }
        return app.estimator.estimate(from: a, to: b, mode: .train, discount: discount)
    }

    /// Value of one logged commute (both directions when round trip).
    var commuteValuePerTrip: Double? {
        guard let e = commuteEstimate, e.fareEUR > 0 else { return nil }
        return e.fareEUR * (commuteRoundTrip ? 2 : 1)
    }

    /// "Mit deiner Pendelstrecke rentiert sich das Ticket nach ~30 Hin- und Rückfahrten."
    var commuteBreakEvenTrips: Int? {
        guard let e = commuteEstimate, e.fareEUR > 0, price > 0 else { return nil }
        let perTrip = e.fareEUR * (commuteRoundTrip ? 2 : 1)
        return Int((price / perTrip).rounded(.up))
    }

    var stationsAreIdentical: Bool {
        guard let a = homeStation, let b = commuteDestination else { return false }
        return a.id == b.id
    }

    // MARK: Reminders

    var reminderPreviews: [ReminderPreview] {
        let cal = Calendar.vienna
        let end = cal.startOfDay(for: endDate)
        return OnboardingModel.reminderOffsets.compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: end).map { ReminderPreview(offset: offset, date: $0) }
        }
    }

    // MARK: Selection

    func selectScope(_ newScope: TicketFamily) {
        guard newScope != scope else { return }
        scope = newScope
        customPrice = nil
        switch newScope {
        case .oe:
            if selectedProduct?.family != .oe {
                selectedProductID = oeProducts.first { $0.variant == .klassik }?.id ?? oeProducts.first?.id
            }
        case .regional:
            let states = statesWithRegionalProducts
            if !states.contains(selectedState), let first = states.first { selectedState = first }
            let current = selectedProduct
            if current?.family != .regional || current?.states.contains(selectedState.rawValue) != true {
                selectedProductID = regionalMainProducts.first?.id ?? regionalProducts.first?.id
            }
        case .custom:
            break
        }
    }

    func selectState(_ state: FederalState) {
        selectedState = state
        customPrice = nil
        selectedProductID = regionalMainProducts.first?.id ?? regionalProducts.first?.id
    }

    func selectProduct(_ product: TicketProduct) {
        selectedProductID = product.id
        customPrice = nil
    }

    func swapStations() {
        Swift.swap(&homeStation, &commuteDestination)
    }

    /// Prefills the holder name after a sign-in (Apple/Google/Microsoft deliver a real name).
    func didSignIn() {
        guard holderName.trimmingCharacters(in: .whitespaces).isEmpty,
              let profile = app.auth.profile, profile.provider != .local else { return }
        holderName = profile.displayName
    }

    // MARK: Navigation

    func next() {
        guard let n = Step(rawValue: step.rawValue + 1) else { return }
        step = n
    }

    func back() {
        guard let p = Step(rawValue: step.rawValue - 1) else { return }
        step = p
    }

    // MARK: Finish

    func finish(context: ModelContext) async {
        let repo = Repository(context: context, app: app)
        let product = scope == .custom ? nil : selectedProduct
        let ticket = TicketEntity(
            productID: product?.id ?? "custom",
            name: ticketName,
            variant: product?.variant ?? .klassik,
            family: product?.family ?? .custom,
            states: product?.states ?? [],
            price: price,
            startDate: Calendar.vienna.startOfDay(for: startDate),
            holderName: holderName.trimmingCharacters(in: .whitespaces),
            ticketNumber: ticketNumber.trimmingCharacters(in: .whitespaces)
        )
        app.settings.defaultDiscount = discount
        app.settings.homeStationID = homeStation?.id
        app.settings.renewalRemindersEnabled = remindersEnabled
        if remindersEnabled { await app.notifications.requestAuthorization() }
        repo.addTicket(ticket)

        if let a = homeStation, let b = commuteDestination, let e = commuteEstimate {
            let fav = FavoriteRouteEntity(title: "Pendeln", fromName: a.name, toName: b.name, fromStationID: a.id, toStationID: b.id,
                                          mode: .train, distanceKm: e.distanceKm, fareEUR: e.fareEUR, isRoundTrip: commuteRoundTrip,
                                          states: Array(Set([a.state, b.state])).sorted(), sortIndex: 0)
            repo.addFavorite(fav)
        }
        app.settings.onboardingCompleted = true
    }

    /// "Demo ansehen": fills a realistic sample year so the app can be explored immediately.
    func loadDemo(context: ModelContext) {
        DemoData.seed(into: context)
        Repository(context: context, app: app).refreshWidgets()
        app.settings.onboardingCompleted = true
    }

    // MARK: Helpers

    static func variantRank(_ variant: TicketVariant) -> Int {
        TicketVariant.allCases.firstIndex(of: variant) ?? TicketVariant.allCases.count
    }

    /// "2026-01-01" for a date in Vienna.
    static func isoDay(_ date: Date) -> String {
        let c = Calendar.vienna.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Midnight (Vienna) of an ISO day ("2026-01-01").
    static func date(fromISODay iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.vienna.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
