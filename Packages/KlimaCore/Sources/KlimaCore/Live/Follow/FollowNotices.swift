import Foundation

// Live verfolgen, notice policy (docs/OEBB_LIVE.md §R8): one switch per notice kind, the delay threshold, quiet hours and
// the dedupe ledger. Pure values; the app decides what to deliver and when. Nothing is sent without the user's switch:
// `FollowNoticeSettings.isEnabled` is off until the user turns it on in Einstellungen › Mitteilungen.

/// A switch in Einstellungen. `delayRecovered` belongs to `.delay`.
public enum FollowNoticeKind: String, CaseIterable, Codable, Sendable, Hashable {
    case delay, platform, cancelled, tightTransfer, arrivingSoon, departed, arrived
}

extension LiveFollowNotice {
    public var kind: FollowNoticeKind {
        switch self {
        case .delay, .delayRecovered: .delay
        case .platform: .platform
        case .cancelled: .cancelled
        case .arrived: .arrived
        case .departed: .departed
        case .arrivingSoon: .arrivingSoon
        case .tightTransfer: .tightTransfer
        }
    }

    /// Stable key for the ledger: the same notice is delivered once per follow.
    public var dedupeKey: String {
        switch self {
        case .delay(let minutes, _): "delay.\(minutes)"
        case .delayRecovered: "delay.recovered"
        case .platform(_, _, let to, let isBoarding): "platform.\(isBoarding ? "boarding" : "alighting").\(to)"
        case .cancelled: "cancelled"
        case .arrived: "arrived"
        case .departed: "departed"
        case .arrivingSoon: "arrivingSoon"
        case .tightTransfer: "tightTransfer"
        }
    }
}

/// Which notices were already delivered for one follow. Kept across app launches and background refreshes, so a
/// refresh that repeats an answer does not notify twice.
public struct FollowNoticeLedger: Codable, Hashable, Sendable {
    public private(set) var keys: Set<String>

    public init(keys: Set<String> = []) { self.keys = keys }

    /// Records `notice`. Returns false when it was delivered before. A recovery clears the delay keys, so the next
    /// crossing of the same delay is news again.
    @discardableResult
    public mutating func claim(_ notice: LiveFollowNotice) -> Bool {
        if case .delayRecovered = notice {
            keys = keys.filter { !$0.hasPrefix("delay.") }
            keys.insert(notice.dedupeKey)
            return true
        }
        return keys.insert(notice.dedupeKey).inserted
    }
}

/// Quiet hours: no notices between `startHour` and `endHour` in the calendar's time. Wraps midnight (22 to 7 by default).
public struct QuietHours: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    /// 0 through 23.
    public var startHour: Int
    /// 0 through 23; the end is exclusive.
    public var endHour: Int

    public static let standard = QuietHours(isEnabled: true, startHour: 22, endHour: 7)

    public init(isEnabled: Bool = true, startHour: Int = 22, endHour: Int = 7) {
        self.isEnabled = isEnabled
        self.startHour = min(max(startHour, 0), 23)
        self.endHour = min(max(endHour, 0), 23)
    }

    /// True when `date` lies inside the quiet window. Equal start and end mean no quiet window.
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, startHour != endHour else { return false }
        let hour = calendar.component(.hour, from: date)
        return startHour < endHour
            ? (hour >= startHour && hour < endHour)
            : (hour >= startHour || hour < endHour)
    }
}

/// The user's choices for live notices. The defaults are the safe ones: nothing is on until the user turns it on.
public struct FollowNoticeSettings: Codable, Hashable, Sendable {
    /// The master switch („Live-Mitteilungen“). Off: no permission prompt, no notification, no Live Activity and no
    /// background refresh for follows.
    public var isEnabled: Bool
    /// Delay from which the user is told (3, 5 or 10 minutes).
    public var delayThresholdMinutes: Int
    /// One switch per notice kind.
    public var kinds: Set<FollowNoticeKind>
    public var quietHours: QuietHours

    public static let delayChoices = [3, 5, 10]

    public init(isEnabled: Bool = false, delayThresholdMinutes: Int = 5, kinds: Set<FollowNoticeKind> = Set(FollowNoticeKind.allCases),
                quietHours: QuietHours = .standard) {
        self.isEnabled = isEnabled
        self.delayThresholdMinutes = FollowNoticeSettings.delayChoices.contains(delayThresholdMinutes) ? delayThresholdMinutes : 5
        self.kinds = kinds
        self.quietHours = quietHours
    }

    public var delayThresholdSeconds: Int { delayThresholdMinutes * 60 }

    /// Whether a notice may be shown now. The caller records it in the ledger either way, so a notice that was held back
    /// by quiet hours is not delivered late.
    public func allows(_ notice: LiveFollowNotice, at now: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, kinds.contains(notice.kind) else { return false }
        return !quietHours.contains(now, calendar: calendar)
    }
}
