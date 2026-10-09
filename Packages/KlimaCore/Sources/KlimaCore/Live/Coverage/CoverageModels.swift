import Foundation

// CONTRACT (Step 0) – owned by WP-C after the contracts commit.

/// Result of matching one leg (or a whole journey) against the KlimaTicket coverage rules (coverage_rules.json).
public enum CoverageResult: String, Codable, Sendable, Hashable {
    case covered
    /// Covered, plus a required or optional extra (toll, night bus, couchette).
    case surcharge
    /// Not covered but discounted for holders (CAT).
    case discount
    /// Covered only up to the border / Gemeinschaftsbahnhof.
    case partial
    case notCovered
    /// Cannot decide → UI says "Gültigkeit prüfen", never claims coverage.
    case unknown
    /// Walk / transfer legs.
    case notApplicable
}

/// Which ticket the user holds, derived from `TicketProduct.id` via `regionalScopes[*].productIdPrefixes`.
public enum TicketScope: Codable, Sendable, Hashable {
    /// KlimaTicket Ö (all variants)
    case oe
    /// Regional family key from coverage_rules.json regionalScopes ("tirol", "vbg", "sbg", "ooe", "vor-metropolregion",
    /// "vor-region", "wien", "stmk", "ktn").
    case regional(String)
    /// Custom or unknown product → every ride leg evaluates to `.unknown`.
    case unsupported
}

/// Normalised leg as the rule engine sees it (provider neutral; SPEC §C2.2). Decodable so the official synthetic cases
/// (fixtures/coverage/synthetic_cases.json) can be fed in verbatim.
public struct CoverageLegInput: Codable, Sendable, Hashable {
    public struct Stop: Codable, Sendable, Hashable {
        public var name: String?
        public var lat: Double?
        public var lon: Double?
        /// Upper-case ISO code ("AT", "DE") when known.
        public var country: String?
        /// App federal state code (W, NÖ, OÖ, S, T, V, K, ST, B, X) – from StationIndex when known.
        public var state: String?

        public init(name: String?, lat: Double? = nil, lon: Double? = nil, country: String? = nil, state: String? = nil) {
            self.name = name
            self.lat = lat
            self.lon = lon
            self.country = country
            self.state = state
        }
    }

    /// "JNY", "WALK", "TRSF" …
    public var legType: String
    public var `operator`: String?
    public var productName: String?
    public var category: String?
    public var categoryLong: String?
    public var cls: Int?
    /// "oebb-mgate" for ÖBB HAFAS, "vao-rest" for VAO REST.
    public var clsScheme: String?
    public var admin: String?
    public var lineId: String?
    public var line: String?
    public var remarks: [String]
    public var from: Stop
    public var to: Stop
    public var passList: [Stop]

    public init(legType: String, operator: String? = nil, productName: String? = nil, category: String? = nil,
                categoryLong: String? = nil, cls: Int? = nil, clsScheme: String? = "oebb-mgate", admin: String? = nil,
                lineId: String? = nil, line: String? = nil, remarks: [String] = [], from: Stop, to: Stop, passList: [Stop] = []) {
        self.legType = legType
        self.operator = `operator`
        self.productName = productName
        self.category = category
        self.categoryLong = categoryLong
        self.cls = cls
        self.clsScheme = clsScheme
        self.admin = admin
        self.lineId = lineId
        self.line = line
        self.remarks = remarks
        self.from = from
        self.to = to
        self.passList = passList
    }
}

public struct LegCoverage: Codable, Sendable, Hashable {
    public var result: CoverageResult
    /// Winning rule id ("oebb-long-distance", "long-distance-coach", "scope:tirol" …).
    public var ruleID: String?
    /// German badge ("Inklusive", "Nicht im KlimaTicket", "KlimaTicket gilt bis Salzburg Hbf").
    public var badge: String?
    /// "high" | "medium" | "low" from the rule.
    public var confidence: String?
    /// For `.partial`: name of the last stop inside Austria / Gemeinschaftsbahnhof.
    public var lastCoveredStopName: String?

    public init(result: CoverageResult, ruleID: String? = nil, badge: String? = nil, confidence: String? = nil,
                lastCoveredStopName: String? = nil) {
        self.result = result
        self.ruleID = ruleID
        self.badge = badge
        self.confidence = confidence
        self.lastCoveredStopName = lastCoveredStopName
    }
}

public struct JourneyCoverage: Codable, Sendable, Hashable {
    /// Aggregated per coverage_rules.json ui.tripAggregation (SPEC §C2.5).
    public var overall: CoverageResult
    /// One entry per `Journey.legs` element (walks → notApplicable).
    public var legs: [LegCoverage]
    /// Index into `Journey.legs` of the last ride leg that is (at least partially) covered, counting from the start.
    public var lastCoveredLegIndex: Int?
    /// Name of the last covered stop when the journey leaves the scope (border, regional area).
    public var lastCoveredStopName: String?

    public init(overall: CoverageResult, legs: [LegCoverage], lastCoveredLegIndex: Int? = nil, lastCoveredStopName: String? = nil) {
        self.overall = overall
        self.legs = legs
        self.lastCoveredLegIndex = lastCoveredLegIndex
        self.lastCoveredStopName = lastCoveredStopName
    }
}
