import SwiftUI
import KlimaCore

// MARK: radarheat – the markers of the Pünktlichkeit layer: trains as small dots (the heat is the picture, the train marker with its
// line plate would hide it), groups of trains as a small count, the numbered hot spots. The number of markers is the radar's own
// (`RadarClustering`: at most about 150 cells a screen), not one per train.

/// A train as a dot. The colour is its bucket (green under 5 minutes, orange 5 to 15, red over 15), and so that colour is not the only
/// signal the size grows with the delay and a cancelled train or one without realtime data is an open ring.
struct HeatTrainDot: View {
    var pin: RadarPin
    var isSelected = false

    private var bucket: HeatBucket {
        RadarHeat.bucket(delaySeconds: pin.delaySeconds, isCancelled: pin.delay == .cancelled)
    }

    private var diameter: CGFloat {
        switch bucket {
        case .onTime: 9
        case .delayed: 11
        case .severe: 13
        case .cancelled: 11
        case .noRealtime: 9
        }
    }

    var body: some View {
        let tint = bucket.tint
        let open = bucket == .cancelled || bucket == .noRealtime
        ZStack {
            if open {
                Circle().fill(Theme.surface).overlay(Circle().strokeBorder(tint, lineWidth: 2.5))
            } else {
                Circle().fill(tint).overlay(Circle().strokeBorder(Color.white.opacity(0.95), lineWidth: 1.5))
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
        .scaleEffect(isSelected ? 1.5 : 1)
        .motionAnimation(Motion.snappy, value: isSelected)
        .frame(width: 28, height: 28)   // the tap target is larger than the dot
        .contentShape(.circle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pin.accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Several trains in one spot of the grid, as a small ring: the heat under it already says how late they are and how many there
/// are, a number would only cover it. The ring is the worst state inside; its size follows the group. A tap zooms in; the count is
/// in the spoken label.
struct HeatClusterDot: View {
    var cluster: RadarCluster
    var noun = "Züge"

    private var diameter: CGFloat { cluster.count >= 10 ? 17 : 14 }

    var body: some View {
        let worst: HeatBucket = cluster.cancelledCount > 0 ? .cancelled : (cluster.lateCount > 0 ? .delayed : .onTime)
        Circle()
            .fill(Theme.sheetBackground)
            .overlay(Circle().strokeBorder(worst.tint, lineWidth: 3.5))
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
            .frame(width: 28, height: 28)
            .contentShape(.circle)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(cluster.count) \(noun) an dieser Stelle, \(cluster.lateCount) verspätet")
            .accessibilityHint("Tippen zum Heranzoomen")
            .accessibilityAddTraits(.isButton)
    }
}

/// The number of a hot spot on the map. A tap opens the trains of its cell.
struct HeatHotspotBadge: View {
    var spot: HeatHotspot
    var isSelected = false

    var body: some View {
        Text("\(spot.rank)")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.background)
            .frame(width: 28, height: 28)
            // A hexagon like the cells, so a number of the map is never mistaken for a station group (a round bubble with a count).
            .background(HexagonShape().fill(Theme.textPrimary))
            .overlay(HexagonShape().stroke(Theme.background.opacity(0.9), lineWidth: isSelected ? 3 : 1.5))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .scaleEffect(isSelected ? 1.15 : 1)
            .motionAnimation(Motion.snappy, value: isSelected)
            .frame(width: 32, height: 32)
            .contentShape(.circle)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Brennpunkt \(spot.rank), \(RadarHeatText.place(spot.placeName))")
            .accessibilityHint("Züge dieses Gebiets anzeigen")
            .accessibilityAddTraits(.isButton)
    }
}
