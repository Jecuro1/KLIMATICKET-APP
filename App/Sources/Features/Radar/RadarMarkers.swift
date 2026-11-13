import SwiftUI
import MapKit
import KlimaCore

// Vehicle marker and cluster bubble of the Zug-Radar, plus the coordinate and follow-target helpers (split from RadarView.swift).

/// One vehicle on the map: its line plate (MARK: radarmodes – the Wegzeichen plate of its line, `RadarModePlate`), the delay ring, a dashed ring
/// for estimates and the direction arrow towards the next stop.
struct RadarMarker: View {
    var pin: RadarPin
    var isSelected = false
    /// MARK: radarmodes – „Darstellung“: size, dots, destination, arrow. `.standard` is the radar's own look.
    var style: RadarMarkerStyle = .standard
    /// MARK: radar2 – how a part marks this vehicle (radarmine): dimmed, highlighted, a star or a number. `.plain` changes nothing.
    var decoration: RadarMarkerDecoration = .plain

    var body: some View {
        let mode = pin.vehicle.line?.mode ?? .other
        VStack(spacing: 1) {
            // MARK: radarmodes – the Wegzeichen plate, or a dot of its shape and fill („Nur Punkte“), and the destination („Linie und Ziel“)
            if style.dots {
                RadarModeDot(badge: .radar(pin.vehicle.line, size: .xs), delay: pin.delay, isEstimate: pin.isEstimate, height: style.dotHeight)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            } else {
                RadarModePlate(badge: .radar(pin.vehicle.line, size: style.plateSize), delay: pin.delay, isEstimate: pin.isEstimate,
                               size: style.plateSize)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                if let destination = style.destination { RadarDestinationLabel(text: destination) }
            }
            if let bearing = pin.bearing, decoration.showsArrow, style.arrows {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.modeColor(mode))
                    .rotationEffect(.degrees(bearing))
                    .frame(height: 8)
            }
        }
        .overlay(alignment: .topTrailing) { RadarDecorationBadge(decoration: decoration) }   // MARK: radar2
        .background { RadarDecorationHalo(decoration: decoration) }   // MARK: radar2
        .opacity(decoration.opacity)   // MARK: radar2
        .scaleEffect(isSelected ? 1.18 : 1)
        .motionAnimation(Motion.snappy, value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pin.accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A cluster of vehicles at this zoom. The ring shows the worst state inside it.
struct RadarClusterBubble: View {
    var cluster: RadarCluster
    var noun = "Fahrzeuge"

    var body: some View {
        let worst: RadarDelayState = cluster.cancelledCount > 0 ? .cancelled : (cluster.lateCount > 0 ? .late : .onTime)
        Text("\(cluster.count)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: 34, minHeight: 34)
            .padding(.horizontal, 4)
            .background(Theme.accent, in: .circle)
            .overlay(Circle().strokeBorder(worst.tint, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(cluster.count) \(noun) an dieser Stelle, \(cluster.lateCount) verspätet")
            .accessibilityHint("Tippen zum Heranzoomen")
            .accessibilityAddTraits(.isButton)
    }
}

extension GeoPoint {
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension RadarVehicle {
    /// Follows the whole run: first stop to last stop (the vehicle has no planner context).
    var followTarget: LiveFollowTarget? {
        guard let first = stopovers.first, let last = stopovers.last else { return nil }
        return LiveFollowTarget(tripID: tripID, lineName: line.map { LinePresentation.title($0) } ?? "Zug",
                                boardingStop: first.location, alightStop: last.location,
                                plannedDeparture: first.departure?.planned, plannedArrival: last.arrival?.planned)
    }
}
