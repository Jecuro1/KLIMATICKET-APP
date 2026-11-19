import Foundation

// MARK: radar2-radarmine – „Wo bleibt mein Bus?“ (docs/RADAR_MINE.md §4): the next departures from one stop with where each vehicle is now. The radar's
// tiles know four stops per vehicle (start, last left, next, destination), so „which bus comes to my stop“ is answered by the stop's departures
// board (StationBoard), whose entries carry the position the Auskunft computed for the running vehicle (`BoardEntry.currentPosition`). When the
// radar holds the same trip id with a newer answer, its marker is the position (and gets the number); otherwise the board's position is drawn as a
// pin of its own. Whether board and radar use the same trip ids is not measured: a vehicle can appear twice, and the footer says so.

/// What the radar holds of one trip: where its marker is and when the answer behind it was asked.
public struct RadarHeldVehicle: Sendable, Hashable {
    public var coordinate: GeoPoint
    public var seenAt: Date

    public init(coordinate: GeoPoint, seenAt: Date) {
        self.coordinate = coordinate
        self.seenAt = seenAt
    }
}

public struct RadarStopArrival: Sendable, Hashable, Identifiable {
    public enum Position: Sendable, Hashable {
        /// Within 100 m of the stop.
        case atStop
        case away(km: Double)
        case unknown
    }

    public enum Source: Sendable, Hashable {
        /// The radar's marker of the same trip (its answer is newer than the board's, or the board has no position).
        case radar
        /// The position in the board's entry.
        case board
        /// Nobody knows where it is.
        case none
    }

    /// The board entry's id.
    public var id: String
    public var tripID: String
    public var line: Line?
    /// The radar mode of the line (nil: „Andere“).
    public var mode: RadarMode?
    /// Plate, title, destination and platform as the Fahrplan's Abfahrtstafel shows them.
    public var row: BoardRow
    public var eta: RadarMineETA?
    public var planned: Date?
    /// „Steig 2“ (bus, tram) or „Gleis 4“ (rail); nil without a platform.
    public var platform: String?
    public var position: Position
    public var source: Source
    /// Where the vehicle is (for the map); nil with `.unknown`.
    public var point: GeoPoint?
    /// When that position was computed: the request time of the board or of the radar's answer.
    public var positionAt: Date?

    public var isCancelled: Bool { eta?.isCancelled ?? row.isCancelled }
}

public enum RadarStopArrivals {
    /// Rows on the page.
    public static let shown = 8
    /// The board covers 30 minutes, at most 12 entries.
    public static let minutes = 30
    public static let maxResults = 12
    /// Züge, S-Bahn, Bus, Bim and U-Bahn (4989) whatever the chips say: with the default chips (Züge, S-Bahn) a bus stop would show nothing, and
    /// „Die Auskunft kennt keine Abfahrt“ would be false.
    public static let products: ProductMask = [.rail, .bus, .tram, .subway]
    /// Closer than this is „an der Haltestelle“.
    public static let atStopKm = 0.1
    /// A position older than this is shown grey with its age.
    public static let staleAfter: TimeInterval = 120
    /// Numbered arrivals on the map.
    public static let mapNumbers = 5

    public static func query(station: Location, at date: Date) -> BoardQuery {
        BoardQuery(station: station, kind: .departures, date: date, durationMinutes: minutes, maxResults: maxResults, products: products)
    }

    /// The first `shown` entries still ahead (the rule of the Pendel's „Nächste Abfahrten“, `StopBoardDepartures.isAhead`), in board order, each
    /// with its position: the radar's newer answer of the same trip id, else the board's own, else unknown.
    public static func rows(board: Board, fetchedAt: Date, stop: GeoPoint?, radar: [String: RadarHeldVehicle], now: Date) -> [RadarStopArrival] {
        board.entries.filter { StopBoardDepartures.isAhead($0, now: now) }.prefix(shown).map { entry in
            let held = radar[entry.tripID]
            var source = RadarStopArrival.Source.none
            var point: GeoPoint?
            var at: Date?
            if let held, held.seenAt > fetchedAt || entry.currentPosition == nil {
                source = .radar
                point = held.coordinate
                at = held.seenAt
            } else if let pos = entry.currentPosition {
                source = .board
                point = pos
                at = fetchedAt
            }
            let target = entry.stop.coordinate ?? stop
            var position = RadarStopArrival.Position.unknown
            if let point, let target {
                let km = point.distanceKm(to: target)
                if km.isFinite { position = km <= atStopKm + 1e-9 ? .atStop : .away(km: km) }
            }
            if case .unknown = position {
                source = .none
                point = nil
                at = nil
            }
            let row = BoardPresentation.row(entry, kind: .departures)
            return RadarStopArrival(id: entry.id, tripID: entry.tripID, line: entry.line,
                                    mode: entry.line.flatMap { RadarMode.of(productClass: $0.productClass) }, row: row,
                                    eta: RadarMineETA(event: entry.event), planned: entry.event.planned,
                                    platform: row.platform.map(platformText), position: position, source: source, point: point,
                                    positionAt: at)
        }
    }

    /// „Steig 2“, „Gleis 4“.
    static func platformText(_ label: PlatformLabel) -> String {
        "\(label.label == "Gl." ? "Gleis" : label.label) \(label.display)"
    }

    /// The numbers on the map: the first five rows with a position that are not cancelled and whose mode is on the map (a row of a mode whose
    /// chip is off stays in the list without a number). Keyed by the row id.
    public static func numbers(_ rows: [RadarStopArrival], shownModes: Set<RadarMode>) -> [String: Int] {
        var result: [String: Int] = [:]
        for row in rows where row.point != nil && !row.isCancelled {
            if let mode = row.mode, !shownModes.contains(mode) { continue }
            guard result.count < mapNumbers else { break }
            result[row.id] = result.count + 1
        }
        return result
    }

    /// The rows with a position whose mode is off the map (the page says „… stehen in der Liste, aber nicht auf der Karte“).
    public static func hiddenModes(_ rows: [RadarStopArrival], shownModes: Set<RadarMode>) -> Set<RadarMode> {
        Set(rows.filter { $0.point != nil && !$0.isCancelled }.compactMap { row in row.mode.flatMap { shownModes.contains($0) ? nil : $0 } })
    }

    /// The position is older than two minutes.
    public static func isStale(_ positionAt: Date?, now: Date) -> Bool {
        guard let positionAt else { return false }
        return now.timeIntervalSince(positionAt) > staleAfter
    }
}
