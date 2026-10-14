import Foundation
import KlimaCore

/// Reads and writes the widget cache in the App Group (`WidgetCacheKey`, docs/WIDGETS.md). The app is the only writer of
/// the live caches and of the consent mirror; the widgets only read them. The control intents write the two live-follow
/// keys. Every access is guarded: an unavailable App Group reads as "no cache", never as a crash.
enum WidgetCache {
    static var store: UserDefaults { AppGroup.defaults }

    // MARK: Consent

    static var consent: WidgetConsent {
        WidgetConsent(rawValue: store.string(forKey: WidgetCacheKey.consent) ?? "") ?? .undecided
    }

    static func setConsent(_ value: WidgetConsent) {
        store.set(value.rawValue, forKey: WidgetCacheKey.consent)
    }

    /// Live data may be shown only while the user has granted it; the caches are kept empty otherwise.
    static var isLiveAllowed: Bool { consent == .granted }

    // MARK: Caches

    static var connections: WidgetConnectionCache? { load(WidgetConnectionCache.self, key: WidgetCacheKey.connections) }
    static var departures: WidgetDepartureCache? { load(WidgetDepartureCache.self, key: WidgetCacheKey.departures) }
    static var disruptions: WidgetDisruptionCache? { load(WidgetDisruptionCache.self, key: WidgetCacheKey.disruptions) }
    static var stations: WidgetStationList? { load(WidgetStationList.self, key: WidgetCacheKey.stations) }

    /// Writes `value` (or removes the key for nil) only when the stored value differs. Returns true when the store changed,
    /// so the caller reloads the matching widget timelines only then.
    @discardableResult
    static func write<T: Codable & Equatable>(_ value: T?, key: String) -> Bool {
        let current = load(T.self, key: key)
        guard current != value else { return false }
        guard let value else {
            store.removeObject(forKey: key)
            return true
        }
        guard let data = try? JSONEncoder().encode(value) else { return false }
        store.set(data, forKey: key)
        return true
    }

    /// Removes every live cache (consent withdrawn, "Live-Cache leeren").
    @discardableResult
    static func clearLive() -> Bool {
        let a = write(WidgetConnectionCache?.none, key: WidgetCacheKey.connections)
        let b = write(WidgetDepartureCache?.none, key: WidgetCacheKey.departures)
        let c = write(WidgetDisruptionCache?.none, key: WidgetCacheKey.disruptions)
        return a || b || c
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Live follow (Live-verfolgen control)

    /// Mirror of the followed train: the control shows it on while the app follows a train.
    static var liveFollowActive: Bool { store.bool(forKey: WidgetCacheKey.liveFollowActive) }

    static func setLiveFollowActive(_ on: Bool) {
        store.set(on, forKey: WidgetCacheKey.liveFollowActive)
    }

    /// The control's request for the app: `true` starts following, `false` stops. The app consumes it on launch or when
    /// it becomes active.
    static func requestLiveFollow(_ on: Bool) {
        store.set(on, forKey: WidgetCacheKey.liveFollowRequest)
    }

    /// Takes the pending request (app side), clearing it.
    static func takeLiveFollowRequest() -> Bool? {
        guard store.object(forKey: WidgetCacheKey.liveFollowRequest) != nil else { return nil }
        let value = store.bool(forKey: WidgetCacheKey.liveFollowRequest)
        store.removeObject(forKey: WidgetCacheKey.liveFollowRequest)
        return value
    }
}
