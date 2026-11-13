import SwiftUI
import KlimaCore

// MARK: radarmodes – how a transport mode of the radar looks (docs/RADAR_MODES.md §5): the symbol and the colour of the app's transport mode, so
// the chip, the legend and the counts use the same signs as the Fahrplan (`TransportMode.symbolName`, `Theme.modeColor`).

extension RadarMode {
    var symbol: String { transportMode.symbolName }
    var color: Color { Theme.modeColor(transportMode) }
}

extension RadarView {
    /// A mode chip: the model asks for the new modes and the choice is stored per device.
    func toggleMode(_ mode: RadarMode) {
        var next = model.modes
        guard next.toggle(mode) else { return }   // the last mode stays on
        setModes(next)
    }

    /// The modes from the chips or the filter sheet: to the model (it asks for them) and to the device's settings.
    func setModes(_ modes: RadarModeSelection) {
        model.modes = modes
        modesRaw = modes.storageValue
    }
}

extension RadarView {
    /// The Zeitreise's clock chip is missing only because a city mode is on: a short hint takes its place (the rest of the rule is unchanged).
    var timeHintShown: Bool {
        trainsOn && !layers.isOn(.punctuality) && !model.carriesOnlyTrains && !travel.isAway
    }
}
