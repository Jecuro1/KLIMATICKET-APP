import Foundation
import UserNotifications
import KlimaCore

// Live verfolgen: local notifications (docs/OEBB_LIVE.md §R8). Copy is German, Du-Form. A notice is only ever posted when
// the user switched Live-Mitteilungen on (`FollowNoticeSettings.isEnabled`, checked by the tracker); the system permission
// is asked for at that moment and never earlier. Nothing is pushed from a server.

enum LiveFollowNotifications {
    /// Asks for the system permission. Called only after the user switched Live-Mitteilungen on.
    static func requestAuthorization() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    static func post(_ notice: LiveFollowNotice, lineName: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title(notice)
        content.body = body(notice, lineName: lineName)
        content.sound = .default
        content.categoryIdentifier = NotificationCategories.followNotice
        content.threadIdentifier = "live.follow.\(id)"
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
        case .departed: "Abgefahren"
        case .arrivingSoon(_, let minutes): "Ankunft in etwa \(minutes) Min"
        case .tightTransfer(_, let buffer): buffer < 0 ? "Anschluss wahrscheinlich verpasst" : "Anschluss knapp"
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
        case .departed(let stop): "\(lineName) ab \(stop)"
        case .arrivingSoon(let stop, _): "\(lineName) in \(stop)"
        case .tightTransfer(let station, let buffer):
            buffer < 0
                ? "Dein Anschluss in \(station) geht wahrscheinlich nicht mehr. Schau in die Verbindung."
                : "Noch \(buffer) Min zum Umsteigen in \(station)."
        }
    }
}
