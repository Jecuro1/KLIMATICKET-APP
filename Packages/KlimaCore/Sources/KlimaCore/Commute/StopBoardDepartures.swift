import Foundation

// Haltestellen-Detail „Nächste Abfahrten“ (docs/COMMUTE.md §12): one departure board for a stop, through the same gate as the
// Pendel-Modus. The app hands over `LiveDataService.timetable`, which is nil without consent, with the Fahrplan switched off,
// under the kill switch or offline – then this throws `consentRequired` before anything else happens (not even the station
// lookup). The board request goes through the shared HAFAS client and its `RequestThrottle`.

/// What the section shows: the next departures as board rows (the Fahrplan's Abfahrtstafel look), and the age of the answer.
public struct StopBoardSnapshot: Sendable, Hashable {
    public var rows: [BoardRow]
    /// When the answer arrived (the age line: „Stand 07:31“).
    public var fetchedAt: Date
    /// ÖBB's realtime stamp of the answer; nil = plan only.
    public var realtimeUpdatedAt: Date?
    /// More departures than shown came back („Alle Abfahrten“).
    public var hasMore: Bool

    public init(rows: [BoardRow], fetchedAt: Date, realtimeUpdatedAt: Date?, hasMore: Bool) {
        self.rows = rows
        self.fetchedAt = fetchedAt
        self.realtimeUpdatedAt = realtimeUpdatedAt
        self.hasMore = hasMore
    }

    public var hasRealtime: Bool { realtimeUpdatedAt != nil || rows.contains { $0.realtime.state != .scheduled } }
}

public enum StopBoardDepartures {
    /// Departures shown in the stop detail.
    public static let shown = 8
    /// Minutes the board covers.
    public static let minutes = 90
    /// Entries asked for (a busy hub fills 90 minutes quickly; the rest stays for „Alle Abfahrten“).
    public static let maxResults = 30
    /// The section loads again at most this often while it is on screen.
    public static let minRefreshInterval: TimeInterval = 60

    public static func query(station: Location, at date: Date) -> BoardQuery {
        BoardQuery(station: station, kind: .departures, date: date, durationMinutes: minutes, maxResults: maxResults)
    }

    /// Throws `consentRequired` without touching `resolve` or the timetable when `timetable` is nil.
    public static func load(timetable: (any TimetableService)?, at date: Date,
                            resolve: @Sendable () async throws -> Location) async throws -> StopBoardSnapshot {
        guard let timetable else { throw CommuteLiveError.consentRequired }
        let station = try await resolve()
        let board = try await timetable.board(query(station: station, at: date))
        return snapshot(board, now: date)
    }

    /// The next `shown` departures still ahead: a run stays until a minute after its (realtime) departure, a cancelled one
    /// until its planned time. Board order (already sorted by effective time).
    public static func snapshot(_ board: Board, now: Date) -> StopBoardSnapshot {
        let ahead = board.entries.filter { entry in
            let event = entry.event
            guard let time = event.isCancelled ? event.planned : (event.realtime ?? event.planned) else { return false }
            return time >= now.addingTimeInterval(-60)
        }
        let rows = ahead.prefix(shown).map { BoardPresentation.row($0, kind: .departures) }
        return StopBoardSnapshot(rows: Array(rows), fetchedAt: now, realtimeUpdatedAt: board.realtimeUpdatedAt, hasMore: ahead.count > shown)
    }

    /// „Stand 07:31 · Echtzeit“ · „Stand 07:31 · Fahrplan“.
    public static func dataAge(_ snapshot: StopBoardSnapshot) -> String {
        CommuteStatus.dataAge(fetchedAt: snapshot.fetchedAt, hasRealtime: snapshot.hasRealtime, isOffline: false)
    }

    /// Whether a refresh may run now.
    public static func mayRefresh(lastFetch: Date?, now: Date) -> Bool {
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= minRefreshInterval
    }
}
