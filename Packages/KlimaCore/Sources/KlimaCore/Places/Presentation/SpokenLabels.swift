import Foundation

/// German VoiceOver strings of the Wegzeichen (docs/ENRICH_SPEC.md §2.5, BADGE_SPEC §5). One label per row / plate
/// row; the views add no extra elements.
public enum SpokenLabels {
    /// Spoken names of the train categories (fern, nacht, regio).
    public static let categoryNames: [String: String] = [
        "RJX": "Railjet Xpress", "RJ": "Railjet", "ICE": "Intercity-Express", "ECE": "Eurocity-Express", "EC": "Eurocity",
        "IC": "Intercity", "D": "Schnellzug", "TGV": "TGV", "WB": "WESTbahn", "NJ": "Nightjet", "EN": "Euronight",
        "REX": "Regionalexpress", "CJX": "Cityjet Xpress", "R": "Regionalzug", "RE": "Regional-Express",
        "RB": "Regionalbahn", "IR": "Interregio",
    ]

    /// „Bus 852“, „S-Bahn S45“, „U-Bahn-Linie U4“, „Straßenbahn D“, „Railjet Xpress“, „Nightjet“, „Regionalexpress 41“,
    /// „Nachtbus N25“, „Skibus“, „Wanderbus 412“, „Rufbus 581, nur auf Bestellung“, „Schienenersatzverkehr SV400“,
    /// „Seilbahn Hungerburgbahn“, „Schiff Achenseeschifffahrt“. The full ref is read („Bus 9773/5“).
    public static func plate(_ line: LineRef, services: [PlaceService] = []) -> String {
        plate(line, services: services, onDemandHint: true)
    }

    static func plate(_ line: LineRef, services: [PlaceService], onDemandHint: Bool) -> String {
        let kind = LineKind.classify(line, services: services)
        let ref = LinePlateText.trimmed(line.ref)
        let shown = ref.isEmpty ? (line.name ?? "") : ref
        switch kind {
        case .fern, .nacht:
            let cat = LinePlateText.canonicalCategory(RailRef(shown).category)
            return categoryNames[cat.uppercased()] ?? (cat.isEmpty ? kind.spokenNoun : "\(kind.spokenNoun) \(cat)")
        case .regio:
            let text = LinePlateText.text(for: line, kind: kind, size: .l).text
            let r = RailRef(text)
            if let n = categoryNames[r.category.uppercased()] { return r.number.isEmpty ? n : "\(n) \(r.number)" }
            return text.isEmpty ? kind.spokenNoun : "\(kind.spokenNoun) \(text)"
        case .sBahn, .uBahn:
            let text = LinePlateText.text(for: line, kind: kind, size: .l).text
            return text.isEmpty || text == "S" || text == "U" ? kind.spokenNoun : "\(kind.spokenNoun) \(text)"
        case .bus, .nachtbus, .skibus, .wanderbus, .rufbus:
            let base: String
            if shown.isEmpty {
                base = kind.spokenNoun
            } else if PlaceNormalizer.fold(shown).contains("bus") {
                base = shown                                  // „Skibus“, „Shuttlebus“, „Rufbus Pitztal“
            } else {
                base = "\(kind.spokenNoun) \(shown)"
            }
            return kind == .rufbus && onDemandHint ? base + ", nur auf Bestellung" : base
        case .tram, .sev, .seilbahn, .schiff, .sonst:
            return shown.isEmpty ? kind.spokenNoun : "\(kind.spokenNoun) \(shown)"
        }
    }

    /// „Linien: Bus 110, Bus 852, Skibus, und 5 weitere“ (one element for the whole plate row).
    public static func plateRow(_ lines: [LineRef], overflow: Int = 0, services: [PlaceService] = []) -> String {
        let parts = lines.map { plate($0, services: services) }
        guard !parts.isEmpty || overflow > 0 else { return "Keine Linien bekannt" }
        var s = (parts.count == 1 && overflow == 0 ? "Linie: " : "Linien: ") + parts.joined(separator: ", ")
        if overflow > 0 { s += parts.isEmpty ? "\(overflow) Linien" : ", und \(overflow) weitere" }
        return s
    }

    /// Search row: „Warth (Vorarlberg) Dorfplatz, Bushaltestelle, Vorarlberg, Skigebiet Ski Arlberg, Linien: Bus 110,
    /// Bus 852, Skibus“ (BADGE_SPEC §4.1: name, kind, state[, ski area][, Gemeinde], lines[, favourite][, distance]).
    /// `municipality` only when the row shows it (the title does not start with it).
    public static func stopRow(place: Place, tags: PlaceTags = .empty, lines: [LineRef], overflow: Int = 0,
                               skiAreaName: String? = nil, municipality: String? = nil, isFavourite: Bool = false,
                               distanceMeters: Double? = nil) -> String {
        var parts = [PlaceNames.display(place.name), StopKindLabel.label(place: place, tags: tags)]
        if let fs = place.federalState { parts.append(fs.displayName) }
        if let ski = skiAreaName, !ski.isEmpty { parts.append(skiArea(ski)) }
        if let m = municipality, !m.isEmpty { parts.append(m) }
        if !lines.isEmpty || overflow > 0 { parts.append(plateRow(lines, overflow: overflow, services: tags.services)) }
        if isFavourite { parts.append("Favorit") }
        if let d = distanceMeters { parts.append(distance(d)) }
        return parts.joined(separator: ", ")
    }

    /// Line row in the stop detail: „Bus 110, von Reutte Bahnhof nach Lech Schlosskopf, Postbus, Tirol und Vorarlberg“.
    /// `from`/`to` are the display-cleaned termini (default: `line.termini`).
    public static func lineRow(_ line: LineRef, from: String? = nil, to: String? = nil, services: [PlaceService] = [])
        -> String {
        var parts = [plate(line, services: services)]
        let a = from ?? line.termini?.from, b = to ?? line.termini?.to
        switch (a.flatMap(nonEmpty), b.flatMap(nonEmpty)) {
        case let (x?, y?): parts.append("von \(x) nach \(y)")
        case let (x?, nil): parts.append("ab \(x)")
        case let (nil, y?): parts.append("nach \(y)")
        default: break
        }
        if let op = line.operatorName.flatMap(nonEmpty) { parts.append(op) }
        let states = line.states.compactMap(FederalState.init(rawValue:)).filter { $0 != .foreign }
            .map(\.displayName).sorted { PlaceNormalizer.fold($0) < PlaceNormalizer.fold($1) }
        if !states.isEmpty { parts.append(list(states)) }
        return parts.joined(separator: ", ")
    }

    /// Departure: „Bus 852 nach Lech Schlosskopf, in 6 Minuten, um 14:38, Echtzeit“ / „…, 3 Minuten verspätet“ /
    /// „…, um 14:38, fällt aus“; without realtime „…, laut Fahrplan“. Times in `timeZone` (Austria).
    public static func departure(line: LineRef, direction: String, planned: Date, realtime: Date? = nil,
                                 isCancelled: Bool = false, now: Date = Date(),
                                 timeZone: TimeZone = TimeZone(identifier: "Europe/Vienna") ?? .current) -> String {
        var parts = ["\(plate(line, services: [], onDemandHint: false)) nach \(direction)"]
        let effective = realtime ?? planned
        if isCancelled {
            parts.append("um \(clock(planned, timeZone))")
            parts.append("fällt aus")
            return parts.joined(separator: ", ")
        }
        let minutes = wholeMinutes(effective.timeIntervalSince(now), .down)
        if minutes <= 0 { parts.append("jetzt") } else { parts.append(minutes == 1 ? "in 1 Minute" : "in \(minutes) Minuten") }
        parts.append("um \(clock(effective, timeZone))")
        if let realtime {
            let delay = wholeMinutes(realtime.timeIntervalSince(planned), .toNearestOrAwayFromZero)
            if delay >= 1 {
                parts.append(delay == 1 ? "1 Minute verspätet" : "\(delay) Minuten verspätet")
            } else if delay <= -1 {
                parts.append(delay == -1 ? "1 Minute früher" : "\(-delay) Minuten früher")
            } else {
                parts.append("Echtzeit")
            }
        } else {
            parts.append("laut Fahrplan")
        }
        return parts.joined(separator: ", ")
    }

    /// „Bundesland Vorarlberg“.
    public static func stateMark(_ state: String) -> String {
        "Bundesland " + (FederalState(rawValue: state)?.displayName ?? state)
    }

    /// „Skigebiet Ski Arlberg“ (also when only the glyph is visible).
    public static func skiArea(_ name: String) -> String { "Skigebiet " + name }

    /// „Region Bregenzerwald“.
    public static func region(_ name: String) -> String { "Region " + name }

    /// „Bezirk Landeck“; Vienna: „10. Bezirk, Favoriten“.
    public static func bezirk(_ name: String, wienBezirk: Int? = nil) -> String {
        if let n = wienBezirk { return "\(n). Bezirk, \(name)" }
        return "Bezirk " + name
    }

    /// „120 Meter“, „1,2 Kilometer“.
    public static func distance(_ meters: Double) -> String {
        // `Int(_:)` traps on NaN/∞ (a distance from a broken coordinate); clamp to a sane range first
        let meters = meters.isFinite ? min(max(0, meters), 100_000_000) : 0
        if meters < 1_000 { return "\(Int(meters.rounded())) Meter" }
        let km = (meters / 100).rounded() / 10
        let text = km == km.rounded() ? String(Int(km)) : String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")
        return "\(text) Kilometer"
    }

    /// „A, B und C“.
    static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " und " + items.last!
    }

    /// Seconds → whole minutes without trapping on NaN/∞ or absurd dates (`Int(_:)` would).
    static func wholeMinutes(_ seconds: TimeInterval, _ rule: FloatingPointRoundingRule) -> Int {
        guard seconds.isFinite else { return 0 }
        return Int((min(max(seconds, -1e9), 1e9) / 60).rounded(rule))
    }

    static func clock(_ date: Date, _ tz: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func nonEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}
