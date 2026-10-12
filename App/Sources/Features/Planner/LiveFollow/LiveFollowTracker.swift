import Foundation
import UserNotifications
import KlimaCore

// Live verfolgen (docs/OEBB_LIVE.md §R3): polls one trip while the app is open and reports changes as in-app status
// and local notifications. No background execution: changes are noticed while the app runs (see the report).

/// Owns the one active follow. Polling: every 10 min before a far-off departure, 2 min close to it, 1 min underway.
@MainActor
@Observable
final class LiveFollowTracker {
    static let shared = LiveFollowTracker()

    enum Status: Equatable {
        case following
        /// The last answer failed; the last known state stays on screen.
        case paused(String)
        /// Arrived or cancelled: polling stops, the card stays until dismissed.
        case finished
    }

    private(set) var target: LiveFollowTarget?
    private(set) var snapshot: LiveFollowSnapshot?
    private(set) var status: Status = .following
    private(set) var updatedAt: Date?
    private(set) var lastNotice: LiveFollowNotice?

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var fetch: ((String) async throws -> TripDetails)?

    /// Starts following `target`, replacing any previous follow.
    func start(_ target: LiveFollowTarget, live: LiveDataService) {
        loop?.cancel()
        self.target = target
        snapshot = nil
        lastNotice = nil
        updatedAt = nil
        status = .following
        if live.isDemo {
            fetch = { id in
                guard let trip = DemoFollow.trip(id, now: Date()) else { throw LiveError.noConnection }
                return trip
            }
        } else {
            fetch = { [weak live] id in
                guard let service = live?.timetable else { throw LiveError.disabled(.oebbHafas) }
                return try await service.trip(id, includePolyline: false)
            }
        }
        LiveFollowNotifications.requestAuthorization()
        loop = Task { [weak self] in await self?.run() }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        target = nil
        snapshot = nil
        lastNotice = nil
        fetch = nil
    }

    private func run() async {
        while !Task.isCancelled, target != nil {
            await pollOnce()
            if status == .finished || Task.isCancelled { break }
            try? await Task.sleep(for: pollInterval())
        }
    }

    private func pollOnce() async {
        guard let target, let fetch else { return }
        do {
            let trip = try await fetch(target.tripID)
            let now = Date()
            let next = LiveFollow.snapshot(trip, target: target, now: now)
            for notice in LiveFollow.notices(from: snapshot, to: next) {
                lastNotice = notice
                LiveFollowNotifications.post(notice, lineName: target.lineName, id: target.tripID)
            }
            snapshot = next
            updatedAt = now
            status = (next.phase == .arrived || next.phase == .cancelled) ? .finished : .following
        } catch is CancellationError {
            return
        } catch {
            status = .paused(LiveMessage.text(for: error))
        }
    }

    private func pollInterval() -> Duration {
        if snapshot?.phase == .underway { return .seconds(60) }
        if let departure = target?.plannedDeparture, departure.timeIntervalSinceNow > 30 * 60 { return .seconds(600) }
        return .seconds(120)
    }
}

/// Local notifications for follow changes. Copy is German, Du-Form.
enum LiveFollowNotifications {
    static func requestAuthorization() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    static func post(_ notice: LiveFollowNotice, lineName: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title(notice)
        content.body = body(notice, lineName: lineName)
        content.sound = .default
        let request = UNNotificationRequest(identifier: "livefollow-\(id)-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func title(_ notice: LiveFollowNotice) -> String {
        switch notice {
        case .delay(let minutes, _): "Verspätung +\(minutes) Min"
        case .delayRecovered: "Wieder pünktlich"
        case .platform: "Gleis geändert"
        case .cancelled: "Zug fällt aus"
        case .arrived: "Angekommen"
        }
    }

    static func body(_ notice: LiveFollowNotice, lineName: String) -> String {
        switch notice {
        case .delay(_, let stop): "\(lineName) · \(stop)"
        case .delayRecovered(let stop): "\(lineName) · \(stop)"
        case .platform(let stop, let from, let to, _):
            if let from { "\(stop): Gleis \(from) → \(to)" } else { "\(stop): neues Gleis \(to)" }
        case .cancelled(let stop): "\(lineName) ab \(stop)"
        case .arrived(let stop): "\(lineName) in \(stop)"
        }
    }
}
