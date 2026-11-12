import SwiftUI
import MapKit
import KlimaCore

// Modes, map styles, presets, pins and failure copy of the Zug-Radar (split from RadarView.swift).

/// Transport modes the radar can show (server-side product filter).
enum RadarMode: CaseIterable, Identifiable {
    case rail, suburban, bus, tram, subway
    var id: Self { self }

    var title: String {
        switch self {
        case .rail: "Züge"
        case .suburban: "S-Bahn"
        case .bus: "Bus"
        case .tram: "Bim"
        case .subway: "U-Bahn"
        }
    }

    var symbol: String {
        switch self {
        case .rail: "tram.fill"
        case .suburban: "tram"
        case .bus: "bus"
        case .tram: "tram.fill.tunnel"
        case .subway: "tram.circle"
        }
    }

    var products: ProductMask {
        switch self {
        case .rail: .rail
        case .suburban: .suburban
        case .bus: .bus
        case .tram: .tram
        case .subway: .subway
        }
    }
}

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

    /// The synthetic dense demo (`DemoRadarService(dense: true)`), only ever used by the CI screenshot hosts.
    var isDenseDemo: Bool { self == .allTrains || self == .allTrainsZoom }
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

    /// VoiceOver text: "RJX 66, nach Innsbruck Hbf, 5 Minuten verspätet, Position geschätzt".
    var accessibilityText: String {
        var parts = [vehicle.line.map { LinePresentation.title($0) } ?? "Zug"]
        if let direction = vehicle.direction { parts.append("nach \(direction)") }
        switch delay {
        case .cancelled: parts.append("fällt aus")
        case .onTime: parts.append("pünktlich")
        case .late:
            let minutes = max((delaySeconds ?? 0) / 60, 5)
            parts.append("\(minutes) Minuten verspätet")
        case .unknown: parts.append("Verspätung unbekannt")
        }
        if isEstimate { parts.append("Position geschätzt") }
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
