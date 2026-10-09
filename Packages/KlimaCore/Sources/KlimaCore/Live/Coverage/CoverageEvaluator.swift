import Foundation

/// KlimaTicket coverage rule engine over `coverage_rules.json` (SPEC §C2). A port of the reference
/// `$OEBB/official/client.py` `Coverage` (classify, classify_regional, aggregate) with its documented fixes.
/// Pure: no I/O and no clock; the station index only resolves federal states of stops.
public final class CoverageEvaluator: Sendable {
    /// Federal-state codes of `Station.state` inside Austria.
    static let austrianStates: Set<String> = ["W", "NÖ", "OÖ", "S", "T", "V", "K", "ST", "B"]
    /// Rule-id prefixes the regional families never use (KlimaTicket-Ö geography and night-train logic).
    static let regionalSkipPrefixes = ["cross-border", "transit-", "freilassing", "night-train"]

    public let ruleSet: CoverageRuleSet
    let stations: StationIndex
    /// Rules by ascending priority; equal priorities keep file order.
    let sortedRules: [CoverageRuleSet.Rule]
    let rulesByID: [String: CoverageRuleSet.Rule]

    public init(rulesJSON: Data, stations: StationIndex) throws {
        let set = try CoverageRuleSet(jsonData: rulesJSON)
        ruleSet = set
        self.stations = stations
        sortedRules = set.rules.enumerated()
            .sorted { $0.element.priority != $1.element.priority ? $0.element.priority < $1.element.priority : $0.offset < $1.offset }
            .map(\.element)
        var byID: [String: CoverageRuleSet.Rule] = [:]
        for r in set.rules where byID[r.id] == nil { byID[r.id] = r }
        rulesByID = byID
    }

    /// Operator keys of the rule file the engine does not know (they evaluate to `false`). Log once at load.
    public var unknownOperatorKeys: [String] { ruleSet.unknownOperatorKeys }

    // MARK: - Ticket scope

    /// `oe-…` → `.oe`; else the first regional family whose `productIdPrefixes` prefixes the id; else `.unsupported`
    /// (e.g. `tirol-innsbruck`, `tirol-regionen`, `vbg-lokal-*`, custom products).
    public func scope(forProductID id: String) -> TicketScope {
        if id.hasPrefix("oe-") { return .oe }
        for key in ruleSet.regionalScopes.keys.sorted() {
            if ruleSet.regionalScopes[key]?.productIdPrefixes.contains(where: { id.hasPrefix($0) }) == true {
                return .regional(key)
            }
        }
        return .unsupported
    }

    // MARK: - Legs

    public func evaluate(_ input: CoverageLegInput, scope: TicketScope) -> LegCoverage {
        let leg = EvalLeg(input, evaluator: self)
        switch scope {
        case .oe:
            return classifyOe(leg)
        case .regional(let family):
            return classifyRegional(leg, family: family)
        case .unsupported:
            guard leg.input.legType == "JNY" else { return LegCoverage(result: .notApplicable, ruleID: "non-ride-leg") }
            return LegCoverage(result: .unknown, ruleID: "unsupported-ticket", badge: "Gültigkeit prüfen", confidence: "n/a")
        }
    }

    // MARK: - Journeys

    /// One `LegCoverage` per `journey.legs` element (walks and transfers → `notApplicable`), the aggregate
    /// (`ui.tripAggregation`, SPEC §C2.5) and the covered prefix of ride legs.
    public func evaluate(_ journey: Journey, scope: TicketScope) -> JourneyCoverage {
        let legs = journey.legs.map { evaluate(CoverageLegInput(leg: $0, stations: stations), scope: scope) }
        let overall = Self.aggregate(legs.map(\.result))
        // Longest prefix of ride legs that are covered or surcharge; a partial leg ends it with its last covered stop.
        var lastIndex: Int?
        var lastStop: String?
        var wholeJourney = true
        for (i, leg) in journey.legs.enumerated() where leg.kind == .ride {
            let r = legs[i]
            if r.result == .covered || r.result == .surcharge {
                lastIndex = i
                lastStop = leg.destination.name
                continue
            }
            wholeJourney = false
            if r.result == .partial {
                lastIndex = i
                lastStop = r.lastCoveredStopName
            }
            break
        }
        return JourneyCoverage(overall: overall, legs: legs, lastCoveredLegIndex: lastIndex,
                               lastCoveredStopName: wholeJourney ? nil : lastStop)
    }

    /// `ui.tripAggregation`: over ride results (everything but `notApplicable`).
    public static func aggregate(_ results: [CoverageResult]) -> CoverageResult {
        let ride = results.filter { $0 != .notApplicable }
        guard !ride.isEmpty else { return .notApplicable }
        let kinds = Set(ride)
        if kinds.isSubset(of: [.covered, .surcharge]) { return .covered }
        if kinds == [.notCovered] { return .notCovered }
        if kinds.contains(.unknown), kinds.isDisjoint(with: [.notCovered, .partial, .discount]) { return .unknown }
        return .partial
    }

    // MARK: - KlimaTicket Ö

    private func classifyOe(_ leg: EvalLeg) -> LegCoverage {
        for rule in sortedRules where Self.applies(rule, family: nil) && matches(rule.match, leg, depth: 0) {
            var result = rule.result
            if let tirol = rule.resultTirol, leg.from.state == "T" || leg.to.state == "T" { result = tirol }
            var out = LegCoverage(result: result, ruleID: rule.id, badge: rule.badge?.de, confidence: rule.confidence)
            if result == .partial {
                if let last = leg.lastCoveredStop() {
                    out.lastCoveredStopName = last.name
                    out.badge = (out.badge ?? "").replacingOccurrences(of: "{lastCoveredStop}", with: last.name ?? "?")
                } else {
                    out.result = .notCovered
                    out.badge = "Nicht im KlimaTicket (Auslandsabschnitt)"
                }
            }
            if rule.id == "toll-surcharge" && !leg.tollSectionOnLeg() {
                // [LIVE quirk] the Bus 260 toll remark is attached to Landeck–Ischgl legs that never reach the toll road.
                out.result = .covered
                out.badge = "Inklusive"
            }
            return out
        }
        return LegCoverage(result: .unknown)
    }

    // MARK: - Regional families (reference `classify_regional`, verbatim order)

    private func classifyRegional(_ leg: EvalLeg, family: String) -> LegCoverage {
        guard leg.input.legType == "JNY" else { return LegCoverage(result: .notApplicable, ruleID: "non-ride-leg") }
        let skip = { (id: String) in Self.regionalSkipPrefixes.contains { id.hasPrefix($0) } }
        // 1. Hard exclusions (coaches, airport lines, tourist railways …) win over the scope.
        for rule in sortedRules where rule.priority < 20 && (rule.result == .notCovered || rule.result == .discount)
            && Self.applies(rule, family: family) && !skip(rule.id) && rule.id != "non-ride-leg" {
            if matches(rule.match, leg, depth: 0) {
                return LegCoverage(result: rule.result, ruleID: rule.id, badge: rule.badge?.de, confidence: rule.confidence)
            }
        }
        guard let scope = ruleSet.regionalScopes[family] else {
            return LegCoverage(result: .unknown, ruleID: "scope:\(family)", badge: "Gültigkeit prüfen", confidence: "n/a")
        }
        // 2. include, 3. exclude (a transit-section exclude uses the transit heuristic only).
        let included = scope.include.map { matches($0, leg, depth: 0) } ?? true
        var excluded = false
        for ex in scope.exclude {
            if ex.hasTransitSection {
                if leg.onTransitSection() { excluded = true; break }
                continue
            }
            if matches(ex, leg, depth: 0) { excluded = true; break }
        }
        // 4. Not included.
        if !included {
            let unknownState = leg.from.state == nil || leg.to.state == nil
            return LegCoverage(result: unknownState ? .unknown : .notCovered, ruleID: "scope:\(family)",
                               badge: unknownState ? "Gültigkeit prüfen" : "Außerhalb des Geltungsbereichs", confidence: scope.confidence)
        }
        if excluded {
            return LegCoverage(result: .notCovered, ruleID: "scope-exclude:\(family)", badge: "Nicht in diesem KlimaTicket enthalten",
                               confidence: scope.confidence)
        }
        // 5. Remaining rules below priority 60 (KlimaTicket-Ö geography skipped).
        for rule in sortedRules where rule.priority < 60 && rule.id != "fallback" && Self.applies(rule, family: family) && !skip(rule.id) {
            if matches(rule.match, leg, depth: 0) {
                return LegCoverage(result: rule.result, ruleID: rule.id, badge: rule.badge?.de, confidence: rule.confidence)
            }
        }
        // 6. In scope.
        return LegCoverage(result: .covered, ruleID: "scope:\(family)", badge: "Inklusive", confidence: scope.confidence)
    }

    /// `appliesTo` contains `*`, `oe` (family nil = KlimaTicket Ö), or `regional:*` / `regional:<family>`.
    static func applies(_ rule: CoverageRuleSet.Rule, family: String?) -> Bool {
        if rule.appliesTo.contains("*") { return true }
        guard let family else { return rule.appliesTo.contains("oe") }
        return rule.appliesTo.contains("regional:*") || rule.appliesTo.contains("regional:\(family)")
    }

    // MARK: - Matcher (reference `m` / `m1`)

    private static let maxRuleRefDepth = 12

    func matches(_ node: MatchNode, _ leg: EvalLeg, depth: Int) -> Bool {
        for c in node.conditions where !holds(c, leg, depth: depth) { return false }
        return true
    }

    private func holds(_ c: MatchCondition, _ leg: EvalLeg, depth: Int) -> Bool {
        let input = leg.input
        switch c {
        case .anyOf(let nodes): return nodes.contains { matches($0, leg, depth: depth) }
        case .allOf(let nodes): return nodes.allSatisfy { matches($0, leg, depth: depth) }
        case .not(let node): return !matches(node, leg, depth: depth)
        case .always: return true
        case .legTypeIn(let v): return v.contains(input.legType)
        case .operatorRegex(let r): return r.search(input.operator)
        case .productNameRegex(let r): return r.search(input.productName)
        case .categoryLongRegex(let r): return r.search(input.categoryLong)
        case .remarkRegex(let r): return input.remarks.contains { r.search($0) }
        case .stopNameRegex(let r): return leg.allStops.contains { r.search($0.name) }
        case .categoryIn(let v): return v.contains((input.category ?? "").trimmingCharacters(in: .whitespaces))
        case .lineIn(let v): return v.contains((input.line ?? "").trimmingCharacters(in: .whitespaces))
        case .lineIdPrefix(let v): return v.contains { (input.lineId ?? "").hasPrefix($0) }
        case .adminPrefix(let v): return (input.admin ?? "").hasPrefix(v)
        case .clsAny(let table):
            guard let cls = input.cls else { return false }
            return (table[input.clsScheme ?? ""] ?? []).contains { cls & $0 != 0 }
        case .anyStopStateIn(let v): return leg.allStops.contains { $0.state.map(v.contains) ?? false }
        case .allStopsStateIn(let v): return leg.allStops.allSatisfy { $0.state.map(v.contains) ?? false }
        case .anyStopStateNotIn(let v):
            // An unknown state (stop not in the StationIndex) is not evidence of leaving the area.
            return leg.allStops.contains { s in s.state.map { !v.contains($0) } ?? false }
        case .anyStopOutsideAustria(let v): return v == (!leg.from.atOrGbf || !leg.to.atOrGbf)
        case .allStopsInAustriaOrGemeinschaftsbahnhof(let v): return v == leg.allStops.allSatisfy(\.atOrGbf)
        case .boardAndAlightInAustria(let v): return v == (leg.from.atOrGbf && leg.to.atOrGbf)
        case .onTransitSection: return leg.onTransitSection()
        case .operatorRegexFrom:
            return ruleSet.acceptedOperatorsRail.contains { $0.regex?.search(input.operator ?? "") ?? false }
        case .ruleRef(let id):
            guard depth < Self.maxRuleRefDepth, let rule = rulesByID[id] else { return false }
            return matches(rule.match, leg, depth: depth + 1)
        case .unknown:
            return false
        }
    }

    // MARK: - Stops

    /// Federal state of the nearest station within 2 km (reference `nearest_state`).
    func nearestState(_ lat: Double, _ lon: Double) -> String? {
        guard let hit = stations.nearest(to: GeoPoint(latitude: lat, longitude: lon), limit: 1, maxKm: 2).first,
              hit.distanceKm < 2 else { return nil }
        return hit.station.state
    }

    /// Gemeinschaftsbahnhof within 400 m, or whose `nameRegex` matches the stop name.
    func isGemeinschaftsbahnhof(name: String?, lat: Double?, lon: Double?) -> Bool {
        ruleSet.gemeinschaftsbahnhoefe.contains { g in
            if let lat, let lon, let glat = g.lat, let glon = g.lon,
               GeoPoint(latitude: lat, longitude: lon).distanceKm(to: GeoPoint(latitude: glat, longitude: glon)) < 0.4 {
                return true
            }
            return g.nameRegex?.search(name ?? "") ?? false
        }
    }
}

// MARK: - Evaluation context

/// A stop with derived facts (reference `enrich_stop`): state from the station index when missing, country from the
/// state ("AT" for Austrian states, "XX" for foreign stations), Gemeinschaftsbahnhof flag.
struct EvalStop {
    let name: String?
    let state: String?
    let country: String?
    /// Only computed for stops outside Austria (it matters only for `atOrGbf`; regex + distance per stop is costly).
    let isGemeinschaftsbahnhof: Bool

    init(_ s: CoverageLegInput.Stop, evaluator: CoverageEvaluator) {
        name = s.name
        var state = s.state?.nilIfEmpty
        if state == nil, let lat = s.lat, let lon = s.lon { state = evaluator.nearestState(lat, lon) }
        self.state = state
        var country = s.country?.uppercased().nilIfEmpty
        if country == nil, let state {
            if CoverageEvaluator.austrianStates.contains(state) { country = "AT" } else if state == "X" { country = "XX" }
        }
        self.country = country
        let inAustria = country?.hasPrefix("AT") ?? false
        isGemeinschaftsbahnhof = !inAustria && evaluator.isGemeinschaftsbahnhof(name: s.name, lat: s.lat, lon: s.lon)
    }

    var inAustria: Bool { country?.hasPrefix("AT") ?? false }
    var atOrGbf: Bool { inAustria || isGemeinschaftsbahnhof }
}

struct EvalLeg {
    let input: CoverageLegInput
    let from: EvalStop
    let to: EvalStop
    let passList: [EvalStop]

    init(_ input: CoverageLegInput, evaluator: CoverageEvaluator) {
        self.input = input
        from = EvalStop(input.from, evaluator: evaluator)
        to = EvalStop(input.to, evaluator: evaluator)
        passList = input.passList.map { EvalStop($0, evaluator: evaluator) }
    }

    /// from, to, then the pass list (reference order for "any stop" operators).
    var allStops: [EvalStop] { [from, to] + passList }

    /// Boarding and alighting in Austria (or a Gemeinschaftsbahnhof) with at least one foreign intermediate stop
    /// (Deutsches Eck, Tisis–Buchs, …).
    func onTransitSection() -> Bool {
        from.atOrGbf && to.atOrGbf && passList.contains { !$0.atOrGbf }
    }

    /// Walks from, pass list, to and stops at the first stop outside Austria; nil when the leg starts abroad.
    func lastCoveredStop() -> EvalStop? {
        var last: EvalStop?
        for s in [from] + passList + [to] {
            guard s.atOrGbf else { break }
            last = s
        }
        return last
    }

    /// `toll-surcharge` scope check: a remark quoting stop names ("Galtür Mautstelle") applies only when the first
    /// word of one of them occurs in a stop name of this leg. No quoted names → the remark applies.
    func tollSectionOnLeg() -> Bool {
        let quoted = input.remarks.flatMap(Self.quotedNames)
        guard !quoted.isEmpty else { return true }
        let names = allStopsInTravelOrder.map { ($0.name ?? "").lowercased() }
        return quoted.contains { q in
            let first = q.lowercased().split(separator: " ", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            return names.contains { $0.contains(first) }
        }
    }

    private var allStopsInTravelOrder: [EvalStop] { [from, to] + passList }

    private static let quoteRegex = CompiledRegex("\"([^\"]+)\"")

    static func quotedNames(_ text: String) -> [String] {
        guard let re = quoteRegex?.regex else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : nil
        }
    }
}
