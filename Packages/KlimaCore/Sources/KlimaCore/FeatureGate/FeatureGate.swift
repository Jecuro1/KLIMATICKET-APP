import Foundation

// MARK: funktionen – the one rule for „is this feature on?“ (docs/FUNCTIONS_HUB.md §3). The hub, the entry points and the deep
// links all ask here: the own switch first, then the Offline-Modus, then what the feature needs. The live-data consent is not part
// of it – it stays exactly as the user set it; a feature that is on but waits for live data says so in its status line.

/// The state of the live layer as the hub shows it (from `LiveDataService`).
public enum FeatureLiveState: String, Equatable, Sendable {
    /// Live data can be asked.
    case ready
    /// The consent card was not answered yet.
    case consentOpen
    /// „Nur Offline-Daten“ was chosen.
    case declined
    /// The ÖBB query is switched off remotely (kill switch).
    case remoteOff
    /// No internet connection.
    case noInternet
}

/// What the gate needs besides the hub's own settings.
public struct FeatureContext: Equatable, Sendable {
    /// The switches that live elsewhere (AppSettings, Look & Feel, the logo store, the detection …). A missing value counts as off.
    public var wrapped: [FeatureID: Bool]
    public var live: FeatureLiveState

    public init(wrapped: [FeatureID: Bool] = [:], live: FeatureLiveState = .ready) {
        self.wrapped = wrapped
        self.live = live
    }
}

/// Why a feature is off.
public enum FeatureOffReason: Equatable, Sendable, Hashable {
    /// Its own switch is off.
    case switchedOff
    /// The Offline-Modus is on.
    case offlineMode
    /// A feature it needs is off.
    case needs(FeatureID)
}

/// A resolved feature: its switch, whether it is on and why not.
public struct FeatureStatus: Equatable, Sendable {
    public let id: FeatureID
    /// The feature's own switch (the toggle in the hub row).
    public let switchIsOn: Bool
    public let offReason: FeatureOffReason?
    /// On, but the live data it uses cannot be asked right now (consent open, declined, remote off, no internet).
    public let waiting: FeatureLiveState?

    public var isOn: Bool { offReason == nil }
}

/// A one-line note of the hub: what is hidden right now and why.
public struct FeatureHiddenNote: Equatable, Sendable, Identifiable {
    public let id: FeatureID
    public let text: String
}

public enum FeatureGate {
    /// The feature's own switch: the hub override or default, or the wrapped value from the context.
    public static func ownSwitch(_ id: FeatureID, settings: FeatureSettings, context: FeatureContext) -> Bool {
        settings.hubSwitch(id) ?? context.wrapped[id] ?? false
    }

    /// Whether the Offline-Modus switches the feature off (it uses live data itself or needs a feature that does).
    public static func isAffectedByOfflineMode(_ id: FeatureID) -> Bool {
        if id.descriptor.usesLiveData { return true }
        return FeatureID.allCases.contains { $0.descriptor.usesLiveData && FeatureRegistry.requires(id, $0) }
    }

    /// Whether the feature uses live data (itself or through what it needs).
    public static func usesLiveData(_ id: FeatureID) -> Bool { isAffectedByOfflineMode(id) }

    public static func status(_ id: FeatureID, settings: FeatureSettings, context: FeatureContext) -> FeatureStatus {
        status(id, settings: settings, context: context, visited: [])
    }

    private static func status(_ id: FeatureID, settings: FeatureSettings, context: FeatureContext,
                               visited: Set<FeatureID>) -> FeatureStatus {
        let own = ownSwitch(id, settings: settings, context: context)
        func off(_ reason: FeatureOffReason) -> FeatureStatus {
            FeatureStatus(id: id, switchIsOn: own, offReason: reason, waiting: nil)
        }
        guard own else { return off(.switchedOff) }
        if settings.offlineMode && isAffectedByOfflineMode(id) { return off(.offlineMode) }
        var path = visited
        path.insert(id)
        for dependency in id.descriptor.dependencies where !path.contains(dependency) {
            if !status(dependency, settings: settings, context: context, visited: path).isOn { return off(.needs(dependency)) }
        }
        let waiting: FeatureLiveState? = usesLiveData(id) && context.live != .ready ? context.live : nil
        return FeatureStatus(id: id, switchIsOn: true, offReason: nil, waiting: waiting)
    }

    public static func isOn(_ id: FeatureID, settings: FeatureSettings, context: FeatureContext) -> Bool {
        status(id, settings: settings, context: context).isOn
    }

    // MARK: Text

    /// The sentence shown while the feature is off; nil while it is on.
    public static func explain(_ id: FeatureID, settings: FeatureSettings, context: FeatureContext) -> String? {
        let descriptor = id.descriptor
        switch status(id, settings: settings, context: context).offReason {
        case nil: return nil
        case .switchedOff: return "\(descriptor.title) ist aus. \(descriptor.offEffect)"
        case .offlineMode: return "Der Offline-Modus ist an. \(descriptor.offEffect)"
        case .needs(let other): return "\(descriptor.title) braucht „\(other.title)“. \(descriptor.offEffect)"
        }
    }

    /// The status line under the row: „an“, „an · wartet auf Live-Daten“, „aus“, „ausgeblendet · braucht Fahrplan & Echtzeit“.
    public static func statusLine(_ id: FeatureID, settings: FeatureSettings, context: FeatureContext) -> String {
        let status = status(id, settings: settings, context: context)
        let paused = id.descriptor.hiddenEntry == nil ? "pausiert" : "ausgeblendet"
        switch status.offReason {
        case .switchedOff: return "aus"
        case .offlineMode: return "\(paused) · Offline-Modus"
        case .needs(let other): return "\(paused) · braucht \(other.title)"
        case nil:
            switch status.waiting {
            case nil, .ready?: return "an"
            case .consentOpen?: return "an · wartet auf Live-Daten"
            case .declined?: return "an · Live-Daten sind abgelehnt"
            case .remoteOff?: return "an · ÖBB-Abfrage gerade abgeschaltet"
            case .noInternet?: return "an · kein Internet"
            }
        }
    }

    /// One note per hidden entry point, in registry order („Zug-Radar ist aus – der Radar-Knopf im Fahrplan ist ausgeblendet.“).
    public static func hiddenNotes(settings: FeatureSettings, context: FeatureContext) -> [FeatureHiddenNote] {
        FeatureRegistry.all.compactMap { descriptor in
            guard let entry = descriptor.hiddenEntry,
                  let reason = status(descriptor.id, settings: settings, context: context).offReason else { return nil }
            let text: String
            switch reason {
            case .switchedOff: text = "\(descriptor.title) ist aus – \(entry) ist ausgeblendet."
            case .offlineMode: text = "Offline-Modus – \(entry) ist ausgeblendet."
            case .needs(let other): text = "\(descriptor.title) braucht \(other.title) – \(entry) ist ausgeblendet."
            }
            return FeatureHiddenNote(id: descriptor.id, text: text)
        }
    }

    /// How many features are on, of all.
    public static func onCount(settings: FeatureSettings, context: FeatureContext) -> Int {
        FeatureID.allCases.filter { isOn($0, settings: settings, context: context) }.count
    }
}
