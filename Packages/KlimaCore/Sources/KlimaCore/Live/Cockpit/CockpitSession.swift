import Foundation

// Cockpit-Ansicht, part 5: the state of one cockpit (docs/RADAR_COCKPIT.md). A small state machine, pure and with an injected clock:
// which camera mode is on (follow, bird, free), whether the train is live, lost or its run has ended. The app feeds it the answers of the
// refresh loop and the user's touches; the views read `state`.
//
//   waiting ──answer with position──▶ live ──no position for 2 min──▶ lost ──answer with position──▶ live
//   live / lost / waiting ──final stop reached, or the schedule is over by a margin──▶ ended (final)
//   camera: follow ⇄ bird; any user move of the map → free; "Zurück zum Zug" → the mode before free.

public struct CockpitSession: Sendable, Equatable {
    /// Whether the train's position is arriving.
    public enum Link: Sendable, Hashable {
        /// Opened, no answer with the train's position yet.
        case waiting
        case live
        /// No position for `lostAfter` seconds: the marker stays where it was and says so.
        case lost
        /// The run is over: the train reached its last stop, or the schedule ended a while ago.
        case ended
    }

    /// What the screens read: the camera and the link in one word. `ended` and `lost` win over `free` (the banner matters more than how
    /// the camera is held), `free` over `following`.
    public enum State: Sendable, Hashable {
        case waiting, following, free, lost, ended
    }

    /// Why the train is lost: the requests fail, or they answer without the train.
    public enum LostReason: Sendable, Hashable {
        case noAnswers
        case notListed
    }

    public struct Config: Sendable, Equatable {
        /// "Keine Position mehr" after this long without a position (the owner's 2 minutes).
        public var lostAfter: TimeInterval = 120
        /// The run counts as over this long after its last expected arrival, whatever the radar says.
        public var endedMargin: TimeInterval = 300
        /// An answer this recent means the service is reachable (the train is then not listed, rather than the requests failing).
        public var recentAnswer: TimeInterval = 60

        public init() {}
    }

    public let config: Config
    public private(set) var mode: CockpitCameraMode = .follow
    /// The driven mode to go back to from `free`.
    public private(set) var drivenMode: CockpitCameraMode = .follow
    public private(set) var link: Link = .waiting
    public let startedAt: Date
    /// The last answer that carried the train's position.
    public private(set) var lastPositionAt: Date?
    /// The last answer of any kind (the train may not have been in it).
    public private(set) var lastAnswerAt: Date?

    public init(startedAt: Date, mode: CockpitCameraMode = .follow, config: Config = Config()) {
        self.config = config
        self.startedAt = startedAt
        self.mode = mode
        if mode.isDriven { drivenMode = mode }
    }

    public var state: State {
        switch link {
        case .ended: return .ended
        case .lost: return .lost
        case .waiting: return mode == .free ? .free : .waiting
        case .live: return mode == .free ? .free : .following
        }
    }

    /// "Zurück zum Zug" is offered: the camera is the user's, and the train is still somewhere to go back to.
    public var offersReturn: Bool { mode == .free && link != .ended }

    /// Why the train is lost, judged at `now`: answers still come in (not listed) or have stopped (no answers).
    public func lostReason(now: Date) -> LostReason? {
        guard link == .lost else { return nil }
        guard let lastAnswerAt, now.timeIntervalSince(lastAnswerAt) <= config.recentAnswer else { return .noAnswers }
        return .notListed
    }

    // MARK: Camera

    /// The mode switcher. Follow and bird are remembered as the mode to return to.
    public mutating func select(_ newMode: CockpitCameraMode) {
        mode = newMode
        if newMode.isDriven { drivenMode = newMode }
    }

    /// The user moved or zoomed the map: the camera is theirs from now on.
    public mutating func userMovedMap() {
        guard mode != .free else { return }
        drivenMode = mode
        mode = .free
    }

    /// "Zurück zum Zug".
    public mutating func returnToTrain() {
        mode = drivenMode
    }

    // MARK: Link

    /// An answer arrived. `hasPosition`: the train was in it. An answer without the train does not make it live, and it does not end a lost
    /// state; it only shows that the service is reachable.
    public mutating func answer(at now: Date, hasPosition: Bool) {
        guard link != .ended else { return }
        lastAnswerAt = max(lastAnswerAt ?? now, now)
        if hasPosition {
            lastPositionAt = max(lastPositionAt ?? now, now)
            link = .live
        }
    }

    /// The clock moved on. `atLastStop`: the train stands at the last stop of its run. `scheduleEnd`: when it is due there (with its delay).
    public mutating func tick(now: Date, atLastStop: Bool, scheduleEnd: Date?) {
        guard link != .ended else { return }
        if atLastStop {
            link = .ended
            return
        }
        if let scheduleEnd, now >= scheduleEnd.addingTimeInterval(config.endedMargin) {
            link = .ended
            return
        }
        let since = lastPositionAt ?? startedAt
        if now.timeIntervalSince(since) >= config.lostAfter, link != .lost {
            link = .lost
        }
    }
}
