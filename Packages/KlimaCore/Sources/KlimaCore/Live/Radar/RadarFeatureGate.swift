import Foundation

// The Zug-Radar's live loop and its three additions under one set of rules (docs/OEBB_LIVE.md §R11.3): the Pünktlichkeit layer
// (docs/RADAR_HEATMAP.md) loads all of Austria through the live loop, the Zeitreise (docs/RADAR_TIMETRAVEL.md) pauses the live loop while
// its scrubber is away from now, and the Cockpit-Ansicht (docs/RADAR_COCKPIT.md) stops both while it asks for its one train. Pure values:
// the radar view hands in what is on and open, and reads which loop runs and how a Zeitreise ends when the picture under it changes.
// `RadarFeatureGateTests` switches between the features in every order and checks that no two parts ever send at once.

public struct RadarFeatureGate: Equatable, Sendable {
    /// Whether the live data may be asked.
    public enum Access: Equatable, Sendable {
        /// Consent given, the switch on, no kill switch, online.
        case open
        /// Only the connection is missing: a Zeitreise is suspended, what it loaded stays for a quick return.
        case offline
        /// No consent, live data switched off, or the kill switch: a Zeitreise ends with everything it loaded.
        case closed
    }

    /// How a Zeitreise ends when the picture under it changes (`RadarTimeModel.reset` / `.suspend`).
    public enum TimeEnding: Equatable, Sendable {
        /// The access, the train layer or the rail-only modes are gone, or the Pünktlichkeit layer came on: everything ends.
        case reset
        /// Only the connection went: the Zeitreise ends like "Zurück zu Jetzt", its snapshots stay.
        case suspend
    }

    public var layers: MapLayerSelection
    public var access: Access
    /// Only Züge and S-Bahn are on (`RadarModeSelection.carriesOnlyTrains`, MARK: radarmodes): the Zeitreise's snapshots are of trains.
    public var railOnly: Bool
    /// The radar is visible and the app is active.
    public var sceneActive: Bool
    /// The Cockpit-Ansicht covers the radar.
    public var cockpitOpen: Bool
    /// The Zeitreise's card is expanded.
    public var timeOpen: Bool
    /// The Zeitreise's scrubber is away from now: its pins are the picture.
    public var timeAway: Bool

    public init(layers: MapLayerSelection = .initial, access: Access = .open, railOnly: Bool = true, sceneActive: Bool = true,
                cockpitOpen: Bool = false, timeOpen: Bool = false, timeAway: Bool = false) {
        self.layers = layers
        self.access = access
        self.railOnly = railOnly
        self.sceneActive = sceneActive
        self.cockpitOpen = cockpitOpen
        self.timeOpen = timeOpen
        self.timeAway = timeAway
    }

    /// The train layer is on and the live data may be asked.
    public var trainsOn: Bool { layers.isOn(.trains) && access == .open }

    /// The Pünktlichkeit layer is on and allowed, and the picture is of now: next to a Zeitreise's other time its numbers would be a lie.
    /// While it is on, the live loop is handed all of Austria as its view (`RadarModel.applyViewport`).
    public var heatOn: Bool { layers.isOn(.punctuality) && access == .open && !timeAway }

    /// Something needs the live loop's requests: the train layer or the Pünktlichkeit layer.
    public var loadsRadar: Bool { trainsOn || heatOn }

    /// The live loop (`RadarModel.run`) runs: the radar is visible, a layer needs it, the Zeitreise is at now and no cockpit covers it.
    public var liveLoopRuns: Bool { sceneActive && loadsRadar && !timeAway && !cockpitOpen }

    /// The Zeitreise is offered (its chip is shown): trains are on and allowed, only trains, and the Pünktlichkeit layer is off. Asked of the
    /// layer itself, not of `heatOn` (which is off while away): switching the layer on during a Zeitreise ends it.
    public var timeAvailable: Bool { trainsOn && !layers.isOn(.punctuality) && railOnly }

    /// `timeAvailable` without the connection: false only when the layers, the modes or the access end the Zeitreise for good.
    public var timeAllowed: Bool { layers.isOn(.trains) && !layers.isOn(.punctuality) && railOnly && access != .closed }

    /// The Zeitreise's loop runs: it is open or away from now, offered, and the radar is visible without a cockpit over it. It sends only while
    /// away from now.
    public var timeLoopRuns: Bool { timeAvailable && sceneActive && !cockpitOpen && (timeOpen || timeAway) }

    /// What a change from `old` to `new` does to a Zeitreise: nothing, an end with everything (`reset`), or an end that keeps the snapshots
    /// (`suspend`, only offline).
    public static func timeEnding(from old: RadarFeatureGate, to new: RadarFeatureGate) -> TimeEnding? {
        if old.timeAllowed && !new.timeAllowed { return .reset }
        if old.timeAvailable && !new.timeAvailable && new.timeAllowed { return .suspend }
        return nil
    }
}
