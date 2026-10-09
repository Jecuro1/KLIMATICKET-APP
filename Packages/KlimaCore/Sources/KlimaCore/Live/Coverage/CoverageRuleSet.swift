import Foundation

/// Decodable model of `coverage_rules.json` (schemaVersion 1; SPEC §C2.1). Regexes are compiled while decoding, so a
/// decoded rule set is ready to evaluate.
///
/// Tolerance rules:
/// - Documentation keys inside match nodes are ignored: `verification`, `note`, `notes`, `plus`, `sources`, `westbahn`
///   and every key starting with `_` (the Python reference crashes on `regionalScopes.wien.include.plus`).
/// - An unknown operator key, a value of the wrong type or a regex that does not compile turns that condition into
///   `false` (the containing node then fails). Such keys are collected once in `unknownOperatorKeys` for the app to log.
/// - A newer `schemaVersion` throws `CoverageRuleSet.LoadError.unsupportedSchema` instead of guessing.
public struct CoverageRuleSet: Decodable, Sendable {
    public static let supportedSchemaVersion = 1

    public enum LoadError: Error, Equatable, Sendable {
        case unsupportedSchema(Int)
    }

    public struct Badge: Decodable, Sendable, Hashable {
        public var de: String?
        public var style: String?
    }

    public struct Rule: Decodable, Sendable {
        public var id: String
        public var priority: Int
        /// "*", "oe", "regional:*", "regional:<scope>".
        public var appliesTo: [String]
        public var result: CoverageResult
        /// Overrides `result` for KlimaTicket Ö when the leg starts or ends in Tirol.
        public var resultTirol: CoverageResult?
        public var badge: Badge?
        public var confidence: String?
        let match: MatchNode

        private enum CodingKeys: String, CodingKey { case id, priority, appliesTo, match, result, resultTirol, badge, confidence }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 1000
            appliesTo = try c.decodeIfPresent([String].self, forKey: .appliesTo) ?? []
            match = try c.decodeIfPresent(MatchNode.self, forKey: .match) ?? MatchNode(conditions: [])
            // An unknown result string must not crash the app: it degrades to `unknown` ("Gültigkeit prüfen").
            result = (try? c.decodeIfPresent(String.self, forKey: .result)).flatMap { CoverageResult(rawValue: $0) } ?? .unknown
            resultTirol = (try? c.decodeIfPresent(String.self, forKey: .resultTirol)).flatMap { CoverageResult(rawValue: $0) }
            badge = try? c.decodeIfPresent(Badge.self, forKey: .badge)
            confidence = try? c.decodeIfPresent(String.self, forKey: .confidence)
        }
    }

    public struct AcceptedOperator: Decodable, Sendable {
        public var label: String?
        let regex: CompiledRegex?

        private enum CodingKeys: String, CodingKey { case regex, label }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = try c.decodeIfPresent(String.self, forKey: .label)
            regex = (try c.decodeIfPresent(String.self, forKey: .regex)).flatMap(CompiledRegex.init)
        }
    }

    /// Station on foreign soil where Austrian tickets are valid (Buchs SG, Lindau-Reutin, Passau Hbf …).
    public struct Gemeinschaftsbahnhof: Decodable, Sendable {
        public var name: String
        public var country: String?
        public var lat: Double?
        public var lon: Double?
        let nameRegex: CompiledRegex?

        private enum CodingKeys: String, CodingKey { case name, country, lat, lon, nameRegex }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            country = try c.decodeIfPresent(String.self, forKey: .country)
            lat = try c.decodeIfPresent(Double.self, forKey: .lat)
            lon = try c.decodeIfPresent(Double.self, forKey: .lon)
            nameRegex = (try c.decodeIfPresent(String.self, forKey: .nameRegex)).flatMap(CompiledRegex.init)
        }
    }

    public struct TransitSection: Decodable, Sendable, Hashable {
        public var id: String
        public var endpoints: [String]
        public var via: String?

        private enum CodingKeys: String, CodingKey { case id, endpoints, via }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            endpoints = (try? c.decodeIfPresent([String].self, forKey: .endpoints)) ?? []
            via = try? c.decodeIfPresent(String.self, forKey: .via)
        }
    }

    /// Area of a regional KlimaTicket family (`regionalScopes.<key>`).
    public struct RegionalScope: Decodable, Sendable {
        /// `TicketProduct.id` prefixes of the family ("tirol-klassik", "vbg-maximo", "sbg-" …).
        public var productIdPrefixes: [String]
        public var confidence: String?
        let include: MatchNode?
        let exclude: [MatchNode]

        private enum CodingKeys: String, CodingKey { case productIdPrefixes, include, exclude, confidence }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            productIdPrefixes = (try? c.decodeIfPresent([String].self, forKey: .productIdPrefixes)) ?? []
            include = try c.decodeIfPresent(MatchNode.self, forKey: .include)
            exclude = try c.decodeIfPresent([MatchNode].self, forKey: .exclude) ?? []
            confidence = try? c.decodeIfPresent(String.self, forKey: .confidence)
        }
    }

    public var schemaVersion: Int
    /// In file order (the evaluator sorts by priority, stable).
    public var rules: [Rule]
    public var acceptedOperatorsRail: [AcceptedOperator]
    public var gemeinschaftsbahnhoefe: [Gemeinschaftsbahnhof]
    public var transitSections: [TransitSection]
    /// Keyed by family ("tirol", "vbg", "sbg", "ooe", "vor-metropolregion", "vor-region", "wien", "stmk", "ktn");
    /// documentation keys (`_howTo`) are skipped.
    public var regionalScopes: [String: RegionalScope]
    /// lineId prefix → Verbund description (documentation keys skipped).
    public var lineIdPrefixToVerbund: [String: String]
    /// Operator keys the engine does not know (each evaluates to `false`), sorted. Empty for the shipped file.
    public var unknownOperatorKeys: [String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, rules, acceptedOperatorsRail, gemeinschaftsbahnhoefe, transitSections, regionalScopes, lineIdPrefixToVerbund
    }

    /// Decodes and validates `coverage_rules.json`.
    public init(jsonData: Data) throws {
        let decoder = JSONDecoder()
        let collector = UnknownKeyCollector()
        decoder.userInfo[UnknownKeyCollector.userInfoKey] = collector
        self = try decoder.decode(CoverageRuleSet.self, from: jsonData)
        unknownOperatorKeys = collector.keys
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion <= Self.supportedSchemaVersion else { throw LoadError.unsupportedSchema(schemaVersion) }
        rules = try c.decode([Rule].self, forKey: .rules)
        acceptedOperatorsRail = try c.decodeIfPresent([AcceptedOperator].self, forKey: .acceptedOperatorsRail) ?? []
        gemeinschaftsbahnhoefe = try c.decodeIfPresent([Gemeinschaftsbahnhof].self, forKey: .gemeinschaftsbahnhoefe) ?? []
        transitSections = try c.decodeIfPresent([TransitSection].self, forKey: .transitSections) ?? []
        var scopes: [String: RegionalScope] = [:]
        if c.contains(.regionalScopes) {
            let sc = try c.nestedContainer(keyedBy: DynamicKey.self, forKey: .regionalScopes)
            for key in sc.allKeys where !key.stringValue.hasPrefix("_") {
                scopes[key.stringValue] = try sc.decode(RegionalScope.self, forKey: key)
            }
        }
        regionalScopes = scopes
        var verbund: [String: String] = [:]
        if c.contains(.lineIdPrefixToVerbund) {
            let vc = try c.nestedContainer(keyedBy: DynamicKey.self, forKey: .lineIdPrefixToVerbund)
            for key in vc.allKeys where !key.stringValue.hasPrefix("_") {
                if let v = try? vc.decode(String.self, forKey: key) { verbund[key.stringValue] = v }
            }
        }
        lineIdPrefixToVerbund = verbund
        unknownOperatorKeys = (decoder.userInfo[UnknownKeyCollector.userInfoKey] as? UnknownKeyCollector)?.keys ?? []
    }
}

// MARK: - Match nodes

/// One match node: a JSON object whose keys are AND-combined conditions (SPEC §C2.3).
struct MatchNode: Decodable, Sendable {
    var conditions: [MatchCondition]

    init(conditions: [MatchCondition]) { self.conditions = conditions }

    /// Keys that only document a node and never take part in matching.
    static let documentationKeys: Set<String> = ["verification", "note", "notes", "plus", "sources", "westbahn"]

    static func isDocumentation(_ key: String) -> Bool { key.hasPrefix("_") || documentationKeys.contains(key) }

    /// True when the node names a transit section at top level (regional `exclude: [{onTransitSection: "…"}]`).
    var hasTransitSection: Bool {
        conditions.contains { if case .onTransitSection(let active) = $0 { return active } else { return false } }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        let collector = decoder.userInfo[UnknownKeyCollector.userInfoKey] as? UnknownKeyCollector
        var out: [MatchCondition] = []
        // Sorted for a deterministic evaluation order (JSON object key order is not guaranteed by every decoder).
        for key in c.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
            let k = key.stringValue
            if Self.isDocumentation(k) { continue }
            let condition = Self.condition(k, c, key)
            if case .unknown(let name) = condition { collector?.add(name) }
            out.append(condition)
        }
        conditions = out
    }

    private static func condition(_ k: String, _ c: KeyedDecodingContainer<DynamicKey>, _ key: DynamicKey) -> MatchCondition {
        func strings() -> [String]? { try? c.decode([String].self, forKey: key) }
        func string() -> String? { try? c.decode(String.self, forKey: key) }
        func bool() -> Bool? { try? c.decode(Bool.self, forKey: key) }
        func regex() -> MatchCondition {
            guard let p = string() else { return .unknown(k) }
            guard let r = CompiledRegex(p) else { return .unknown("\(k) (ungültiger Ausdruck)") }
            switch k {
            case "operatorRegex": return .operatorRegex(r)
            case "productNameRegex": return .productNameRegex(r)
            case "categoryLongRegex": return .categoryLongRegex(r)
            case "remarkRegex": return .remarkRegex(r)
            default: return .stopNameRegex(r)
            }
        }
        switch k {
        case "anyOf":
            return (try? c.decode([MatchNode].self, forKey: key)).map(MatchCondition.anyOf) ?? .unknown(k)
        case "allOf":
            return (try? c.decode([MatchNode].self, forKey: key)).map(MatchCondition.allOf) ?? .unknown(k)
        case "not":
            return (try? c.decode(MatchNode.self, forKey: key)).map(MatchCondition.not) ?? .unknown(k)
        case "always":
            return .always
        case "legTypeIn":
            return strings().map(MatchCondition.legTypeIn) ?? .unknown(k)
        case "operatorRegex", "productNameRegex", "categoryLongRegex", "remarkRegex", "stopNameRegex":
            return regex()
        case "categoryIn":
            return strings().map(MatchCondition.categoryIn) ?? .unknown(k)
        case "lineIn":
            return strings().map(MatchCondition.lineIn) ?? .unknown(k)
        case "lineIdPrefix":
            return strings().map(MatchCondition.lineIdPrefix) ?? .unknown(k)
        case "adminPrefix":
            return string().map(MatchCondition.adminPrefix) ?? .unknown(k)
        case "clsAny":
            return (try? c.decode([String: [Int]].self, forKey: key)).map(MatchCondition.clsAny) ?? .unknown(k)
        case "stopStateIn", "anyStopStateIn":
            return strings().map(MatchCondition.anyStopStateIn) ?? .unknown(k)
        case "allStopsStateIn":
            return strings().map(MatchCondition.allStopsStateIn) ?? .unknown(k)
        case "anyStopStateNotIn":
            return strings().map(MatchCondition.anyStopStateNotIn) ?? .unknown(k)
        case "anyStopOutsideAustria":
            return bool().map(MatchCondition.anyStopOutsideAustria) ?? .unknown(k)
        case "allStopsInAustriaOrGemeinschaftsbahnhof":
            return bool().map(MatchCondition.allStopsInAustriaOrGemeinschaftsbahnhof) ?? .unknown(k)
        case "boardAndAlightInAustria":
            return bool().map(MatchCondition.boardAndAlightInAustria) ?? .unknown(k)
        case "onTransitSection":
            // `true` in rules, a section id in regional excludes; the reference evaluates the heuristic either way.
            if let b = bool() { return .onTransitSection(active: b) }
            if let s = string() { return .onTransitSection(active: !s.isEmpty) }
            return .unknown(k)
        case "operatorRegexFrom":
            return string().map(MatchCondition.operatorRegexFrom) ?? .unknown(k)
        case "ruleRef":
            return string().map(MatchCondition.ruleRef) ?? .unknown(k)
        default:
            return .unknown(k)
        }
    }
}

/// Match operators (exact semantics of the reference `Coverage.m1`, SPEC §C2.3).
indirect enum MatchCondition: Sendable {
    case anyOf([MatchNode])
    case allOf([MatchNode])
    case not(MatchNode)
    case always
    case legTypeIn([String])
    case operatorRegex(CompiledRegex)
    case productNameRegex(CompiledRegex)
    case categoryLongRegex(CompiledRegex)
    case remarkRegex(CompiledRegex)
    case stopNameRegex(CompiledRegex)
    case categoryIn([String])
    case lineIn([String])
    case lineIdPrefix([String])
    case adminPrefix(String)
    case clsAny([String: [Int]])
    case anyStopStateIn([String])
    case allStopsStateIn([String])
    case anyStopStateNotIn([String])
    case anyStopOutsideAustria(Bool)
    case allStopsInAustriaOrGemeinschaftsbahnhof(Bool)
    case boardAndAlightInAustria(Bool)
    /// `active` is false only for an explicit `false`/empty value; the heuristic itself ignores the value (reference).
    case onTransitSection(active: Bool)
    case operatorRegexFrom(String)
    case ruleRef(String)
    /// Unknown operator or malformed value: always false.
    case unknown(String)
}

/// Precompiled `NSRegularExpression` (patterns verbatim, inline `(?i)`). Immutable and thread-safe.
struct CompiledRegex: @unchecked Sendable {
    let pattern: String
    let regex: NSRegularExpression

    init?(_ pattern: String) {
        guard let r = try? NSRegularExpression(pattern: pattern) else { return nil }
        self.pattern = pattern
        regex = r
    }

    /// Python `re.search` semantics: true when the pattern occurs anywhere; nil/empty text never matches.
    func search(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Collects unknown operator keys during one decode (for `CoverageRuleSet.unknownOperatorKeys`).
final class UnknownKeyCollector: @unchecked Sendable {
    static let userInfoKey = CodingUserInfoKey(rawValue: "klimabilanz.coverage.unknownKeys")!
    private let lock = NSLock()
    private var set = Set<String>()

    func add(_ key: String) {
        lock.lock()
        set.insert(key)
        lock.unlock()
    }

    var keys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return set.sorted()
    }
}
