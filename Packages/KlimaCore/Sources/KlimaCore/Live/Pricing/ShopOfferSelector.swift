import Foundation

/// The regular single fare picked from a shop offer list (SPEC §B3.6).
public struct ShopFare: Sendable, Hashable {
    /// EUR, rounded to cents.
    public var amountEUR: Double
    /// Product names joined with „ + “ ("Standard-Ticket", "VVT Einzelticket").
    public var productName: String
    /// `products[0].owners[0].nameShort`: „ÖBB“, „VVT“, „VOR“, „OÖVV“ …
    public var owner: String
    /// Applied reductions (`relevantReductions[].de`, e.g. „1× Vorteilscard Classic“), de-duplicated in order.
    public var reductions: [String]

    public init(amountEUR: Double, productName: String, owner: String, reductions: [String] = []) {
        self.amountEUR = amountEUR
        self.productName = productName
        self.owner = owner
        self.reductions = reductions
    }

    /// True for a ticket of an Austrian Verkehrsverbund sold by the ÖBB shop (owner ≠ „ÖBB“).
    public var isVerbund: Bool { owner != ShopOfferSelector.oebbOwner }
}

/// Pure selection of the Standard fare (SPEC §B2): the offer in travel class "2" (or "1") with `flexibility.de == "FLEX"`
/// whose products are all `trafficType == "ONEWAY"`, lowest `price`. Sparschiene (NON-FLEX / SEMI-FLEX), day tickets
/// (FLEX but MULTIPLE) and business class ("B") never qualify.
public enum ShopOfferSelector {
    static let oebbOwner = "ÖBB"

    /// Standard regular single fare for `travelClass` (2nd → "2", 1st → "1"); nil if none. Pure. Golden-tested.
    public static func standardFare(_ offers: ShopOffers, travelClass: TravelClass) -> ShopFare? {
        guard offers.offerError != true else { return nil }
        let wanted = travelClass == .first ? "1" : "2"
        var best: (price: Double, offer: ShopOffers.Offer)?
        for section in offers.offerSections ?? [] {
            for tc in section.travelClasses ?? [] where tc.travelClass?.trimmingCharacters(in: .whitespaces) == wanted {
                for offer in tc.offers ?? [] {
                    guard isStandard(offer), let price = offer.price, price.isFinite, price > 0 else { continue }
                    if best == nil || price < best!.price { best = (price, offer) }
                }
            }
        }
        guard let (price, offer) = best else { return nil }
        let products = offer.products ?? []
        let names = products.compactMap { $0.name?.text?.trimmingCharacters(in: .whitespaces).nilIfEmpty }
        var reductions: [String] = []
        for r in products.flatMap({ $0.relevantReductions ?? [] }).compactMap({ $0.text?.trimmingCharacters(in: .whitespaces).nilIfEmpty })
            where !reductions.contains(r) {
            reductions.append(r)
        }
        let owner = products.first?.owners?.first?.nameShort?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? oebbOwner
        return ShopFare(amountEUR: (price * 100).rounded() / 100,
                        productName: names.isEmpty ? "Standard-Ticket" : names.joined(separator: " + "),
                        owner: owner, reductions: reductions)
    }

    /// FLEX and every product ONEWAY (at least one product).
    static func isStandard(_ offer: ShopOffers.Offer) -> Bool {
        guard offer.flexibility?.text?.trimmingCharacters(in: .whitespaces).uppercased() == "FLEX" else { return false }
        let products = offer.products ?? []
        return !products.isEmpty && products.allSatisfy { $0.trafficType?.uppercased() == "ONEWAY" }
    }
}
