import SwiftUI
import MapKit
import KlimaCore

// Modes, map styles, presets, pins and failure copy of the Zug-Radar (split from RadarView.swift).

// MARK: radarmodes – the transport modes (`RadarMode`, `RadarModeSelection`) live in KlimaCore; their symbol and colour in `Modes/RadarMode+UI.swift`.

/// Base map styles. The train layer is the same in all of them; „Dunkel“ forces the dark map palette.
enum RadarMapStyle: String, CaseIterable, Identifiable {
    case standard, satellite, dark
    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .satellite: "Satellit"
        case .dark: "Dunkel"
        }
    }

    var symbol: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe.europe.africa"
        case .dark: "moon"
        }
    }

    var style: MapStyle {
        switch self {
        case .standard, .dark: .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
        case .satellite: .imagery(elevation: .flat)
        }
    }
}

/// Screenshot presets (CI): the same view with the filter sheet, a search or a zoomed-out map already open.
enum RadarPreset: String, Sendable {
    case live, filter, search, cluster, layers
    // MARK: radarall – about 1500 synthetic trains (demo only): the Austria-wide view and a zoomed one
    case allTrains, allTrainsZoom
    // MARK: radartime – the Zeitreise on synthetic trains (demo only): the scrubber at +45 minutes, the time-lapse playing, the snapshots loading
    case timeTravel, timeTravelPlaying, timeTravelLoading, timeTravelChip
    // MARK: radarheat – the Pünktlichkeit layer on synthetic trains (demo only): the map, the open panel, a cell, the panel at the largest text size
    case heat, heatPanel, heatLists, heatTrend, heatCell, heatAX5
    // MARK: radarmodes – Bus, Bim and U-Bahn on synthetic city fleets (demo only): Wien close up, Austria with Bus on, the legend, the crowded view
    case modesCity, modesZoomHint, modesLegend, modesCrowded

    /// The synthetic dense demo (`DemoRadarService(dense: true)`), only ever used by the CI screenshot hosts.
    var isDenseDemo: Bool { self == .allTrains || self == .allTrainsZoom }
    // MARK: radartime – the synthetic fleet with timetables (`Time/RadarTimeDemo.swift`).
    var isTimeDemo: Bool { self == .timeTravel || self == .timeTravelPlaying || self == .timeTravelLoading || self == .timeTravelChip }
    // MARK: radarheat – the synthetic trains with a delay cluster over Tirol (`RadarHeatDemo.swift`).
    var isHeatDemo: Bool { self == .heat || self == .heatPanel || self == .heatLists || self == .heatTrend || self == .heatCell || self == .heatAX5 }
    // MARK: radarmodes – the synthetic city fleets (`Modes/RadarCityDemo.swift`) with the demo-only fast budget.
    var isCityDemo: Bool { self == .modesCity || self == .modesZoomHint || self == .modesLegend || self == .modesCrowded }
}

/// Live copy for failures (Du-Form, no technical codes).
enum LiveMessage {
    static func text(for error: Error) -> String {
        guard let live = error as? LiveError else { return "Das hat gerade nicht geklappt. Versuch es gleich noch einmal." }
        switch live {
        case .offline, .network, .timeout: return "Keine Verbindung zu ÖBB – versuch es gleich noch einmal."
        case .rateLimited: return "ÖBB bittet um eine kurze Pause. Gleich geht es weiter."
        case .circuitOpen: return "Die Abfrage pausiert gerade. Probier es später noch einmal."
        case .blocked: return "ÖBB lässt gerade keine Abfragen zu. Bitte später erneut versuchen."
        case .disabled: return "Live-Daten sind gerade nicht verfügbar."
        default: return "Die Auskunft ist gerade nicht verfügbar."
        }
    }
}

/// A vehicle as drawn: its position at the moment (server position, or an estimate between two answers).
struct RadarPin: Identifiable, Hashable {
    var vehicle: RadarVehicle
    var coordinate: GeoPoint
    var isEstimate: Bool
    var delay: RadarDelayState
    var delaySeconds: Int?
    /// Direction to the next stop, clockwise from north; nil when the next stop has no coordinate.
    var bearing: Double?

    var id: String { vehicle.tripID }

    /// VoiceOver text: "Bus 13A, nach Hütteldorf, 6 Minuten verspätet, Position berechnet" (MARK: radarmodes – the mode's noun where the title has
    /// none, and always where the position comes from).
    var accessibilityText: String {
        var parts = [vehicle.line.map { RadarModesText.spokenLine(title: LinePresentation.title($0), kind: LinePresentation.kind($0)) } ?? "Fahrzeug"]
        if let direction = vehicle.direction { parts.append("nach \(direction)") }
        switch delay {
        case .cancelled: parts.append("fällt aus")
        case .onTime: parts.append("pünktlich")
        case .late:
            let minutes = max((delaySeconds ?? 0) / 60, 5)
            parts.append("\(minutes) Minuten verspätet")
        case .unknown: parts.append("Verspätung unbekannt")
        }
        parts.append(RadarModesText.positionNote(isEstimate: isEstimate))
        return parts.joined(separator: ", ")
    }
}

extension RadarDelayState {
    /// The ring colour of a marker: on time green, five minutes or more late orange, cancelled red, unknown grey.
    var tint: Color {
        switch self {
        case .onTime: Theme.positive
        case .late: Theme.summit
        case .cancelled: Theme.negative
        case .unknown: Theme.textTertiary
        }
    }
}
