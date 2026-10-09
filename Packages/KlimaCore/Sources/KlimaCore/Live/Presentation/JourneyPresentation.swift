import Foundation

// Connection cards, journey bar, transfers, notices and VoiceOver text (SPEC §C3.4). Pure: `now` is injected.
// Expected values: FX/ux/vm_trips_*.json (reference `$OEBB/ux/client.py`).

/// Platform of a stop event: „Gl. 3“ for tracks, „Steig C“ for bus and tram bays.
public struct PlatformLabel: Codable, Sendable, Hashable {
    /// „Gl.“ or „Steig“.
    public var label: String
    public var planned: String?
    public var realtime: String?
    public var changed: Bool
    /// Realtime platform when known, else the planned one.
    public var display: String

    public init(label: String, planned: String?, realtime: String?, changed: Bool, display: String) {
        self.label = label
        self.planned = planned
        self.realtime = realtime
        self.changed = changed
        self.display = display
    }

    /// „Gl. 3“ / „Steig C“.
    public var text: String { "\(label) \(display)" }
    /// VoiceOver: „Gleis 3“ / „Steig C“.
    public var spoken: String { "\(label == "Gl." ? "Gleis" : label) \(display)" }
}

/// One connection card in the results list.
public struct ConnectionSummary: Sendable, Hashable, Identifiable {
    public enum Tag: String, Codable, Sendable, Hashable, CaseIterable {
        case fastest, fewestChanges

        /// Chip text: „Schnellste“ / „Wenigste Umstiege“.
        public var title: String { self == .fastest ? "Schnellste" : "Wenigste Umstiege" }
    }

    /// `Journey.id`.
    public var id: String
    public var departure: RealtimeLabel
    public var arrival: RealtimeLabel
    public var plannedDeparture: Date?
    public var plannedArrival: Date?
    public var durationMinutes: Int
    /// „2 h 16 min“, „41 min“.
    public var durationText: String
    public var changes: Int
    /// „direkt“ / „1 Umstieg“ / „2 Umstiege“.
    public var changesText: String
    /// Departure platform of the first ride leg.
    public var departurePlatform: PlatformLabel?
    public var bar: [JourneyBarSegment]
    public var transfers: [TransferInfo]
    /// „ab Gl. 3 · 1 Umstieg · Langen am Arlberg“, with via stops „ab Gl. 2 · 1 Umstieg · über Feldkirch“.
    public var metaLine: String
    public var topNotice: Notice?
    /// Card notices (crowd, warning, critical); info remarks are shown in the detail only.
    public var notices: [Notice]
    public var isPast: Bool
    public var isCancelled: Bool
    public var tags: Set<Tag>
    /// Display names of the requested via stops this connection passes, in travel order (owner request: „Über“).
    public var viaNames: [String]
    /// „über Feldkirch“ / „über Feldkirch und Bludenz“; nil without via stops.
    public var viaText: String?
    /// Display names of the stations where the traveller changes (origins of the 2nd, 3rd … ride leg).
    public var changeStations: [String]
    /// „RJX 19960 · Bus 750“.
    public var lineSummary: String

    public init(id: String, departure: RealtimeLabel, arrival: RealtimeLabel, plannedDeparture: Date?, plannedArrival: Date?,
                durationMinutes: Int, durationText: String, changes: Int, changesText: String, departurePlatform: PlatformLabel?,
                bar: [JourneyBarSegment], transfers: [TransferInfo], metaLine: String, topNotice: Notice?, notices: [Notice],
                isPast: Bool, isCancelled: Bool, tags: Set<Tag> = [], viaNames: [String] = [], viaText: String? = nil,
                changeStations: [String] = [], lineSummary: String = "") {
        self.id = id
        self.departure = departure
        self.arrival = arrival
        self.plannedDeparture = plannedDeparture
        self.plannedArrival = plannedArrival
        self.durationMinutes = durationMinutes
        self.durationText = durationText
        self.changes = changes
        self.changesText = changesText
        self.departurePlatform = departurePlatform
        self.bar = bar
        self.transfers = transfers
        self.metaLine = metaLine
        self.topNotice = topNotice
        self.notices = notices
        self.isPast = isPast
        self.isCancelled = isCancelled
        self.tags = tags
        self.viaNames = viaNames
        self.viaText = viaText
        self.changeStations = changeStations
        self.lineSummary = lineSummary
    }
}

public enum JourneyPresentation {
    // MARK: Summaries

    /// Cards for a result list; also assigns the tags (SPEC §C3.4).
    public static func summaries(_ journeys: [Journey], now: Date) -> [ConnectionSummary] {
        summaries(journeys, now: now, via: [])
    }

    /// Same, for a search with via stops: each card names the via stops it passes („über Feldkirch“).
    public static func summaries(_ journeys: [Journey], now: Date, via: [ViaStop]) -> [ConnectionSummary] {
        var cards = journeys.map { summary($0, now: now, via: via) }
        assignTags(&cards)
        return cards
    }

    /// One card without tags (tags compare a whole result list).
    public static func summary(_ journey: Journey, now: Date, via: [ViaStop] = []) -> ConnectionSummary {
        let rides = journey.rideLegs
        let departure = journey.departure ?? StopEvent()
        let arrival = journey.arrival ?? StopEvent()
        let minutes = durationMinutes(journey)
        let platform = rides.first.flatMap { platformLabel($0.departure, mode: $0.line?.mode) }
        let changeStations = rides.dropFirst().map { DisplayNames.name($0.origin.name) }
        let viaNames = via.prefix(JourneyQuery.maxViaStops).filter { journey.passes($0.location) }.map { DisplayNames.name($0.location.name) }
        let viaText = Self.viaText(Array(viaNames))
        var meta: [String] = []
        if let platform { meta.append("ab \(platform.text)") }
        meta.append(changesText(journey.changes))
        if let first = changeStations.first, !viaNames.contains(first) { meta.append(first) }
        if let viaText { meta.append(viaText) }
        let cardNotices = Self.notices(journey.remarks + rides.flatMap(\.remarks)).filter { $0.severity != .info }
        return ConnectionSummary(
            id: journey.id,
            departure: RealtimePresentation.label(departure), arrival: RealtimePresentation.label(arrival),
            plannedDeparture: departure.planned, plannedArrival: arrival.planned,
            durationMinutes: minutes, durationText: durationText(minutes: minutes),
            changes: journey.changes, changesText: changesText(journey.changes),
            departurePlatform: platform, bar: bar(journey), transfers: transfers(journey),
            metaLine: meta.joined(separator: " · "), topNotice: topNotice(cardNotices), notices: cardNotices,
            isPast: departure.effective.map { $0 < now } ?? false, isCancelled: isCancelled(journey),
            viaNames: Array(viaNames), viaText: viaText, changeStations: Array(changeStations),
            lineSummary: LinePresentation.lineSummary(rides.compactMap(\.line)))
    }

    /// `fastest`: the first non-past, non-cancelled card with the minimum duration. `fewestChanges`: when the change
    /// counts differ, the first such card with the minimum changes that is not already the fastest (reference
    /// `trips()`; `vm_trips_st_anton_innsbruck.json`).
    static func assignTags(_ cards: inout [ConnectionSummary]) {
        let eligible = cards.indices.filter { !cards[$0].isPast && !cards[$0].isCancelled }
        guard let best = eligible.map({ cards[$0].durationMinutes }).min() else { return }
        let fastest = eligible.first { cards[$0].durationMinutes == best }
        if let fastest { cards[fastest].tags.insert(.fastest) }
        let changes = eligible.map { cards[$0].changes }
        guard let fewest = changes.min(), let most = changes.max(), fewest < most else { return }
        if let i = eligible.first(where: { cards[$0].changes == fewest && $0 != fastest }) { cards[i].tags.insert(.fewestChanges) }
    }

    static func durationMinutes(_ journey: Journey) -> Int {
        if let s = journey.durationSeconds { return s / 60 }
        guard let a = journey.departure?.planned ?? journey.departure?.effective,
              let b = journey.arrival?.planned ?? journey.arrival?.effective else { return 0 }
        return max(0, Int(b.timeIntervalSince(a) / 60))
    }

    static func isCancelled(_ journey: Journey) -> Bool {
        journey.legs.contains { $0.kind == .ride && ($0.isCancelled || $0.departure.isCancelled || $0.arrival.isCancelled) }
    }

    /// „2 h 16 min“, „41 min“, „3 h“.
    public static func durationText(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// „direkt“ / „1 Umstieg“ / „2 Umstiege“.
    public static func changesText(_ changes: Int) -> String {
        switch changes {
        case ...0: return "direkt"
        case 1: return "1 Umstieg"
        default: return "\(changes) Umstiege"
        }
    }

    /// „über Feldkirch“, „über Feldkirch und Bludenz“; nil for none.
    public static func viaText(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        if names.count == 1 { return "über \(names[0])" }
        return "über \(names.dropLast().joined(separator: ", ")) und \(names[names.count - 1])"
    }

    // MARK: Bar

    /// Ride, walk and wait segments in travel order; minutes from effective (realtime) times; fractions sum to 1.
    /// A wait is the gap between two segments; walks and waits of 0 minutes are left out.
    public static func bar(_ journey: Journey) -> [JourneyBarSegment] {
        var segments: [JourneyBarSegment] = []
        var previousEnd = journey.departure?.planned ?? journey.departure?.effective
        for leg in journey.legs {
            let start = leg.departure.effective, end = leg.arrival.effective
            if let previousEnd, let start, start > previousEnd, !segments.isEmpty {
                let wait = minutesBetween(previousEnd, start)
                if wait > 0 { segments.append(JourneyBarSegment(kind: .wait, minutes: wait, fraction: 0)) }
            }
            switch leg.kind {
            case .ride:
                let m = start.flatMap { s in end.map { minutesBetween(s, $0) } } ?? 0
                let plate = leg.line.map(LinePresentation.plate)?.nilIfEmpty
                segments.append(JourneyBarSegment(kind: .ride, mode: leg.line?.mode ?? .other, plate: plate, minutes: max(0, m), fraction: 0))
            case .walk, .transfer:
                let m = walkMinutes(leg)
                if m > 0 { segments.append(JourneyBarSegment(kind: .walk, minutes: m, fraction: 0)) }
            }
            previousEnd = end ?? previousEnd
        }
        let total = segments.reduce(0) { $0 + $1.minutes }
        for i in segments.indices {
            segments[i].fraction = total > 0 ? Double(segments[i].minutes) / Double(total) : 1 / Double(segments.count)
        }
        return segments
    }

    /// Walk minutes of a non-ride leg: effective times, else `walkDurationSeconds` of a footpath. A change inside a
    /// station (`.transfer`) has no walk of its own: its `walkDurationSeconds` is the whole change window (`chg.durS`).
    static func walkMinutes(_ leg: Leg) -> Int {
        if let s = leg.departure.effective, let e = leg.arrival.effective { return max(0, minutesBetween(s, e)) }
        guard leg.kind == .walk else { return 0 }
        return leg.walkDurationSeconds.map { Int((Double($0) / 60).rounded(.toNearestOrEven)) } ?? 0
    }

    /// Rounded minutes (Python `round`, as the reference).
    static func minutesBetween(_ a: Date, _ b: Date) -> Int {
        Int((b.timeIntervalSince(a) / 60).rounded(.toNearestOrEven))
    }

    // MARK: Transfers

    /// One entry per change between ride legs: buffer = next departure − arrival − walk (realtime where known).
    /// ≥ 5 min `.ok` („38 min Umstiegszeit“, buffer + walk), 2…4 `.tight` („Knapp: 3 min zum Umsteigen“),
    /// < 2 `.atRisk` („Anschluss gefährdet“).
    public static func transfers(_ journey: Journey) -> [TransferInfo] {
        let rideIndices = journey.legs.indices.filter { journey.legs[$0].kind == .ride }
        var out: [TransferInfo] = []
        for (a, b) in zip(rideIndices, rideIndices.dropFirst()) {
            if let t = transfer(journey, from: a, to: b) { out.append(t) }
        }
        return out
    }

    /// Transfer between ride legs `a` and `b` (indices into `journey.legs`).
    static func transfer(_ journey: Journey, from a: Int, to b: Int) -> TransferInfo? {
        let prev = journey.legs[a], next = journey.legs[b]
        guard let arrival = prev.arrival.effective, let departure = next.departure.effective else { return nil }
        let walk = journey.legs[(a + 1)..<b].filter { $0.kind != .ride }.reduce(0) { $0 + walkMinutes($1) }
        let buffer = minutesBetween(arrival, departure) - walk
        let risk: TransferRisk = buffer >= 5 ? .ok : (buffer >= 2 ? .tight : .atRisk)
        let text: String
        switch risk {
        case .ok: text = "\(buffer + walk) min Umstiegszeit"
        case .tight: text = "Knapp: \(buffer) min zum Umsteigen"
        case .atRisk: text = "Anschluss gefährdet"
        }
        return TransferInfo(stationName: DisplayNames.name(prev.destination.name), walkMinutes: walk, bufferMinutes: buffer,
                            risk: risk, text: text)
    }

    // MARK: Notices

    static let crowdWords = ["Auslastung", "Starker Reisetag", "Sitzplatzreservierung"]

    /// Remarks → notices, deduplicated by id. Severity: `crowd` (Auslastung, Starker Reisetag, Sitzplatzreservierung)
    /// → `critical` (disruption priority ≤ 50, „Schienenersatzverkehr“, „fällt aus“) → `warning` (other disruptions)
    /// → `info` (attributes, info and the remaining remarks; detail only).
    public static func notices(_ remarks: [Remark]) -> [Notice] {
        var seen = Set<String>()
        var out: [Notice] = []
        for r in remarks {
            let n = notice(r)
            if seen.insert(n.id).inserted { out.append(n) }
        }
        return out
    }

    static func notice(_ r: Remark) -> Notice {
        let title = r.title?.nilIfEmpty ?? r.text
        let text = r.title?.nilIfEmpty == nil || r.text == title ? nil : r.text.nilIfEmpty
        let id = r.id?.nilIfEmpty ?? "\(r.kind.rawValue):\(r.code ?? ""):\(fnv1a(r.text))"
        return Notice(id: id, severity: severity(r), title: title, text: text, priority: r.priority)
    }

    static func severity(_ r: Remark) -> NoticeSeverity {
        if r.kind == .attribute || r.kind == .info { return .info }
        let hay = (r.title ?? "") + " " + r.text
        if crowdWords.contains(where: { hay.contains($0) }) { return .crowd }
        let lower = hay.lowercased()
        if (r.kind == .disruption && (r.priority ?? Int.max) <= 50) || lower.contains("schienenersatzverkehr") || lower.contains("fällt aus") {
            return .critical
        }
        return r.kind == .disruption ? .warning : .info
    }

    /// Highest severity, then the lowest priority.
    public static func topNotice(_ notices: [Notice]) -> Notice? {
        notices.enumerated().min { a, b in
            if a.element.severity != b.element.severity { return a.element.severity > b.element.severity }
            let pa = a.element.priority ?? Int.max, pb = b.element.priority ?? Int.max
            return pa != pb ? pa < pb : a.offset < b.offset
        }?.element
    }

    /// Stable id for remarks without a HIM id (dismissal keys survive app launches; `hashValue` would not).
    static func fnv1a(_ s: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        return String(h, radix: 16)
    }

    // MARK: Attributes

    /// Remark code → SF Symbol of a detail chip, in priority order (first ones win when capped).
    static let attributeSymbols: [(codes: Set<String>, symbol: String)] = [
        (["WV"], "wifi"), (["BR"], "fork.knife"), (["HD"], "moon"), (["KN"], "figure.2.and.child.holdinghands"),
        (["RO", "EF", "OC"], "figure.roll"), (["FK", "FR"], "bicycle"), (["UA"], "briefcase"),
    ]

    /// Detail chips (SF Symbols) from attribute remark codes: at most `limit` (6), chosen by the table order
    /// (WLAN, Bordrestaurant, Ruhezone, Familienzone, Rollstuhl, Fahrrad, Businessabteil) and listed in the order of
    /// `vm_trips_innsbruck_lech.json` (alphabetical by symbol). `limit: nil` returns all.
    public static func attributes(_ remarks: [Remark], limit: Int? = 6) -> [String] {
        let codes = Set(remarks.filter { $0.kind == .attribute }.compactMap(\.code))
        var chosen = attributeSymbols.filter { !$0.codes.isDisjoint(with: codes) }.map(\.symbol)
        if let limit { chosen = Array(chosen.prefix(max(0, limit))) }
        return chosen.sorted()
    }

    // MARK: Platforms

    /// „Gl.“ for tracks (HAFAS `PL`), „Steig“ for bays (`ST`); legacy string platforms count as tracks for rail modes.
    /// nil when the event has no platform.
    public static func platformLabel(_ event: StopEvent, mode: TransportMode? = nil) -> PlatformLabel? {
        let planned = event.plannedPlatform?.text.nilIfEmpty, realtime = event.realtimePlatform?.text.nilIfEmpty
        guard let display = realtime ?? planned else { return nil }
        let kind = (event.realtimePlatform ?? event.plannedPlatform)?.kind ?? .unknown
        let isTrack: Bool
        switch kind {
        case .track: isTrack = true
        case .stand: isTrack = false
        case .unknown: isTrack = [TransportMode.train, .sBahn, .metro].contains(mode ?? .other)
        }
        let changed = event.platformChangeFlag || (planned != nil && realtime != nil && planned != realtime)
        return PlatformLabel(label: isTrack ? "Gl." : "Steig", planned: planned, realtime: realtime, changed: changed, display: display)
    }

    // MARK: VoiceOver

    /// German VoiceOver label of a card, e.g. „Abfahrt 11:16, pünktlich, Ankunft 13:32, 2 Stunden 16 Minuten,
    /// 1 Umstieg in Langen am Arlberg, ab Gleis 3, RJX 19960, Bus 750, € 29,70, Schnellste Verbindung,
    /// Hinweis: Andere Zuggarnitur …“. Via stops are read as „über Feldkirch“.
    public static func accessibilityLabel(_ s: ConnectionSummary, priceText: String?) -> String {
        var parts: [String] = []
        if s.isCancelled { parts.append("Fällt aus") }
        if s.isPast { parts.append("Bereits abgefahren") }
        parts.append(spokenEvent("Abfahrt", planned: s.plannedDeparture, label: s.departure))
        parts.append(spokenEvent("Ankunft", planned: s.plannedArrival, label: s.arrival))
        parts.append(spokenDuration(s.durationMinutes))
        if s.changes <= 0 {
            parts.append("direkt")
        } else if s.changes == 1, let at = s.changeStations.first {
            parts.append("1 Umstieg in \(at)")
        } else {
            parts.append(s.changesText)
        }
        if let p = s.departurePlatform { parts.append("ab \(p.spoken)\(p.changed ? ", Gleiswechsel" : "")") }
        if let via = s.viaText { parts.append(via) }
        if !s.lineSummary.isEmpty { parts.append(s.lineSummary.replacingOccurrences(of: " · ", with: ", ")) }
        if let priceText = priceText?.nilIfEmpty { parts.append(priceText) }
        if s.tags.contains(.fastest) { parts.append("Schnellste Verbindung") }
        if s.tags.contains(.fewestChanges) { parts.append("Wenigste Umstiege") }
        if let n = s.topNotice { parts.append("Hinweis: \(n.title)") }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func spokenEvent(_ prefix: String, planned: Date?, label: RealtimeLabel) -> String {
        var s = prefix
        if let planned { s += " \(RealtimePresentation.time(planned))" }
        let realtime = planned.flatMap { p in label.delayMinutes.map { p.addingTimeInterval(Double($0) * 60) } }
        if let spoken = RealtimePresentation.spoken(label, realtime: realtime) { s += ", \(spoken)" }
        return s
    }

    /// „2 Stunden 16 Minuten“, „1 Stunde“, „41 Minuten“.
    static func spokenDuration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        let hours = h == 1 ? "1 Stunde" : "\(h) Stunden"
        if h == 0 { return RealtimePresentation.minutes(m) }
        return m == 0 ? hours : "\(hours) \(RealtimePresentation.minutes(m))"
    }
}

// MARK: - Departure / arrival boards

/// One row of a live departure or arrival board.
public struct BoardRow: Sendable, Hashable, Identifiable {
    public var id: String
    /// Planned time „11:22“.
    public var time: String
    public var realtime: RealtimeLabel
    /// Plate text (`LinePresentation.plate`), glyph and family for styling.
    public var plate: String
    public var plateGlyph: PlateGlyph?
    public var lineKind: LineKind
    /// „Bus F“, „S 4“, „RJ 83“.
    public var lineTitle: String
    public var mode: TransportMode
    /// Final destination (departures) or origin of the run (arrivals, „von …“), as a display name.
    public var destination: DisplayName
    public var platform: PlatformLabel?
    /// Card notices (crowd, warning, critical).
    public var notices: [Notice]
    public var isCancelled: Bool

    public init(id: String, time: String, realtime: RealtimeLabel, plate: String, plateGlyph: PlateGlyph?, lineKind: LineKind,
                lineTitle: String, mode: TransportMode, destination: DisplayName, platform: PlatformLabel?, notices: [Notice],
                isCancelled: Bool) {
        self.id = id
        self.time = time
        self.realtime = realtime
        self.plate = plate
        self.plateGlyph = plateGlyph
        self.lineKind = lineKind
        self.lineTitle = lineTitle
        self.mode = mode
        self.destination = destination
        self.platform = platform
        self.notices = notices
        self.isCancelled = isCancelled
    }
}

public enum BoardPresentation {
    /// Rows in board order (`Board.entries` is already sorted by effective time).
    public static func rows(_ board: Board) -> [BoardRow] {
        board.entries.map { row($0, kind: board.kind) }
    }

    /// `destination` is the run's final destination on a departure board and the run's origin on an arrival board
    /// (HAFAS `dirTxt` is the final destination on both, SPEC §A3.4 – an arrival board must not show it).
    public static func row(_ entry: BoardEntry, kind boardKind: BoardKind = .departures) -> BoardRow {
        let plate: LinePlateText.Plate = entry.line.map { LinePresentation.plate($0, size: .s) } ?? (text: "", glyph: nil)
        let kind = entry.line.map(LinePresentation.kind) ?? .sonst
        let destinationRaw: String
        switch boardKind {
        case .departures: destinationRaw = entry.direction ?? entry.terminusOrOrigin?.name ?? ""
        case .arrivals: destinationRaw = entry.terminusOrOrigin?.name ?? entry.direction ?? ""
        }
        return BoardRow(id: entry.id, time: entry.event.planned.map(RealtimePresentation.time) ?? "",
                        realtime: RealtimePresentation.label(entry.event), plate: plate.text, plateGlyph: plate.glyph, lineKind: kind,
                        lineTitle: entry.line.map(LinePresentation.title) ?? "", mode: entry.line?.mode ?? .other,
                        destination: DisplayNames.make(destinationRaw),
                        platform: JourneyPresentation.platformLabel(entry.event, mode: entry.line?.mode),
                        notices: JourneyPresentation.notices(entry.remarks).filter { $0.severity != .info },
                        isCancelled: entry.event.isCancelled)
    }
}
