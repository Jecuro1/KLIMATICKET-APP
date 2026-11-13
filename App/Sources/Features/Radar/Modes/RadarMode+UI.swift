import SwiftUI
import MapKit
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

/// A city mode's chip while the map is too far out for it: a small zoom badge, and VoiceOver says „an, erscheint beim Heranzoomen“.
struct RadarModeChipZoom: ViewModifier {
    var mode: RadarMode
    var isOn: Bool
    var outOfZoom: Bool

    func body(content: Content) -> some View {
        let waits = isOn && mode.isCity && outOfZoom
        content
            .overlay(alignment: .topTrailing) {
                if waits {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(3)
                        .background(Theme.accent, in: .circle)
                        .offset(x: 3, y: -3)
                        .motionTransition(.pop)
                        .accessibilityHidden(true)
                }
            }
            .motionAnimation(Motion.snappy, value: waits)
            .accessibilityValue(RadarModesText.chipValue(isOn: isOn, outOfZoom: mode.isCity && outOfZoom))
    }
}

extension RadarView {
    /// The CI scenes of Bus, Bim and U-Bahn (`RadarModesScreenshotHost`): synthetic city fleets with the demo-only fast budget.
    func applyModesPreset(_ preset: RadarPreset) {
        model.adopt(schedulerConfig: .forRadar(syntheticCityDemo: true, sandboxed: LaunchMode.isSandboxed))
        let wien = RadarCityDemoFleet.stephansplatz
        switch preset {
        case .modesZoomHint:   // Austria (the default camera) with Bus on: the hint and the chip's zoom badge
            setModes(RadarModeSelection([.rail, .suburban, .bus]))
        case .modesCrowded:   // Wien at 0.12°: knots of vehicles make the city lane crowded and cut off
            setModes(RadarModeSelection(Set(RadarMode.allCases)))
            camera = .region(MKCoordinateRegion(center: wien.clCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)))
        default:   // Wien close up with all five modes
            setModes(RadarModeSelection(Set(RadarMode.allCases)))
            // Close enough that most vehicles are single plates (a Wien view of 0.12° would be groups of 10 to 25).
            camera = .region(MKCoordinateRegion(center: GeoPoint(latitude: 48.1920, longitude: 16.3750).clCoordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
            applyFilterScene(preset)
        }
    }

    /// The scenes of „Filter & Darstellung“ on the close Wien view.
    private func applyFilterScene(_ preset: RadarPreset) {
        switch preset {
        case .modesLegend:
            showsLegend = true
        case .modesDots:   // „Nur Punkte“, Groß, Gruppen aus
            model.display = RadarDisplay(label: .dots, size: .large, groups: false)
        case .modesFilter:   // the top of the sheet: Schnellwahl, Verkehrsmittel, Zugart
            model.filter = RadarFilter(trainClasses: [.rex, .s])
            openFilterSheet(page: .filter)
        case .modesFilterLines:   // the lower sections: Linie, Betreiber, Verspätung
            model.filter = RadarFilter(lines: ["13A", "U6"], onlyRealtime: true)
            filterScroll = "lines"
            openFilterSheet(page: .filter)
        case .modesDisplay:   // the Darstellung page with its preview
            model.display = RadarDisplay(label: .lineAndDestination, size: .large)
            openFilterSheet(page: .display)
        case .modesEmpty:   // a filter that matches nothing: the note says how many there would be, „Filter aus“ on the map
            model.filter = RadarFilter(lines: ["99X"])
        default:
            break
        }
    }

    private func openFilterSheet(page: RadarFilterSheet.Page) {
        filterPage = page
        filterDetent = .large
        showsFilter = true
    }
}
