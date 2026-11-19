import Foundation

// MARK: radartrail – which trails are drawn and when (docs/RADAR_TRAILS.md §4, §7). The setting „Spuren“ (Aus / Ausgewählte und meine / Alle im
// Ausschnitt) and „Länge“ (5 / 10 / 20 Min) is the only thing this feature stores: per device under `radar.trail.v1`, versioned JSON with tolerant
// decoding, reset in screenshot launches. Never a sample.

public struct RadarTrailSetting: Hashable, Sendable {
    public enum Mode: String, CaseIterable, Sendable, Identifiable {
        case off, mine, all
        public var id: Self { self }
        public var title: String {
            switch self {
            case .off: RadarTrailText.modeOff
            case .mine: RadarTrailText.modeMine
            case .all: RadarTrailText.modeAll
            }
        }
    }

    /// The lengths „Länge“ offers, in minutes.
    public static let lengths = [5, 10, 20]

    public var mode: Mode
    public var minutes: Int

    public init(mode: Mode = .mine, minutes: Int = 10) {
        self.mode = mode
        self.minutes = Self.lengths.contains(minutes) ? minutes : 10
    }

    public static let standard = RadarTrailSetting()
    public static let storageKey = "radar.trail.v1"

    /// How far back a trail reaches.
    public var length: TimeInterval { TimeInterval(minutes) * 60 }
    /// What the recorder keeps: the length plus the delay line's margin.
    public var window: TimeInterval { length + RadarTrailRecorder.sparklineMargin }

    public var storageValue: String {
        let object: [String: Any] = ["version": 1, "mode": mode.rawValue, "minutes": minutes]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Unknown or missing values take their default (Ausgewählte und meine, 10 Min).
    public init(storage: String) {
        self.init()
        guard let data = storage.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        mode = (object["mode"] as? String).flatMap(Mode.init(rawValue:)) ?? .mine
        if let minutes = object["minutes"] as? Int, Self.lengths.contains(minutes) { self.minutes = minutes }
    }
}

public enum RadarTrailPolicy {
    /// „Alle im Ausschnitt“ only this close (latitude span in degrees) …
    public static let allSpanLimit = 0.5
    /// … and with at most this many single markers on the map.
    public static let allSinglesLimit = 60
    /// „Ausgewählte und meine“ draws at most this many trails.
    public static let mineLimit = 12

    /// Why „Alle“ draws only „mine“: the map is taller than `allSpanLimit`, or holds more than `allSinglesLimit` single markers. The note
    /// names the one that holds (a wide map with three trains is not „zu viele Fahrzeuge“).
    public enum Limit: Equatable, Sendable { case tooWide, tooMany }

    public struct Choice: Equatable, Sendable {
        /// The trips whose trail is drawn, in this order (the selected one first).
        public var tripIDs: [String]
        /// „Alle“ was asked for, but the map is too wide or too full: only „mine“ is drawn and the note says why.
        public var limit: Limit?

        public init(tripIDs: [String] = [], limit: Limit? = nil) {
            self.tripIDs = tripIDs
            self.limit = limit
        }
    }

    /// The trails to draw. Only vehicles drawn as single markers count (a trail must end at its marker, and a group has none):
    /// `singles` are their trip ids in map order. „mine“ is the selected vehicle, the followed one and the remembered lines' vehicles.
    public static func trips(mode: RadarTrailSetting.Mode, selected: String?, followed: String?, remembered: [String], singles: [String],
                             span: Double) -> Choice {
        switch mode {
        case .off:
            return Choice()
        case .all where span <= allSpanLimit && singles.count <= allSinglesLimit:
            let first = selected.flatMap { singles.contains($0) ? [$0] : nil } ?? []
            return Choice(tripIDs: first + singles.filter { $0 != selected })
        case .all:
            return Choice(tripIDs: mine(selected: selected, followed: followed, remembered: remembered, singles: singles),
                          limit: span > allSpanLimit ? .tooWide : .tooMany)
        case .mine:
            return Choice(tripIDs: mine(selected: selected, followed: followed, remembered: remembered, singles: singles))
        }
    }

    static func mine(selected: String?, followed: String?, remembered: [String], singles: [String]) -> [String] {
        let present = Set(singles)
        var result: [String] = []
        for id in [selected, followed].compactMap({ $0 }) + remembered where present.contains(id) && !result.contains(id) {
            result.append(id)
            if result.count == mineLimit { break }
        }
        return result
    }

    /// Trails are drawn only with the train layer on and the live data open (offline draws no markers, so a trail would end in nothing),
    /// at „Jetzt“ (away from now the Zeitreise draws its own computed trail) and with the setting on.
    public static func isDrawn(trainsOn: Bool, timeAway: Bool, mode: RadarTrailSetting.Mode) -> Bool {
        trainsOn && !timeAway && mode != .off
    }

    /// The line under the status card (`RadarTrailText`): nothing, the caption with its start, the „zu viele“ note (with the caption's start
    /// when „mine“ is still drawn), or, away from now, that trails exist only at „Jetzt“.
    public enum Note: Equatable, Sendable {
        case none
        case caption(since: Date)
        case limited(Limit, since: Date?)
        case onlyNow
    }

    /// Which note shows. `drawn`: trails on the map now; `heldForReturn`: away from now, whether trails would come back at „Jetzt“ (the
    /// note is no promise for a radar that never drew one). MARK: radar2-review-radartrail – `drawnSince`: the oldest moment the drawn lines
    /// show (`RadarTrailGeometry.oldestMoment`); when given, „seit“ is exactly that. The markers are drawn 20 to 120 s behind the clock and
    /// hold their last answer in Low Power Mode, so „now minus the length“ named a later minute than the lines on the map reach back to.
    public static func note(mode: RadarTrailSetting.Mode, trainsOn: Bool, timeAway: Bool, choice: Choice, drawn: Int, heldForReturn: Bool,
                            firstRecordedAt: Date?, now: Date, length: TimeInterval, drawnSince: Date? = nil) -> Note {
        guard mode != .off, trainsOn else { return .none }
        if timeAway { return heldForReturn ? .onlyNow : .none }
        let since = drawnSince ?? firstRecordedAt.map { RadarTrailText.since(firstRecordedAt: $0, now: now, length: length) }
        if let limit = choice.limit { return .limited(limit, since: drawn > 0 ? since : nil) }
        guard drawn > 0, let since else { return .none }
        return .caption(since: since)
    }

    /// What the radar's access does to the samples: offline keeps them for the return (nothing arrives meanwhile, the missing minutes are a
    /// gap); closed – no consent, „Live-Fahrplan“ off, kill switch, Offline-Modus – clears them.
    public enum AccessEffect: Equatable, Sendable { case keep, clear }

    public static func effect(of access: RadarFeatureGate.Access) -> AccessEffect {
        access == .closed ? .clear : .keep
    }
}
