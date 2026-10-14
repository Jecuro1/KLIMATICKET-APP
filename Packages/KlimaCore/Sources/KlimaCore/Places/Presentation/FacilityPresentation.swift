import Foundation

/// One row of a stop's „Ausstattung“ (pure, no UI): German label, SF Symbol name, what OpenStreetMap says, and the
/// accessibility label. Status texts never claim absence from a missing entry: no statement reads as „nicht erfasst“.
public struct FacilityRow: Equatable, Sendable, Identifiable {
    public var id: FacilityKind { kind }
    public let kind: FacilityKind
    public let title: String
    public let symbol: String
    public let status: FacilityStatus
    /// „laut OpenStreetMap vorhanden“, „nicht erfasst“, …
    public let statusText: String
    /// „2 Aufzüge“, „überdacht“, „rollstuhlgerecht“ …; nil when there is nothing to add.
    public let detail: String?
    /// „an der Haltestelle erfasst“ or „Objekt in bis zu 40 m“; nil when not recorded.
    public let sourceText: String?
    public let accessibilityLabel: String

    public enum Tone: Sendable { case positive, negative, neutral }

    public var tone: Tone {
        switch status {
        case .present, .limited, .realtime: .positive
        case .absent: .negative
        case .notRecorded: .neutral
        }
    }
}

public enum FacilityPresentation {
    /// Display order of the grid: barrier-free access first, then what people look for at a stop.
    public static let order: [FacilityKind] = [
        .wheelchair, .elevator, .toilets, .bicycleParking, .ticketMachine, .departuresBoard, .shelter, .bench,
        .tactilePaving,
    ]

    /// The route card's meta row shows at most this many facility chips.
    public static let routeChipLimit = 3

    /// Attribution of the facility data (ENRICH_SPEC §1.10.2, ODbL).
    public static let attribution = "© OpenStreetMap-Mitwirkende, ODbL 1.0"

    /// One row per kind in `order`; kinds the data does not contain are „nicht erfasst“.
    public static func rows(_ facilities: [StopFacility]) -> [FacilityRow] {
        let byKind = Dictionary(facilities.map { ($0.kind, $0) }, uniquingKeysWith: { first, _ in first })
        return order.map { row(byKind[$0] ?? StopFacility(kind: $0, status: .notRecorded)) }
    }

    /// Chips for the route card: positive statements only, in `order`, at most `limit`.
    public static func routeChips(_ facilities: [StopFacility], limit: Int = routeChipLimit) -> [FacilityRow] {
        Array(rows(facilities).filter { $0.tone == .positive }.prefix(max(0, limit)))
    }

    public static func row(_ f: StopFacility) -> FacilityRow {
        let title = title(f.kind)
        let statusText = statusText(f)
        let detail = detail(f)
        let source = sourceText(f.source)
        let label = [title + ": " + statusText, detail, source].compactMap { $0 }.joined(separator: ", ")
        return FacilityRow(kind: f.kind, title: title, symbol: symbol(f.kind), status: f.status, statusText: statusText,
                           detail: detail, sourceText: source, accessibilityLabel: label)
    }

    public static func title(_ kind: FacilityKind) -> String {
        switch kind {
        case .elevator: "Aufzug"
        case .toilets: "WC"
        case .bicycleParking: "Fahrradständer"
        case .ticketMachine: "Fahrkartenautomat"
        case .shelter: "Wartehäuschen"
        case .bench: "Sitzbank"
        case .tactilePaving: "Blindenleitsystem"
        case .departuresBoard: "Abfahrtstafel"
        case .wheelchair: "Barrierefrei"
        }
    }

    /// SF Symbol names (iOS 17+ symbols only).
    public static func symbol(_ kind: FacilityKind) -> String {
        switch kind {
        case .elevator: "arrow.up.arrow.down.square"
        case .toilets: "toilet"
        case .bicycleParking: "bicycle"
        case .ticketMachine: "ticket"
        case .shelter: "bus.fill"
        case .bench: "chair.lounge"
        case .tactilePaving: "figure.walk"
        case .departuresBoard: "display"
        case .wheelchair: "figure.roll"
        }
    }

    public static func statusText(_ f: StopFacility) -> String {
        switch (f.kind, f.status) {
        case (.wheelchair, .present): "laut OpenStreetMap barrierefrei"
        case (.wheelchair, .limited): "laut OpenStreetMap teilweise barrierefrei"
        case (.wheelchair, .absent): "laut OpenStreetMap nicht barrierefrei"
        case (.departuresBoard, .realtime): "laut OpenStreetMap mit Echtzeitanzeige"
        case (_, .present), (_, .realtime): "laut OpenStreetMap vorhanden"
        case (_, .limited): "laut OpenStreetMap eingeschränkt"
        case (_, .absent): "laut OpenStreetMap nicht vorhanden"
        case (_, .notRecorded): "nicht erfasst"
        }
    }

    /// Count, covered, toilet access and fee, where OSM says them; nil otherwise.
    public static func detail(_ f: StopFacility) -> String? {
        guard f.isPresent else { return nil }
        var parts: [String] = []
        switch f.kind {
        case .elevator:
            parts.append(counted(f, one: "1 Aufzug", many: "Aufzüge", several: "mehrere Aufzüge"))
        case .ticketMachine:
            parts.append(counted(f, one: "1 Automat", many: "Automaten", several: "mehrere Automaten"))
        case .toilets:
            parts.append(counted(f, one: "1 WC", many: "WCs", several: "mehrere WCs"))
            switch f.toiletWheelchair {
            case .present?: parts.append("rollstuhlgerecht")
            case .limited?: parts.append("teilweise rollstuhlgerecht")
            case .absent?: parts.append("nicht rollstuhlgerecht")
            default: break
            }
            if let fee = f.toiletFee { parts.append(fee ? "kostenpflichtig" : "kostenlos") }
        case .bicycleParking:
            if f.countIsAtLeast {
                parts.append("mindestens \(f.count) Stellplätze")
            } else if f.count > 0 {
                parts.append(f.count == 1 ? "1 Stellplatz" : "\(f.count) Stellplätze")
            }
            if let covered = f.covered { parts.append(covered ? "überdacht" : "nicht überdacht") }
        case .shelter, .bench, .tactilePaving, .departuresBoard, .wheelchair:
            break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func counted(_ f: StopFacility, one: String, many: String, several: String) -> String {
        if f.countIsAtLeast { return several }
        return f.count == 1 ? one : "\(f.count) \(many)"
    }

    public static func sourceText(_ source: FacilitySource?) -> String? {
        switch source {
        case .stopTag?: "an der Haltestelle erfasst"
        case .nearbyObject?: "Objekt in bis zu 40 m"
        case nil: nil
        }
    }

    /// The source line of the grid: attribution and the data date (META build date), German.
    public static func sourceLine(buildDate: Date?) -> String {
        guard let buildDate else { return attribution }
        return "\(attribution) · Stand \(dateText(buildDate))"
    }

    static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_AT")
        f.timeZone = TimeZone(identifier: "Europe/Vienna")
        f.dateFormat = "d. MMMM yyyy"
        return f.string(from: date)
    }
}
