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
    }

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
        if let name = app.auth.profile?.displayName, app.auth.profile?.provider != .local { holderName = name }
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

    var statesWithRegionalProducts: [FederalState] {
        FederalState.allCases.filter { s in s != .foreign && app.catalog.products.contains { $0.family == .regional && $0.states.contains(s.rawValue) } }
    }

    var selectedProduct: TicketProduct? { selectedProductID.flatMap(app.catalog.product(id:)) }

    /// Price for the chosen start date (prices depend on the validity start), or the custom price.
    var price: Double {
        if let customPrice { return customPrice }
        return selectedProduct?.price(forStart: startDate) ?? 0
    }

    var isPriceFromCatalog: Bool { customPrice == nil && selectedProduct != nil }

    var endDate: Date { TicketPeriod.standardEnd(for: startDate) }

    var ticketName: String {
        if scope == .custom { return customName.isEmpty ? "Mein Jahresticket" : customName }
        return selectedProduct?.name ?? "KlimaTicket"
    }

    var canContinue: Bool {
        switch step {
        case .ticket: scope == .custom ? !customName.trimmingCharacters(in: .whitespaces).isEmpty || customPrice != nil : selectedProduct != nil
        case .validity: price > 0
        default: true
        }
    }

    /// Estimated value of the commute favourite (for the habits step preview).
    var commuteEstimate: FareEstimate? {
        guard let a = homeStation, let b = commuteDestination, a.id != b.id else { return nil }
        return app.estimator.estimate(from: a, to: b, mode: .train, discount: discount)
    }

    /// "Mit deiner Pendelstrecke rentiert sich das Ticket nach ~30 Hin- und Rückfahrten."
    var commuteBreakEvenTrips: Int? {
        guard let e = commuteEstimate, e.fareEUR > 0, price > 0 else { return nil }
        let perTrip = e.fareEUR * (commuteRoundTrip ? 2 : 1)
        return Int((price / perTrip).rounded(.up))
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
            startDate: startDate,
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
}
