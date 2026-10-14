import Foundation

// Zugsuche ("Züge suchen"): find the runs of one train by its name or number, e.g. "RJX 66", "RJX66" or "66" (SPEC
// docs/OEBB_LIVE.md §R9). Pure values and pure parsing. The network call is `TrainSearchService`, which is separate from
// `TimetableService` so that existing fakes and demo services keep compiling.

// MARK: - Name

/// A train name as the user types it: a category (letters, optional) and a number. "RJX 66", "rjx66", "RJX-66" and "66"
/// all parse. Words, stop names and mixed text ("Wien Hbf") do not.
public struct TrainName: Sendable, Hashable {
    /// Upper-case category ("RJX", "REX", "S"). nil when only a number was typed.
    public var category: String?
    /// The number as typed, digits only ("66", "1830").
    public var number: String

    public init?(_ raw: String) {
        // Spaces, hyphens and dots are separators; everything else must be A–Z followed by digits.
        let folded = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "." }
        let letters = folded.prefix { $0 >= "A" && $0 <= "Z" }
        let digits = folded.dropFirst(letters.count)
        guard !digits.isEmpty, digits.count <= 5, letters.count <= 5,
              digits.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        category = letters.isEmpty ? nil : String(letters)
        number = String(digits)
    }

    /// The HAFAS `input`: "RJX 66", or "66" without a category.
    public var hafasInput: String { category.map { "\($0) \(number)" } ?? number }

    /// Name shown to the user.
    public var display: String { hafasInput }

    /// Whether a line is this train: the number is one of the name tokens ("RJX 66") or the line number, and the category
    /// matches when one was typed (same rule as the radar, `RadarLine.category(of:)`). `Line.trainNumber` is not used: it
    /// carries HAFAS' internal product number, not the train number.
    public func matches(_ line: Line?) -> Bool {
        guard let line else { return false }
        if let category, RadarLine.category(of: line) != category { return false }
        if line.lineNumber == number { return true }
        return line.name.split(separator: " ").contains { String($0) == number }
    }
}

// MARK: - Query

public struct TrainSearchQuery: Sendable, Hashable {
    /// The text sent as HAFAS `input` ("RJX 66"). Built from a `TrainName` or passed verbatim (live checks).
    public var input: String
    /// Product filter. The default is rail (ÖBB and the rail operators), which is what Zugsuche is about.
    public var products: ProductMask
    /// HAFAS `onlyCR`: only trains running now. Off: the run for the number, today or the next one.
    public var onlyRunning: Bool
    /// Optional day and time (Vienna). nil sends neither `date` nor `time`.
    public var date: Date?

    public init(input: String, products: ProductMask = .rail, onlyRunning: Bool = false, date: Date? = nil) {
        self.input = input
        self.products = products
        self.onlyRunning = onlyRunning
        self.date = date
    }

    public init(name: TrainName, products: ProductMask = .rail, onlyRunning: Bool = false, date: Date? = nil) {
        self.init(input: name.hafasInput, products: products, onlyRunning: onlyRunning, date: date)
    }
}

// MARK: - Run actions

public extension TrainRun {
    /// "Live verfolgen" for this run: boarding at the first stop, alighting at the last. nil when the run has no stop list.
    var followTarget: LiveFollowTarget? {
        guard let origin, let destination else { return nil }
        return LiveFollowTarget(tripID: tripID, lineName: line.map { LinePresentation.title($0) } ?? "Zug",
                                boardingStop: origin.location, alightStop: destination.location,
                                plannedDeparture: origin.departure?.planned, plannedArrival: destination.arrival?.planned)
    }

    /// Whether the run is on the road today (Vienna): its departure or its arrival falls on the day of `now`. Following and
    /// the map only apply to such a run; a run in the timetable period is only a schedule.
    func isActive(on now: Date) -> Bool {
        [origin?.departure?.planned, destination?.arrival?.planned].compactMap { $0 }.contains { Calendar.vienna.isDate($0, inSameDayAs: now) }
    }
}

// MARK: - Result

/// One run of a train (one trip id, one day). `origin` and `destination` are the first and last stop of the run; they are nil
/// when the server sent no stop list for the run.
public struct TrainRun: Sendable, Hashable, Identifiable {
    public var tripID: String
    public var line: Line?
    /// Final destination of the run (`dirTxt`).
    public var direction: String?
    public var origin: Stopover?
    public var destination: Stopover?
    public var isCancelled: Bool

    public init(tripID: String, line: Line? = nil, direction: String? = nil, origin: Stopover? = nil, destination: Stopover? = nil,
                isCancelled: Bool = false) {
        self.tripID = tripID
        self.line = line
        self.direction = direction
        self.origin = origin
        self.destination = destination
        self.isCancelled = isCancelled
    }

    public var id: String { tripID }

    /// Planned day of the run: the first departure, else the last arrival.
    public var plannedDate: Date? { origin?.departure?.planned ?? destination?.arrival?.planned }

    /// Delay in seconds, shown on the run: the arrival at the destination when known (the forecast for the end of the run),
    /// else the departure at the origin. nil without realtime.
    public var delaySeconds: Int? { destination?.arrival?.delaySeconds ?? origin?.departure?.delaySeconds }

    /// Whether the operator delivers realtime for this run.
    public var hasRealtime: Bool { (origin?.departure?.hasRealtime ?? false) || (destination?.arrival?.hasRealtime ?? false) }
}

public struct TrainSearchResult: Sendable, Hashable {
    /// Where the runs come from. `journeyMatch` is the ÖBB name search; `stationBoards` is the honest fallback that searches
    /// today's departures of the big stations (the UI labels it).
    public enum Source: String, Sendable, Hashable { case journeyMatch, stationBoards }

    public var source: Source
    public var runs: [TrainRun]
    /// `planrtTS` – when the realtime data behind the runs was last updated.
    public var realtimeUpdatedAt: Date?

    public init(source: Source = .journeyMatch, runs: [TrainRun] = [], realtimeUpdatedAt: Date? = nil) {
        self.source = source
        self.runs = runs
        self.realtimeUpdatedAt = realtimeUpdatedAt
    }

    /// No run with that name in the timetable period: an empty result, never an error.
    public static let empty = TrainSearchResult()

    /// The runs of exactly this train, earliest planned date first (runs without a planned date last). The server also
    /// returns name-prefix matches ("RJX 660" for "RJX 66"); those are left out. Runs cover the whole timetable period,
    /// one per operating day pattern, so the list is not limited to today.
    public func runs(for name: TrainName) -> [TrainRun] {
        runs.filter { name.matches($0.line) }.sorted { a, b in
            switch (a.plannedDate, b.plannedDate) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.tripID < b.tripID
            }
        }
    }
}

// MARK: - Service

/// Zugsuche provider. `HafasClient` is the production implementation; demo mode uses an in-memory one.
public protocol TrainSearchService: Sendable {
    func trainRuns(_ query: TrainSearchQuery) async throws -> TrainSearchResult
}

// MARK: - Suggestions

/// Suggestions under the search field, from the typed text only (and the recent searches the app passes in). Nothing is
/// fetched to make them.
public enum TrainSearchSuggestions {
    /// Categories that the search offers for a typed number or prefix.
    public static let categories = ["RJX", "RJ", "EC", "IC", "EN", "NJ", "REX", "R", "CJX", "S"]

    public static func make(for text: String, recent: [String], limit: Int = 8) -> [String] {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !typed.isEmpty else { return Array(recent.prefix(limit)) }
        var result: [String] = []
        func add(_ value: String) {
            guard !result.contains(value), result.count < limit else { return }
            result.append(value)
        }
        if let name = TrainName(typed), name.category != nil {
            // "RJX 66": the full name first, then recent searches that start with the same text.
            add(name.display)
            for r in recent where r.uppercased().hasPrefix(typed) { add(r) }
        } else if let name = TrainName(typed) {
            // Number only ("66"): the number with each category, then recent names.
            for c in categories { add("\(c) \(name.number)") }
            for r in recent where r.uppercased().hasPrefix(typed) { add(r) }
        } else if typed.allSatisfy({ $0 >= "A" && $0 <= "Z" }) {
            // Letters only ("RJ", "wi"): categories that start with the letters, then recent searches.
            for c in categories where c.hasPrefix(typed) { add(c) }
            for r in recent where r.uppercased().hasPrefix(typed) { add(r) }
        } else {
            // A prefix of a number with a category ("RJX 6"): recent searches only.
            for r in recent where r.uppercased().hasPrefix(typed) { add(r) }
        }
        return result
    }
}
